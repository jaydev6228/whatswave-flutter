# Release Readiness

## What phase 9 adds

- Shared app telemetry for bootstrap, uncaught errors, shell navigation, and call interactions
- A CI workflow that runs analyze, widget and unit tests, Android debug build smoke checks, and iOS simulator build smoke checks
- A practical release gate so local QA, debug-only shortcuts, and backend prerequisites stay separated from production delivery

## Pre-release checklist

1. Run `flutter pub get`, `flutter analyze`, and `flutter test`.
2. Build platform artifacts:
   - `flutter build apk --release`
   - `flutter build appbundle --release`
   - `flutter build ios --release`
3. Confirm demo-only flags stay off in release builds:
   - `WW_ENABLE_DEMO_SURFACES`
   - `WW_DEMO_RESTORE_SESSION`
4. Verify the compact and larger manual QA matrix:
   - iPhone SE (3rd generation)
   - iPhone 17 Pro
   - Small Android phone
   - Medium Android phone
5. Re-check native permission copy, privacy manifests, notification entitlements, and app icon/splash assets before uploading a release candidate.
6. Verify backend environment values, push credentials, and media storage buckets point to the correct environment.

## Observability seam

`LocalAppTelemetry` now captures:

- `FlutterError.onError`
- `PlatformDispatcher.instance.onError`
- `runZonedGuarded` fallthrough errors
- Shell tab screen views and tab-switch interactions
- Call permission, connection, control-toggle, and call-finish events

This is intentionally a seam, not the final vendor choice. For public release, replace or decorate `LocalAppTelemetry` with the provider you choose, such as Crashlytics, Sentry, Datadog, or a server-backed analytics pipeline. The app-level wiring is ready for that swap without rewriting the feature controllers.

## CI quality gates

The workflow in `.github/workflows/flutter_ci.yml` enforces:

- `flutter analyze`
- `flutter test`
- Android debug build smoke validation
- iOS simulator smoke validation without code signing

That keeps pull requests honest before manual simulator and device QA begins.

## Still blocked for a true public release

These are infrastructure gaps, not local Flutter UI gaps:

- Real Firebase or AWS repositories and server APIs
- APNs and FCM token sync plus push and call invite delivery
- A real audio and video calling provider
- End-to-end encryption and key management
- Server-side abuse prevention, rate limiting, moderation, and audit controls

## Recommended next production steps

1. Choose the first release backend path: Firebase-first or AWS-first.
2. Pick the production call provider and replace the simulated call transport layer.
3. Wire a real telemetry vendor behind `AppTelemetry`.
4. Add integration tests once backend adapters are no longer seeded-only.
5. Run full TestFlight and Play internal testing with real devices after the above services are in place.
