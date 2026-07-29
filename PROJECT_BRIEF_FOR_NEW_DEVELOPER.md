# Project Brief For New Developer

## Purpose

This file is the fastest high-signal handoff for a new developer or AI agent taking over the WhatsWave Flutter project.

Use this file first, then read the linked docs for deeper detail.

## Project to work on

Work only in this Flutter project:

- `outputs/whatswave_flutter`

Do not modify the older native Swift iOS app outside this folder unless explicitly asked.

## Product summary

WhatsWave Flutter is a WhatsApp-style cross-platform app with:

- auth and onboarding
- chat list and chat thread
- updates/status and story viewer
- calls UI and simulated call flows
- communities and contacts
- settings, profile, privacy, and app lock
- local persistence for development and testing
- backend seams prepared for Firebase-first and AWS-compatible future work

## Current status

Locally implemented and testable:

- Phase 1 foundation and architecture
- Phase 2 auth and session flow
- Phase 3 chats
- Phase 4 updates and story UX
- Phase 5 calls with simulated flows
- Phase 6 communities and contacts
- Phase 7 settings, privacy, and app lock
- Phase 8 backend scaffolding started
- Phase 9 hardening started

Current default runtime:

- local seeded data

Current reality:

- the app is feature-rich locally
- major UI flows run on iOS and Android
- tests are present across core features
- Firebase and AWS are not live yet
- real push, real sync, real media backend, and real call transport are still pending

## Architecture snapshot

Top-level structure:

```text
lib/
  app/
  core/
  features/
test/
docs/
```

Feature shape:

```text
features/
  <feature>/
    presentation/
    application/
    domain/
    data/
```

Important architecture rules:

- presentation code must not depend directly on Firebase or AWS SDKs
- repository and service seams are the boundary for backend work
- domain models should flow through the app, not backend DTOs
- local fallback implementations must stay usable until live adapters are proven

## Important files

Bootstrap and app shell:

- `lib/main.dart`
- `lib/app/bootstrap.dart`
- `lib/app/whatswave_app.dart`

Runtime backend and integration seam:

- `lib/core/config/backend_runtime_config.dart`
- `lib/core/integrations/backend_integration_bundle.dart`
- `lib/core/integrations/backend_repository_bundle.dart`
- `lib/core/integrations/integration_hub_controller.dart`
- `lib/core/integrations/tracked_repositories.dart`
- `lib/core/observability/app_telemetry.dart`

Feature entry points:

- `lib/features/auth/application/auth_controller.dart`
- `lib/features/chats/application/chats_controller.dart`
- `lib/features/updates/application/updates_controller.dart`
- `lib/features/calls/application/calls_controller.dart`
- `lib/features/communities/application/communities_controller.dart`
- `lib/features/settings/presentation/settings_screen.dart`
- `lib/features/settings/presentation/backend_sync_screen.dart`

## UX and coding standard

This project has a strong product-quality bar.

Preferred direction:

- WhatsApp-like polish, not generic demo UI
- lightweight UI
- compact-device support
- stable motion and transitions
- light and dark mode parity
- fewer user actions where possible

Working rules:

- keep changes scoped and clean
- extend existing controllers and seams instead of bypassing them
- add tests with behavior changes
- validate on iOS and Android after meaningful UI work
- keep debug/demo shortcuts out of release behavior

## Setup on a new machine

Recommended baseline:

- Flutter stable
- Xcode
- CocoaPods
- Android Studio or Android SDK tools
- JDK 17
- one iOS simulator
- one Android emulator

Last known-good snapshot from this machine:

- Flutter `3.44.1`
- Dart `3.12.1`
- Xcode `26.1`
- CocoaPods `1.16.2`
- Android SDK `36.0.0`
- JDK `17.0.12`

First-run commands:

```bash
flutter pub get
flutter doctor -v
flutter analyze
flutter test
flutter devices
flutter run -d "iPhone 17 Pro"
flutter run -d emulator-5554
```

If those exact device names do not exist, use equivalent iOS and Android targets.

## Validation expectation

After meaningful changes, run:

```bash
flutter analyze
flutter test
```

Then launch on:

- one compact iPhone
- one larger iPhone
- one compact Android phone
- one medium Android phone when practical

Check both:

- light mode
- dark mode

Recommended device matrix:

- iPhone SE class
- iPhone 17 Pro class
- small Android phone
- medium Android phone

## Backend and infrastructure status

Current backend mode:

- `WW_BACKEND_TARGET=local`

Prepared but not live:

- Firebase-first runtime path
- AWS-compatible runtime path
- push registration seam
- media transfer seam
- provider readiness UI
- backend sync screen

Still missing for real production:

- live Firebase or AWS project
- real auth backend
- real message/status sync
- real media upload/download
- push token sync and delivery
- real call signaling and media transport
- end-to-end encryption and key management
- server-side abuse, moderation, and rate limiting

## Temporary development identifiers

These are already set and can be reused for dev setup:

- iOS bundle ID: `com.tsjaydevra.whatswave`
- Android application ID: `com.tsjaydevra.whatswave`

## Known constraints

- this project started in a generated Codex output folder and is not yet a normal git repo
- the previous machine could not create a Firebase project because of local policy limits
- current Android builds show a non-blocking warning from `shared_preferences_android` about future Kotlin Gradle migration
- release/TestFlight builds must ignore testing shortcuts and demo-only surfaces

## Recommended next work order

If backend infrastructure is available:

1. Create or connect a dev Firebase project
2. Add `firebase_core` and generated config
3. Wire Firebase initialization
4. Implement Firebase Auth adapter
5. Implement Firestore chat and updates adapters
6. Implement Storage-backed media upload
7. Implement FCM/APNs token sync
8. Choose a real call provider and wire signaling/media

If backend infrastructure is not available:

1. Continue local-first UX polish
2. Expand test coverage
3. Improve offline and retry behavior
4. Harden release-readiness docs and QA checklists

## Read next

Read these in order:

1. `TRANSFER_TO_NEW_PC.md`
2. `docs/handoff/README.md`
3. `docs/handoff/01_project_state.md`
4. `docs/handoff/05_development_guardrails.md`
5. `docs/handoff/06_testing_and_qa.md`
6. `docs/architecture.md`

If backend work is next, also read:

1. `docs/handoff/03_firebase_dev_setup.md`
2. `docs/handoff/04_aws_path.md`
3. `docs/backend_integration_plan.md`
4. `docs/release_readiness.md`

## Short prompt for another AI

```text
Continue work only in the Flutter project at outputs/whatswave_flutter.
Do not modify the older native Swift iOS app outside this folder.
Read PROJECT_BRIEF_FOR_NEW_DEVELOPER.md first, then TRANSFER_TO_NEW_PC.md and docs/handoff/README.md.
Preserve the current UX quality bar, compact-device support, light/dark parity, and repository/service seams.
After meaningful changes, run flutter analyze, flutter test, and launch on iOS and Android.
If backend work is available, continue with Firebase-first integration through the existing repository and service boundaries.
```
