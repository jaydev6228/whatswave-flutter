# WhatsWave Flutter

`WhatsWave Flutter` is a brand-new Flutter codebase for a full-featured real-time messaging app -- chats and groups, status updates, communities, and voice/video calling. It is intentionally separate from the existing iOS Swift project and does not modify that app.

## Demo

Running on the iOS Simulator (iPhone 17 Pro).

[![Watch the demo video](docs/screenshots/03-chats-list.png)](docs/demo/whatswave-demo.mp4)

<sub>▶️ Click the screenshot above (or [this link](docs/demo/whatswave-demo.mp4)) to watch/download the full screen recording.</sub>

| Auth | Profile setup | Chats list | Chat detail |
|---|---|---|---|
| ![Auth](docs/screenshots/01-auth-phone-number.png) | ![Profile setup](docs/screenshots/02-profile-setup.png) | ![Chats list](docs/screenshots/03-chats-list.png) | ![Chat detail](docs/screenshots/04-chat-detail.png) |

| Live video call | Group video call | Communities | Calls |
|---|---|---|---|
| ![Video call](docs/screenshots/05-video-call-live.png) | ![Group video call](docs/screenshots/06-group-video-call.png) | ![Communities](docs/screenshots/07-communities-tab.png) | ![Calls](docs/screenshots/08-calls-tab.png) |

| Settings | Draw tool | Crop tool | Music picker |
|---|---|---|---|
| ![Settings](docs/screenshots/09-settings-tab.png) | ![Draw tool](docs/screenshots/10-draw-tool-colors.png) | ![Crop tool](docs/screenshots/11-crop-tool-ratios.png) | ![Music picker](docs/screenshots/12-music-picker.png) |

| Group info | Contact info | Text status |
|---|---|---|
| ![Group info](docs/screenshots/13-group-info.png) | ![Contact info](docs/screenshots/14-contact-info.png) | ![Text status](docs/screenshots/15-text-status-composer.png) |

<sub>The status composer's draw, crop, and music tools (above) load their music catalog live from Firestore/Storage.</sub>

This repository is being built in small, reviewable phases:

1. Architecture, project setup, and design foundation
2. Shared app shell and visual system
3. Auth and onboarding
4. Chats, groups, composer, attachments, and viewers
5. Updates/status, stories, and channels
6. Calls, calling flows, and provider adapters
7. Communities, contacts, and discovery
8. Settings, profile, app lock, and preferences
9. Backend adapters, push, sync, and offline hardening
10. Expanded happy/sad path test coverage

## Current phase

This repo currently includes:

- A full Flutter project scaffold with generated `android/` and `ios/` runners
- A themed app shell with light and dark mode support, and soft liquid-glass-style tab bar and screen transitions
- A splash/session gate with fake session restore
- Phone entry, OTP verification, and profile bootstrap auth flow
- A controller-driven chats slice: search, filters, archive, groups (roles, add/remove members, custom group icons), reply/forward/star/multi-select on messages, in-chat search, a pre-send media review screen (add a caption, rotate, freehand markup) before photos/videos go out, and hold-to-record voice notes with a waveform scrubber
- A controller-driven updates slice: story rings, per-viewer list with like state, heart quick-reacts, status composition (text/photo/video), and viewed/unviewed state
- A controller-driven calls slice: favorites, history, permission prompts, 1:1 audio/video calls, and **real multi-party group video calling** -- floating participant bubbles that merge and dock into place as people join, a live video grid once the call is connected, and unified host/participant controls
- A controller-driven communities and contacts slice with search, filters, permission gating, create-community flow, detail screens with tappable announcements/group chats, and invite/share actions
- A controller-driven settings slice with persisted preferences, profile editing, a privacy center, and a lifecycle-aware app lock overlay
- A backend and sync center with vendor-neutral push registration, observed repository activity, a local media transfer pipeline, and injectable provider contracts that keep Firebase and AWS seams clean
- Runtime-selected repository bundles so local seeded adapters remain stable while Firebase-first and AWS-ready repository boundaries are scaffolded
- A shared observability seam that captures app, shell, and calling breadcrumbs locally and is ready to swap for a release telemetry provider
- An inbox disk cache and reversed message list for fast cold starts and smooth scroll performance
- Unit and widget tests for the foundation, auth/session flow, chats, updates, calls (including group calling), communities, settings, and security layers

## Backend status

The app runs in two modes, switched at launch via `WW_BACKEND_TARGET` (see `config/README.md`) -- `local` is always the default, `firebase` opts into the adapters below. Every repository sits behind an interface (`AuthRepository`, `ChatRepository`, etc.), so switching modes never touches a screen.

