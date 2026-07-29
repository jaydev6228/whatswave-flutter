# Project State

## Scope

This handoff covers only the Flutter app in `outputs/whatswave_flutter`.

There is a separate native Swift iOS project outside this folder. That older project should remain untouched unless the product owner explicitly asks for work there.

## High-level status

The project is in a strong local-development state.

Implemented locally:

- Phase 1 foundation and architecture
- Phase 2 auth and session flow
- Phase 3 chats
- Phase 4 updates and story viewer
- Phase 5 calls with simulated call flows
- Phase 6 communities and contacts
- Phase 7 settings, profile, privacy, and app lock
- Phase 8 backend scaffolding started
- Phase 9 hardening started

What this means in practice:

- The product UI is feature-rich and testable on iOS and Android
- Light and dark mode support exists throughout the app
- Local seeded data powers the current app behavior
- Auth persistence works locally for testing
- Backend seams now exist for future Firebase-first or AWS-compatible adapters
- CI and telemetry seams are present, but live infrastructure is still missing

## Current backend state

Default mode:

- `WW_BACKEND_TARGET=local`

Current reality:

- UI and controllers are functional
- Repository selection is runtime-aware
- Push registration is scaffolded behind an injectable service
- Media transfer is scaffolded behind an injectable service
- Backend sync UI reports provider readiness and repository readiness
- No live Firebase project is connected yet
- No live AWS services are connected yet
- Calling is still simulated, not real transport

Important production gap:

- A public release is still blocked by real backend infrastructure, push delivery, real calling transport, and security controls

## Current temporary identifiers

These are already in the Flutter project and can be used for dev Firebase registration:

- iOS bundle ID: `com.tsjaydevra.whatswave`
- Android namespace: `com.tsjaydevra.whatswave`
- Android application ID: `com.tsjaydevra.whatswave`

These are fine for development and testing.

If production later needs different identifiers, register new Firebase apps for production rather than reworking the dev setup.

## Toolchain snapshot from this machine

Verified working on this machine:

- Flutter `3.44.1`
- Dart `3.12.1`
- Xcode `26.1`
- CocoaPods `1.16.2`
- Android SDK `36.0.0`
- JDK `17.0.12`

Verified devices:

- iOS simulator: `iPhone 17 Pro`
- Android emulator: `emulator-5554`

## Validation status at handoff time

Completed successfully:

- `flutter analyze`
- `flutter test`
- fresh Flutter launch on iOS simulator
- fresh Flutter launch on Android emulator

Known build note:

- Android currently prints a warning about `shared_preferences_android` using the old Kotlin Gradle Plugin path
- This warning did not block builds or tests during the last verification pass

## Current architecture hotspots

Most important files for resuming work:

- App bootstrap:
  - `lib/main.dart`
  - `lib/app/bootstrap.dart`
  - `lib/app/whatswave_app.dart`
- Preferences and shell:
  - `lib/core/controllers/app_preferences_controller.dart`
  - `lib/features/shell/presentation/app_shell.dart`
- Runtime backend seam:
  - `lib/core/config/backend_runtime_config.dart`
  - `lib/core/integrations/backend_integration_bundle.dart`
  - `lib/core/integrations/backend_repository_bundle.dart`
  - `lib/core/integrations/integration_hub_controller.dart`
  - `lib/core/integrations/tracked_repositories.dart`
- Observability seam:
  - `lib/core/observability/app_telemetry.dart`
- Feature controllers:
  - `lib/features/auth/application/auth_controller.dart`
  - `lib/features/chats/application/chats_controller.dart`
  - `lib/features/updates/application/updates_controller.dart`
  - `lib/features/calls/application/calls_controller.dart`
  - `lib/features/communities/application/communities_controller.dart`

## Remaining strategic work

Still pending for real product readiness:

- Firebase dev project creation on a machine that allows it
- Live Firebase or AWS adapters
- Push token sync and real message delivery
- Real audio and video call provider
- End-to-end encryption and key management
- Server-side abuse prevention, moderation, and rate limiting
- Release-grade analytics and crash vendor binding
- Real device validation with non-simulated backend flows

## Recommended next implementation order

1. Firebase dev setup on a new machine
2. `firebase_core` bootstrap and generated config
3. Firebase Auth adapter
4. Firestore chat and updates adapters
5. Storage-backed media uploads
6. FCM token sync and push service
7. Real call provider selection and signaling integration
8. Expanded hardening for offline, moderation, and release
