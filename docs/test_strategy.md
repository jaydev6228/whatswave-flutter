# Test strategy

## Philosophy

Every slice should ship with happy and sad path coverage. "Sad path" means more than exceptions:

- Empty state
- Loading state
- Validation failure
- Permission denied
- Offline state
- Partial data state
- Backend failure state
- Recovery path

## Test layers

### Unit tests

Use for:

- Controllers
- Use cases
- Validators
- Mapper logic
- Repository behavior

### Widget tests

Use for:

- Primary screens
- Important reusable widgets
- Theme behavior
- Navigation shell interactions
- Error and empty states

### Security rules tests

`firestore.rules` and `storage.rules` are the app's real authorization
boundary. Every per-thread read gate, per-field admin check and per-owner
write check lives there rather than in Dart -- a modified client talks to
Firebase directly, so no Dart test can stand in for them.

```bash
npm install        # once
npm run test:rules
```

Runs `test/rules/*.test.mjs` against the Firestore and Storage emulators via
`@firebase/rules-unit-testing`, using the committed `firebase.test.json`
(rules paths and emulator ports only -- no project id or credentials, unlike
the gitignored `firebase.json`). The emulators need a JDK;
`scripts/run-rules-tests.mjs` finds one automatically, including the JDK
Android Studio bundles, so no extra install is normally required.

Cover both directions for every rule: the legitimate operation must be
allowed *and* each way of abusing it must be denied. Asserting only the
denials lets a rule that denies everything pass, and asserting only the
happy path is how the `starredBy` escalation below survived.

What this already caught, on its first run: a participant could write any
uid into a message's `starredBy`, and because the collection-group rule
grants read access to every uid listed there, that handed a **non-participant
read access to that message**. The rule checked only one direction of the set
change, and `hasOnly` on an empty set is vacuously true.

### Integration tests

`integration_test/` holds four on-device flows. See "Layer 4".

---

# UI and functional automation plan

Added 2026-10-13. The goal as stated was "100% bug free, UI accurate on any
device on both OS." Taking that seriously means first replacing it with
something measurable, because 100% bug free is not a state software reaches --
it is a claim that cannot be verified, so it cannot be used as a gate.

## The four gates that replace it

| Gate | Measured by | Now | Target |
|---|---|---|---|
| Every screen renders clean across the layout matrix | `screen_coverage_guard_test` | 12 / 36 | 36 / 36 |
| No layout regression reaches `main` | CI, on every push | enforced | enforced |
| Crash-free sessions | Crashlytics, in production | not measured | > 99.5% |
| Every bug fixed gets a regression test first | code review | informal | required |

Gate 1 is the one that answers "UI accurate on any device." Gate 3 is the only
honest answer to "bug free" -- you do not prove absence of bugs, you measure
their rate and drive it down.

## Why layout can be automated without a device farm

Flutter renders its own widgets, so given the same logical size, text scale and
theme, the output is identical on both platforms. Verified today: a widget test
fails on `RenderFlex overflowed`, **including overflow that only appears at
large text scale**, via the `expect(tester.takeException(), isNull)` already in
`pumpWhatsWaveAppForDevice`.

That makes layout testing nearly free. It also bounds what the device farm is
for: platform channels, real storage, real biometrics -- not layout.

Only two UI files branch on platform (`location_map_preview.dart`,
`app_permission_service.dart`), so the matrix needs no platform axis. Those two
branches do need `debugDefaultTargetPlatformOverride`, which no test currently
uses.

## Layer 1 -- the layout matrix (landed)

`test/support/device_matrix.dart` now carries two axes:

```dart
layoutMatrix   = [smallestPhoneProfile (320x568), tabletProfile (768x1024)]
layoutVariants = [defaultVariant, largeTextVariant (2.0), darkVariant]
```

320pt is the width that matters most and had never been rendered: iPhone SE
(1st gen) and the low-end Android phones that are a large share of installs
outside the US. Six configurations per screen, fast enough for every push.

`test/layout/screen_coverage_guard_test.dart` is the forcing function. It
enumerates `lib/**/*_screen.dart` and fails when a screen is in neither
`_covered`, `_exemptDebugOnly`, nor `_pendingCoverage`. It also fails on stale
names, which caught a screen that did not exist on its first run. The
`_maxPendingScreens` ratchet means the backlog can only shrink.

**Remaining work: drain the 21 screens in `_pendingCoverage`.** Highest risk
first, because these have never been rendered at any non-default size:
`settings_screen`, `contact_info_screen`, `call_experience_screen`,
`new_group_screen`, `attachment_viewer_screen`.

