# Agent Resume Brief

## Purpose

This brief is meant for another AI tool or a developer who needs a concise but accurate starting point.

## Read first

1. `docs/handoff/01_project_state.md`
2. `docs/handoff/05_development_guardrails.md`
3. `docs/handoff/06_testing_and_qa.md`
4. `docs/backend_integration_plan.md`
5. `docs/release_readiness.md`

## Current resume summary

You are continuing work on the Flutter app only:

- project root: `outputs/whatswave_flutter`
- do not touch the separate older native Swift iOS project outside this folder

What is already true:

- feature-complete local UI exists for auth, chats, updates, calls, communities, and settings
- local session persistence exists for easier repeated testing
- runtime backend scaffolding exists for local, Firebase-first, and AWS-compatible modes
- repository selection, push registration, media transfer, and telemetry are already abstracted behind seams
- `flutter analyze` and `flutter test` were passing at the last handoff
- fresh iOS and Android launches were also passing at the last handoff

What is not yet true:

- no live Firebase project is connected
- no live AWS services are connected
- no real call transport provider is connected
- no end-to-end encryption is implemented
- no server-side abuse or moderation stack exists

## Current important files

Backend runtime and integration:

- `lib/core/config/backend_runtime_config.dart`
- `lib/core/integrations/backend_integration_bundle.dart`
- `lib/core/integrations/backend_repository_bundle.dart`
- `lib/core/integrations/integration_hub_controller.dart`
- `lib/core/integrations/tracked_repositories.dart`

App bootstrap:

- `lib/main.dart`
- `lib/app/bootstrap.dart`
- `lib/app/whatswave_app.dart`

Feature entry points:

- `lib/features/auth/application/auth_controller.dart`
- `lib/features/chats/application/chats_controller.dart`
- `lib/features/updates/application/updates_controller.dart`
- `lib/features/calls/application/calls_controller.dart`
- `lib/features/communities/application/communities_controller.dart`
- `lib/features/settings/presentation/settings_screen.dart`
- `lib/features/settings/presentation/backend_sync_screen.dart`

## Mandatory working style

- preserve UX quality on both iOS and Android
- test on compact and larger devices
- respect light and dark mode
- keep production/TestFlight behavior free of debug-only shortcuts
- do not route backend SDKs directly into presentation code
- keep local fallback behavior stable until live adapters are proven

## Best next tasks

If infrastructure is available on the new machine, do this next:

1. create or connect a dev Firebase project
2. add `firebase_core` and generate `firebase_options.dart`
3. wire Firebase initialization
4. implement Firebase-backed `AuthRepository`
5. move chats and updates to Firestore adapters
6. move media transfer to Storage
7. move push token registration to FCM

If infrastructure is still not available, do this instead:

1. improve offline and retry behavior
2. expand widget and unit coverage
3. refine release-readiness docs
4. keep polishing cross-device UX

## Validation expectation after each meaningful change

Run:

```bash
flutter analyze
flutter test
```

Then run the app on:

- one iOS simulator
- one Android emulator

## Copy-paste prompt for another AI

Use this as the starting instruction if another AI takes over:

```text
Continue work only in the Flutter project at outputs/whatswave_flutter.
Do not modify the separate native Swift iOS project outside this folder.
Read docs/handoff/README.md first, then follow the documented guardrails.
Preserve the current UX quality bar, compact-device support, light/dark parity, and runtime backend seams.
After meaningful changes, run flutter analyze, flutter test, and launch on both iOS and Android.
If backend work is available, continue with Firebase-first integration through the existing repository and service boundaries.
```
