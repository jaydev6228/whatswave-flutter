# Production release plan

Audited 2026-10-13 against commit `62d9fc0` (branch `e2e-encryption`).
Flutter 3.44.8 / Dart 3.12.2. `flutter analyze`: 0 issues. 110 Dart test
files, 2 rules test files, all green.

The code quality is not the problem. The problems are store compliance, one
licence conflict, and a missing server tier.

---

## Part 1 — Blockers. The app cannot be submitted until these are done.

### B1. The GPL-3.0 dependency blocks the Apple App Store

`libsignal_protocol_dart` 0.8.2 is **GPL-3.0 with no linking exception**. I
checked every package in the resolved tree: it is the only copyleft one.
Everything else is MIT, BSD, or Apache-2.0.

GPL-3.0 §10 forbids imposing "any further restrictions" on recipients. The
App Store terms do exactly that — a copy is tied to an Apple ID and limited
to devices the account holder controls. This is not theoretical: VLC was
pulled from the App Store in 2011 over this clause and only returned after
relicensing to a permissive licence.

The distinction that matters: **relicensing WhatsWave does not fix this.**
You own WhatsWave's code, so you could add an App Store exception to your own
`LICENSE` at will. You cannot grant an exception for code you do not own, and
the GPL obligation here flows from MixinNetwork's package.

#### Permissive alternatives — surveyed 2026-10-13

There is **no permissively licensed pure-Dart ratchet implementation.** Every
Dart package implementing X3DH/Double Ratchet is GPL or AGPL. Verified by
reading each `LICENSE` file, because two of them are advertised misleadingly:

| Package | Actual licence | Usable on the App Store? |
|---|---|---|
| `libsignal_protocol_dart` 0.8.2 (current) | GPL-3.0, no exception | No |
| `libsignal` 8.0.0 (djx-y-z wrapper) | AGPL-3.0 | **No — see note** |
| `vodozemac` 0.8.0 (famedly Dart bindings) | **AGPL-3.0** | No |
| `olm` 3.1.0 (famedly Dart bindings) | Apache-2.0 | Licence fine, library dead |
| `cryptography` 2.9.0 (dint) | Apache-2.0 | Yes — primitives only, no ratchet |

Three traps in that table:

- **`libsignal` advertises "AGPL-3.0 with an app store exception."** Its own
  README then says the exception *"covers only the code in this repository; it
  does not extend to Signal's `libsignal` contained in the precompiled
  binaries."* Upstream `signalapp/libsignal` is plain AGPL-3.0 with no such
  grant — I checked, it is tracked as an open issue. So this package is
  strictly worse than what we have: same blocker, plus AGPL network copyleft.
- **famedly's `vodozemac` Dart bindings are AGPL-3.0** even though upstream
  `matrix-org/vodozemac` is Apache-2.0. The badge on pub.dev lists the
  dependency licences alongside its own, which is easy to misread.
- **`olm`'s bindings genuinely are Apache-2.0**, but `matrix-org/olm` is
  **archived** — Matrix deprecated libolm in favour of vodozemac. And
  `flutter_olm`, which you need to build the native library for mobile, is
  AGPL-3.0. Dead end.

#### The two that actually work

Both are Rust, so both need a Dart binding via `flutter_rust_bridge`. That is
the point in your favour: **you write the binding, so you own it and license
it however you like.** The copyleft question disappears because neither
upstream is copyleft.