| Feature | Local mode | Firebase mode |
|---|---|---|
| Auth | Seeded fake phone/OTP flow | **Real Firebase Phone Auth** (SMS/reCAPTCHA verification, session persistence) |
| Chats | Seeded fake threads | **Real Cloud Firestore** (per-thread participant security rules) |
| Updates/Status | Seeded fake stories | **Real Cloud Firestore** for metadata; photo/video upload to **Firebase Storage**, with per-segment 24h expiry, view/like tracking, and a device-local fallback if the upload fails |
| Communities | Seeded fake communities + contacts | **Real Cloud Firestore** for communities; **real device contacts** (`flutter_contacts`) matched against registered accounts via a `phoneDirectory` collection |
| Calls | Simulated (Timers, no real transport) | **Real 1:1 and group calling** for any contact/thread with known uids -- real Firestore signaling (ring/accept/decline/end, including group invites) plus a real LiveKit room with live local/remote video **and audio**, reachable from chat/Communities call buttons. Group calls animate participants in as floating bubbles before settling into a live video grid. Verified end-to-end on a real two-device call (iOS Simulator + physical Android phone). Contacts without a matched uid (e.g. the Calls tab's demo favorites) still use the original simulated flow, unchanged |
| Crashlytics / Analytics | Local in-memory breadcrumbs only | **Real Crashlytics + Analytics** (crash capture/upload verified; stack-trace symbolication disabled, see below) |
| Push (FCM/APNs) | Not implemented | **Real FCM token registration** (permission request, token fetch, written to `pushTokens/{uid}`) -- see below for a Simulator-specific limitation |

Known, deliberate scope decisions (each documented in the relevant repository/service file):
- Cross-user visibility (seeing someone else's chat/story/community) only really applies once a second real account exists to test against -- the write-security rules are in place, but only exercised by a single test account so far.
- Crashlytics crash reports upload successfully but aren't automatically symbolicated -- `flutterfire configure`'s generated Xcode build phase assumes a Swift Package Manager checkout layout that didn't match this machine's Xcode version and broke every build, so it was reverted. See `FirebaseAppTelemetry`'s doc comment for the full story and a manual fallback.
- Device-contact phone matching is a best-effort trailing-digits comparison, not real E.164 parsing -- see `core/utils/phone_number_matching.dart`.
- iOS Simulators cannot obtain a real APNs token (needs real hardware talking to Apple's push servers) -- push registration correctly reports "action required" there rather than crashing. Testing a real token needs a physical iOS device or the Android emulator. Sending pushes (not just registering for them) still needs a Cloud Function, which needs Blaze.
- LiveKit's camera capture also needs real hardware -- the iOS Simulator has no `AVCaptureDevice`, so real calls (and the debug test screen) catch that failure as a non-fatal warning and still confirm the room connection and mic track. Video needs a physical device on at least one side.
- Real calling has two known gaps, both documented inline in `CallsController`: an incoming call shows a placeholder caller name (`"Caller xxxx"`) since there's no contact-name resolution for an arbitrary caller uid yet, and a second simultaneous incoming call is silently ignored rather than queued or auto-declined.
- Testing real calls on the iOS Simulator needs its **I/O -> Audio Input** menu (in the Simulator app itself, not Xcode) set to a real microphone, not None/Mute -- otherwise `setMicrophoneEnabled` reports success while silently capturing nothing. On at least one real Android device, LiveKit's audio routing also needed the speaker preference to be passed with `force: true` to reliably win over the earpiece.

For the full setup story (Firebase console steps, `flutterfire configure`, local secrets), see `config/README.md`.

## Project structure

```text
lib/
  app/
  core/
  features/
test/
docs/
```

### Architecture shape

Each feature is intended to grow into a vertical slice:

```text
features/
  chats/
    presentation/
    application/
    domain/
    data/
```

Every feature keeps this same shape regardless of backend: local seeded data and real Firebase adapters implement the same repository interface, so a screen never knows or cares which one it's talking to (see [Backend status](#backend-status)).

## Local setup

### 1. Install Flutter tooling

On macOS, make sure Flutter, Xcode, CocoaPods, Android Studio, the Android SDK, and a JDK are installed, then run:

```bash
flutter doctor -v
```

### 2. Fetch packages

From this project folder:

```bash
flutter pub get
```

### 3. Run the app

```bash
flutter devices
flutter run -d "iPhone 17 Pro"
flutter run -d emulator-5554
```

To launch directly into a restored demo session for manual shell/chat QA:

```bash
flutter run -d emulator-5554 --dart-define=WW_DEMO_RESTORE_SESSION=true
```

To keep a local build closer to release behavior while still using debug tooling:

```bash
flutter run -d emulator-5554 --dart-define=WW_ENABLE_DEMO_SURFACES=false
```

To preview the Firebase-first scaffolding without wiring live credentials yet:

```bash
flutter run -d emulator-5554 \
  --dart-define=WW_BACKEND_TARGET=firebase \
  --dart-define=WW_APP_ENV=development
```

#### Easier alternative: `config/dev.json`

Instead of retyping `--dart-define` flags, copy `config/dev.json.example` to
`config/dev.json` (gitignored, local-only) and run:

```bash
flutter run --dart-define-from-file=config/dev.json
```

See `config/README.md` for the full key reference, including how to set up
your own Firebase config for Firebase mode.

### 4. Launch simulators and emulators

List the available emulator IDs:

```bash
flutter emulators
```

Verified locally on this machine:

- `apple_ios_simulator`
- `Small_Phone`
- `Medium_Phone_API_35`

Launch an iOS simulator:

```bash
flutter emulators --launch apple_ios_simulator
```

Launch an Android emulator:

```bash
flutter emulators --launch Small_Phone
```

After the device is booted, confirm the target ID:

```bash
flutter devices
```

### 5. Run checks

```bash
flutter analyze
flutter test
```

### Recommended development device matrix

To keep responsive issues visible while developing new features, keep one compact and one larger target open on each platform:

- iOS compact: `iPhone SE (3rd generation)`
- iOS large: `iPhone 17 Pro`
- Android compact: `Small_Phone`
- Android medium: `Medium_Phone_API_35`

The widget suite now covers the auth flow and the main shell across a compact and larger iPhone/Android size matrix, so `flutter test` will catch a large class of spacing and overflow regressions before manual QA.

### 6. Android JDK note

If Android builds fail on a managed network with SSL or certificate errors, point Flutter at a trusted local JDK before building:

```bash
flutter config --jdk-dir /Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home
```

Then rerun:

```bash
flutter doctor -v
```

## Troubleshooting

Release hardening guidance now lives in `docs/release_readiness.md`, and the automated quality gate lives in `.github/workflows/flutter_ci.yml`.

## Backend runtime flags

The app exposes a runtime backend configuration layer, so it runs fully on seeded local data even before live provider credentials are added.

- `WW_BACKEND_TARGET=local|firebase|aws`
- `WW_APP_ENV=local|development|staging|production`
- `WW_CALL_PROVIDER=simulated|livekit|twilio|agora|stream|self_managed`
- `WW_USE_FIREBASE_EMULATORS=true|false`
- `WW_FIREBASE_PROJECT_ID=...`
- `WW_FIREBASE_OPTIONS_READY=true|false`
- `WW_IOS_FIREBASE_CONFIG_READY=true|false`
- `WW_ANDROID_FIREBASE_CONFIG_READY=true|false`
- `WW_FIREBASE_AUTH_READY=true|false`
- `WW_FIRESTORE_READY=true|false`
- `WW_FIREBASE_STORAGE_READY=true|false`
- `WW_FCM_READY=true|false`
- `WW_APNS_READY=true|false`
- `WW_ANALYTICS_ENABLED=true|false`
- `WW_CRASH_REPORTING_ENABLED=true|false`

These flags feed the in-app `Settings > Backend and sync` screen so we can see which repository, push, media, and release pieces are still scaffolded, missing, or ready.

## Release and TestFlight rule

- Demo, QA, preview, and seeded-session surfaces must stay out of release and TestFlight builds.
- `WW_ENABLE_DEMO_SURFACES` and `WW_DEMO_RESTORE_SESSION` are ignored automatically when the app is compiled in release mode.
- Any future testing shortcut should be added behind the same non-release-only runtime flag pattern.

## Design direction

The app shell follows common social and messaging app patterns:

- Story-style update rings and recent updates surfaces
- A clean, organized settings/profile layout
- Dense but readable chat list cards
- Call history and favorites with quick actions
- Light and dark themes tuned for messaging use

## What comes next

Auth, chats, updates/status, communities, and calling (including group calling) are all wired to real Firebase/LiveKit backends today (see [Backend status](#backend-status)). What's left:

1. AWS-path repository adapters (currently scaffolded behind the same interfaces, not yet implemented)
2. Sending pushes end-to-end (registration works; the sender side needs a Cloud Function on the Blaze plan)
3. Cross-user visibility testing with a second real account, beyond the security rules already in place
4. Expanded release hardening and CI quality gates

## Notes

- The app still runs fully on seeded local data with `WW_BACKEND_TARGET=local` (the default) -- no live credentials required to explore the UI.
- Firebase and AWS setup guidance lives in the in-app backend and sync center, and repository selection follows the runtime backend mode without leaking provider SDK assumptions into feature UI.
- The Swift iOS project remains unchanged.