One gap this layer does not close: `setSurfaceSize` does not simulate a notch
or home indicator, and 43 files use `SafeArea` or `viewPadding`. Add a
`MediaQueryData(viewPadding: EdgeInsets.only(top: 59, bottom: 34))` variant for
the Dynamic Island case.

## Layer 2 -- accessibility gates (half a day, no new dependency)

Four matchers ship with `flutter_test` and Apple rejects on all four:

```dart
await expectLater(tester, meetsGuideline(textContrastGuideline));
await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
```

Add them to the same per-screen loop as Layer 1. Expect real failures --
`labeledTapTargetGuideline` fails on any icon-only button without a semantics
label, and this app has many.

## Layer 3 -- golden tests, selectively (2 days)

Goldens catch what overflow detection cannot: wrong colour, wrong spacing,
misalignment, and content clipped without technically overflowing.

They also churn -- every intentional design change rewrites the images -- and
font rasterisation differs between macOS and CI's Linux, so goldens generated
locally will fail in CI.

So: **goldens only on screens whose design is settled**, generated in CI only.
Start with the five whose layout is both stable and load-bearing: chat list,
conversation, call experience, safety number, passphrase backup. The last two
have never been seen on a small device at all.

Do not golden the 21 screens in the backlog. Overflow plus accessibility
checks give most of the value at none of the churn.

## Layer 4 -- integration tests on real devices (1 week)

`integration_test/` holds four flows. It is the only layer that exercises
real sqflite, real Keychain, real isolates and real platform channels --
none of which a widget test touches. They destroy local app state on the
device they run on, so use a test device or a fresh simulator.

Four flows, chosen because each one covers a failure that has already happened
or that the crypto work makes possible:

1. sign in, send a message, force-quit, relaunch -- message still there
2. airplane mode, send, relaunch -- the failed send and its retry survive
3. fresh install, restore from passphrase -- safety number unchanged
4. sign out, sign in as a different user -- no trace of the first user

Flow 4 guards a real data-leak path that was fixed but has no test proving it
stays fixed.

**Device matrix:** Firebase Test Lab, which you already have through Firebase.
It runs both OSes on physical hardware, so it covers fragmentation that no
simulator does.

**On permission dialogs:** `integration_test` cannot tap native permission
prompts, and this app requests camera, microphone, contacts, location, photos
and biometrics. The usual answer is to add `patrol`, which drives native UI --
but it is a heavy dependency with its own platform risk. Pre-granting is
cheaper and adds nothing to `pubspec.yaml`:

```bash
adb shell pm grant com.tsjaydevra.whatswave android.permission.CAMERA
xcrun simctl privacy booted grant camera com.tsjaydevra.whatswave
```

Revisit `patrol` only if a flow genuinely needs to assert on the dialog itself.

## Layer 5 -- production safety net

No amount of pre-release testing substitutes for this:

- Play staged rollout starting at 1%, with Crashlytics velocity alerts
- TestFlight external group before any App Store release
- A crash-free-sessions gate on promotion, not a vibe check

## What none of this catches

Worth being explicit, so the gates are not mistaken for proof:

- **Layout automation** cannot catch wrong *content*, bad animation timing, or
  platform-specific text rendering.
- **Goldens** cannot catch anything behind an interaction you did not script.
- **Integration tests** cannot catch real network conditions or device
  fragmentation beyond the matrix you pay for.
- **Nothing here** catches crypto logic errors (those need property-based
  tests over the ratchet) or race conditions (those need the resiliency matrix
  in `production_release_plan.md`, run by hand).

## Sequencing

| Order | Work | Effort | Why first |
|---|---|---|---|
| 1 | Drain the 21-screen backlog, 6 configs each | 3-4 days | Largest gap, cheapest coverage, no new dependency |
| 2 | Accessibility matchers into the same loop | 0.5 day | Free, and Apple rejects on it |
| 3 | `viewPadding` notch variant | 0.5 day | 43 files use SafeArea and none are tested for it |
| 4 | Goldens on the five settled screens, CI-generated | 2 days | Catches what overflow cannot |
| 5 | Four `integration_test` flows | 3 days | Only layer proving real storage and keystore |
| 6 | Firebase Test Lab wiring in CI | 1 day | Real hardware, both OSes |
| 7 | Platform-override tests for the two adaptive files | 0.5 day | Untested branches |

Roughly two and a half weeks to all seven. Items 1 and 2 are the ones that
move Gate 1 from 12/36 to 36/36, and they need no new dependency and no
infrastructure.