| | Library | Licence | Maps onto your design |
|---|---|---|---|
| **A** | [`matrix-org/vodozemac`](https://github.com/matrix-org/vodozemac) | Apache-2.0, active | Olm = Double Ratchet, Megolm = group ratchet. Near 1:1 with the pairwise sessions + sender keys you already built |
| **B** | [`openmls/openmls`](https://github.com/openmls/openmls) | **MIT**, active, 1k stars | MLS (RFC 9420). Groups scale O(log n) instead of your current O(n²) client fanout |

**A is the smaller change.** Your `WhatsWaveSignalStore`,
`SenderKeyDistributor`, and envelope format all survive — Olm sessions replace
`SessionCipher`, Megolm sessions replace sender keys, and the store interface
is the same shape. Estimate 3–4 weeks.

**B is better long term** and is the MIT option if that matters to you. MLS
fixes the quadratic group fanout flagged in Part 3 for free. But MLS assumes a
Delivery Service that orders and fans out commits, which this app does not
have — it would land after B7. Estimate 6–8 weeks, and it is the right answer
if you are building the server tier anyway.

#### One upside worth noting

The GPL-3.0 relicence of WhatsWave was forced *only* by this dependency. Drop
it and you own every line again — `LICENSE.proprietary.bak` is still in the
repo, so you can go back to proprietary, or MIT, or keep GPL by choice rather
than obligation.

#### Order of operations

1. **Email MixinNetwork this week.** A GPL copyright holder can grant an
   App Store exception; Signal added exactly this kind of §7 permission for
   their own apps. Costs one email and may end the problem outright.
2. If they decline, take **A (vodozemac)** unless you have already committed
   to building the server tier, in which case take **B (openmls)**.

**Do not reimplement the Double Ratchet from `libsignal_protocol_dart`'s
source.** You and I have both read it; a reimplementation is a derivative work
and the licence question gets worse, not better. Starting from vodozemac or
openmls has no such taint.

### B2. Release builds are signed with debug keys

`android/app/build.gradle.kts:33-36` still has Flutter's template:

```kotlin
release {
    // TODO: Add your own signing config for the release build.
    signingConfig = signingConfigs.getByName("debug")
}
```

Play rejects debug-signed bundles. Generate an upload keystore, put it outside
the repo, reference it through `android/key.properties`, and enrol in Play App
Signing. One hour of work, and it must happen before anything else can be
tested on real distribution rails.

### B3. No `PrivacyInfo.xcprivacy` for the app target

The only privacy manifests in the tree belong to `WebRTC-SDK` inside `Pods/`.
The app target has none.

Apple has required this since May 2024 for apps that touch "required reason"
APIs. This app touches several: `UserDefaults` (via `shared_preferences`),
file timestamps and disk space (via `path_provider` and
`flutter_cache_manager`), and active keyboard info. Submitting without it is a
hard rejection, and the rejection email does not tell you which API tripped it.

### B4. No account deletion anywhere in the codebase

I grepped for `deleteAccount`, `deleteUser`, and every variant. Nothing.

Apple Guideline 5.1.1(v) requires in-app account deletion for any app that
supports account creation. Google Play's Data deletion policy requires both an
in-app path and a web-reachable one. Both are hard rejections.

This is more work than it looks here, because deletion has to cascade:
`users/{uid}`, `signalIdentities/{uid}`, `signalPreKeys/{uid}/keys/*`,
`signalBackups/{uid}`, `signalKeyDeliveries/{uid}/inbox/*`, `pushTokens/{uid}`,
the user's Storage objects, and their membership in every `chatThreads`
document. Client-side deletion cannot do the last two safely — it needs the
Admin SDK, which means it depends on B7.

### B5. No privacy policy and no terms of service

Neither exists in the repo nor as a reachable URL, and `settings_screen.dart`
has no row linking to one. Both stores require a live URL at submission.

For this app the policy has to specifically cover: contact-book upload
(`flutter_contacts`), precise location sharing (`geolocator`), biometric
unlock (`local_auth`), and crash/analytics collection (Crashlytics,
Analytics). Apple's Privacy Nutrition Label and Play's Data Safety form must
then agree with it — a mismatch is its own rejection.

### B6. Encryption export compliance is not declared

`ITSAppUsesNonExemptEncryption` is absent from `Info.plist`, and the app now
ships a real Signal Protocol implementation plus AES-256-GCM at rest.

Three separate obligations, and these are law rather than store policy:

1. Add `ITSAppUsesNonExemptEncryption = true` to `Info.plist`, or every single
   upload stalls on a manual questionnaire.
2. File a self-classification report with US BIS. You almost certainly qualify
   as mass-market under ECCN 5D992.c, but qualifying still requires filing,
   annually, to BIS and the NSA.
3. Apple will ask about the French encryption declaration during submission.

Budget a week of calendar time for the BIS filing even though the work is an
afternoon.

### B7. Push notifications are collected but never sent

`lib/core/integrations/backend_integration_bundle.dart:176` writes the FCM
token to `pushTokens/{uid}`. The code comment says it plainly:

> so a future server-side component

Nothing reads that collection. There is no `functions/` directory, and
`firebase.json` has no functions block. The only server-side code in the
repository is the single LiveKit token endpoint on Vercel.

So today: a message to a backgrounded or offline user produces no
notification, and an incoming call never rings an unopened app. For a
messaging app that is a functional blocker, not a polish item. It also blocks
B4 (cascade delete) and every item in Part 3.

---

## Part 2 — Required before release, not strictly blocking

| # | Item | Why |
|---|---|---|
| R1 | Upgrade the dependency tree — every direct dep is behind. `livekit_client` 2.9.0→2.13.1 and the Firebase stack are the ones that matter. | Stores reject SDKs with known CVEs; LiveKit moves fast on WebRTC security fixes |
| R2 | Resolve the two deliberate pins: `file_picker` 10.3.10 (latest 13.1.0) and `flutter_secure_storage` 10.3.4 (latest 11.2.0, held for a win32 conflict) | Both are now several majors behind; the win32 conflict may have cleared |
| R3 | Server-side abuse prevention and rate limiting — none exists | Without it one script can run your Firestore bill to five figures overnight |
| R4 | Replace `LocalAppTelemetry` with a real vendor behind `AppTelemetry` (the seam is already there) | You cannot debug a production incident from `debugPrint` |
| R5 | Content moderation and a report/block flow for users | Both stores require a reporting mechanism for UGC apps; Apple 1.2 is explicit |
| R6 | Age rating questionnaires, and decide whether you need COPPA/age gating | A messaging app with UGC rates 17+/Mature unless you moderate |
| R7 | Rotate the LiveKit key `API8miTMnPwbZaZ` and delete `~/Downloads/whatswave-dev-jaydev-ebae8-0645500c9405.json` | Still outstanding from the last session |
| R8 | Create a separate production Firebase project | You are currently pointed at `whatswave-dev-*` |

---

## Part 3 — The scale question, answered honestly

> "think app can handle million request msg/call/post etc per second"

**The current architecture cannot, and no amount of tuning gets it there.**
This is worth being blunt about because it changes what you build next.

### Where it actually tops out

Every client talks to Firestore directly. The only server is one Vercel
function that mints LiveKit tokens. There is no fanout tier, no queue, no
cache, no rate limiter.

Three measured ceilings:

**Per-document writes.** Firestore sustains roughly **1 write/second per
document**. Typing indicators write `typingByUid.$uid` onto the *thread*
document (`firestore_chat_repository.dart:626`). A 50-person group with four
people typing exceeds that limit on a single document — and every keystroke
fans a snapshot out to all 50 listeners. This is the first thing that will
break, and it will break at about 20 active users in one group, not at a
million.

**Cost.** Firestore document writes run about $0.18 per 100,000. One million
writes per second is ~$180/second, roughly **$460 million per month**, before
reads, egress, or storage. The architecture is not the binding constraint
here; arithmetic is.

**Client-side fanout.** Group sender-key distribution is driven by the sending
client (by design — there are no Cloud Functions). Each member distributes its
own key to every other member. That is O(n²) client writes per group, which is
sound for a 50-person group and quadratically wrong for a 5,000-person one.

### What a million messages per second actually requires

WhatsApp handles on the order of 100 billion messages per day — close to your
figure — on Erlang/BEAM, custom-built servers, and their own routing fabric.
It is thousands of machines and a team of hundreds. It is not a Firestore
configuration.

### The staged target I would actually aim at

| Stage | Capacity | What it needs |
|---|---|---|
| **Now** | low thousands of users | fix B1–B7 and ship |
| **1** | ~50k DAU | Cloud Functions for push fanout, move typing indicators to Realtime Database (built for ephemeral high-frequency writes, priced per-GB not per-write), rate limiting |
| **2** | ~500k DAU | dedicated message service, Redis for presence, sharded counters, CDN for media, drop client-side sender-key fanout for a server-assisted channel |
| **3** | millions | leave Firestore for the message path entirely; Cassandra/ScyllaDB or similar, own WebSocket gateway, regional sharding |

Stage 1 is the only one worth planning now. Stages 2 and 3 are answers to
problems you do not have, and designing for them today is the most expensive
mistake available.

**One concrete change worth making before launch** regardless: move typing
indicators and presence off Firestore documents and onto Realtime Database.
It is already in your Firebase project, it is the right tool for ephemeral
high-frequency state, and it removes the ceiling that bites first.

---

## Part 4 — Test plan

### What exists

- 110 Dart test files, 2 Firestore rules test files, all passing
- CI: `flutter analyze`, `flutter test`, rules tests under the emulator,
  Android and iOS build smoke
- Crypto round-trip tests: 1:1, out-of-order, group across three members,
  sender-key rotation after removal, backup wrong-then-right passphrase

### What is missing

**1. Screen-size coverage — nothing automated today.**

Golden tests are the right tool and need no new dependency. Render each screen
at five sizes and commit the images; CI then fails on any layout regression:

```dart
// test/golden/screen_sizes_test.dart
const sizes = {
  'iphone_se':     Size(375, 667),   // smallest supported
  'iphone_17':     Size(402, 874),
  'iphone_17_max': Size(440, 956),
  'android_small': Size(360, 640),   // most common low-end Android
  'tablet':        Size(834, 1112),
};
```

Run `flutter test --update-goldens` once, eyeball every image, commit. Start
with the five screens most likely to break: conversation, chat list, call
experience, the new safety-number screen, and the passphrase backup screen.
The last two have never been seen on a small device.

Add to the same suite: `textScaleFactor: 2.0` (Apple requires Dynamic Type
support), and both light and dark themes.

**2. On-device integration tests — `integration_test/` does not exist.**

Widget tests cannot catch what will actually break: real sqflite, real
isolates, real Keychain, real platform channels. Four flows are worth it:

- sign in → send a message → force-quit → relaunch → message still there
- airplane mode → send → relaunch → the failed send and its retry survive
- fresh install → restore from passphrase → safety number unchanged
- sign out → sign in as a different user → no trace of the first user

That last one tests a real data-leak path you fixed; nothing currently proves
it stays fixed.

**3. Resiliency — the matrix I would actually run**

The failure modes specific to this app, all manual, all worth doing once per
release:

| Scenario | What it should do | What it might do |
|---|---|---|
| WiFi → cellular mid-send | message delivers | duplicate send |
| Airplane mode for 24h, then online | queued sends flush in order | out-of-order ratchet, permanent decrypt failure |
| Peer reinstalls the app | "security code changed" notice | silent failure, or trust-on-first-use with no warning |
| Device clock set 2 days back | messages still send | Firebase token rejected, opaque error |
| Firestore outage (block the domain) | offline banner, cached reads | hang with no feedback |
| Keychain wiped (restore from backup) | prompt to restore passphrase | "Failed to unwrap key" crash loop |
| 200MB video on a 3G connection | streams, progress accurate | OOM |
| Same message decrypted twice | served from local store | `DuplicateMessageException` |

Rows 3, 6, and 8 are the ones I would bet on finding a bug.

**4. Load testing — only one thing is worth testing**

The Vercel token endpoint is your only server, so it is the only thing with a
load profile you can meaningfully measure. `k6`, 30 lines, run once:

```bash
k6 run --vus 200 --duration 60s load/token_endpoint.js
```

Firestore does not need load testing — Google's limits are published and your
code either stays under them or does not. Read the per-document write limit
and audit against it instead; that is cheaper and more accurate than
generating traffic.

**5. Accessibility**

Apple rejects on this more than people expect. Run `flutter test` with the
accessibility guidelines matchers (`meetsGuideline(textContrastGuideline)`,
`androidTapTargetGuideline`, `labeledTapTargetGuideline`) over the main
screens. It is three lines per screen and catches contrast and tap-target
failures automatically.

### Suggested ordering

1. Goldens at five sizes — highest value per hour, catches the most
2. The four integration tests
3. Accessibility matchers in CI
4. The resiliency matrix, manually, once B1–B7 are done
5. k6 against the token endpoint

---

## Sequencing

**Week 1** — Email MixinNetwork about the licence (B1). Upload keystore (B2).
Privacy manifest (B3). Export compliance plist key and start the BIS filing
(B6).

**Weeks 2–3** — Cloud Functions for push fanout (B7), then account deletion on
top of it (B4). Privacy policy and terms, hosted (B5). Dependency upgrades
(R1, R2).

**Week 4** — Goldens and integration tests. Move typing indicators to Realtime
Database. Production Firebase project (R8).

**Week 5** — Rate limiting (R3), telemetry vendor (R4), report/block flow (R5).
Resiliency matrix. TestFlight and Play internal testing.

**Blocked on B1 throughout.** If MixinNetwork declines and you need iOS, insert
the MLS migration and add four to five weeks.
