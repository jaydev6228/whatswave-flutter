# Implementation Update - 2026-06-03

## Scope of this pass

This log covers the work completed after the latest phase review, including the call-surface polish you requested, the phase 9 hardening pass, and the next phase 8 backend scaffolding slice.

## What was completed

### 1. Call UI and UX polish

- Cleaned the simulated call experience so the video-call front and back camera control now lives inside the local preview instead of competing with the bottom dock controls.
- Strengthened selected-state contrast for speaker, mute, camera, and lens controls so on and off states are easier to read in both themes.
- Fixed the `Camera off` preview treatment so the status stays centered and no longer clips or collides with the surrounding video-card layout.
- Kept the lighter-weight call style from the recent design pass while reducing noisy overlapping UI in the active call experience.
- Removed the small colored state dots from call controls and shifted state feedback into the control itself:
  - audio route now keeps a stable `Speaker` label and uses the control surface to show on and off state
  - video toggle now reads `Cam off` when the local camera is disabled
  - mute continues to read `Mute` or `Muted`
- Refined the call controls again after device review:
  - kept `Speaker` as a stable label and moved the on/off cue fully into the button surface
  - strengthened the active `Speaker` surface so the on state reads as a clearly brighter white control on both themes
  - deepened the idle light-mode control surface and strengthened the selected border and shadow so the active `Speaker` button stands out more clearly on bright backgrounds
  - tightened the light-mode control styling again so the `Speaker` button keeps a more obvious filled white surface with stronger edge contrast and elevation on live devices
  - aligned the dark-mode `Muted` selected surface with `Speaker` so both active controls now share the same white filled state instead of mixing two different selected treatments
  - aligned the dark-mode `Camera` selected surface with `Muted` and `Speaker` so the full active control set now uses one consistent selected fill in video calls
  - moved the front and back camera switch action out of the bottom video dock and into the top-right corner of the local preview card, leaving the bottom dock as a cleaner three-button control group
  - refined the preview switch control again by removing the `You` badge, moving the action to the bottom-right corner of the local preview, and using a clearer flip-camera icon for the smaller in-preview button
  - renamed the lens switch control to `Switch` so the camera action feels clearer than `Flip`
  - softened the light-mode preview switch control so the front and back camera button feels lighter and more iOS-like instead of reading as a dark black chip on bright themes
  - removed Android's default overscroll stretch at the app level so long lists now stop more cleanly instead of rubber-band stretching during pull gestures

### 2. Production hardening

- Added a shared `AppTelemetry` seam for local breadcrumbs and future release telemetry providers.
- Wired bootstrap, uncaught Flutter errors, platform errors, tab navigation, and call-flow actions into telemetry.
- Finished call-controller telemetry for permission requests, permission denials, call state transitions, call control toggles, and session completion.
- Added regression tests for the new telemetry layer and the shared app-shell telemetry wiring.
- Added CI in `.github/workflows/flutter_ci.yml` for:
  - `flutter analyze`
  - `flutter test`
  - Android debug build smoke check
  - iOS simulator smoke build
- Added `docs/release_readiness.md` with the local release gate, observability seam notes, and remaining public-release blockers.

### 3. Runtime bug fixed during verification

- Found and fixed a real launch-time `Zone mismatch` issue in `bootstrap.dart` that only showed up during an actual Android run.
- Re-ran analysis, tests, and fresh device launches after the bootstrap fix.

### 4. Phase 8 backend scaffolding

- Centralized the app's default repository selection into a dedicated runtime bundle so auth, chats, updates, communities, and calls no longer hard-wire seeded fake repositories inside `WhatsWaveApp`.
- Added a runtime-aware repository readiness catalog for the backend sync center:
  - local mode now reports the active seeded adapters feature by feature
  - Firebase-first mode now reports scaffolded repository targets that still rely on local fallback data until live bindings are added
  - AWS-ready mode now reports portable local-fallback repository seams for a future mixed-provider backend
- Expanded the backend sync screen with a new `Repository adapters` section so it is easier to see which parts of the app are still local, which are scaffolded, and what setup remains before a real backend swap.
- Added unit coverage for the new repository bundle factory and controller exposure so the Phase 8 seam is tested before live Firebase wiring begins.

## Files updated in this pass

- `lib/main.dart`
- `lib/app/bootstrap.dart`
- `lib/app/whatswave_app.dart`
- `lib/core/observability/app_telemetry.dart`
- `lib/core/integrations/backend_repository_bundle.dart`
- `lib/features/calls/application/calls_controller.dart`
- `lib/features/calls/presentation/call_experience_screen.dart`
- `lib/features/settings/presentation/backend_sync_screen.dart`
- `test/app/whatswave_app_test.dart`
- `test/core/integrations/backend_repository_bundle_test.dart`
- `test/core/observability/app_telemetry_test.dart`
- `test/core/integrations/integration_hub_controller_test.dart`
- `test/features/calls/application/calls_controller_test.dart`
- `test/features/calls/presentation/calls_screen_test.dart`
- `test/features/settings/presentation/settings_screen_test.dart`
- `test/support/device_matrix.dart`
- `.github/workflows/flutter_ci.yml`
- `docs/release_readiness.md`
- `README.md`
- `docs/backend_integration_plan.md`

## Validation completed

### Automated

- `flutter analyze`
- `flutter test`

Both completed successfully after the final bootstrap fix.
The follow-up light-theme speaker regression test and contrast refinement also completed successfully afterward.
The follow-up Phase 8 repository bundle work also passed `flutter analyze` after the runtime repository scaffolding was added.

### Device launch verification

- Android:
  - launched on `emulator-5554`
  - latest code opened successfully
- iOS:
  - launched on `iPhone 17 Pro`
  - latest code opened successfully
- Visual spot checks completed on iOS active-call surfaces for:
  - audio call control state labels
  - video call control state labels and `Cam off` preview
- Additional light-theme call verification completed after the preview-switch polish:
  - iPhone 17 Pro active video call surface
  - Android emulator active video call surface
  - preview switch control no longer reads as a dark black chip in light mode

Quick launch screenshots were captured during verification in:

- `work/device_checks/android_after_phase9.png`
- `work/device_checks/ios_after_phase9.png`
- `work/device_checks/android_after_call_state_patch.png`
- `work/device_checks/ios_audio_call_state_labels.png`
- `work/device_checks/ios_video_call_state_labels.png`
- `work/device_checks/ios_light_audio_call_speaker_on.png`
- `work/device_checks/android_light_audio_call_speaker_on.png`
- `work/device_checks/ios_light_preview_switch_softened.png`
- `work/device_checks/android_light_preview_switch_softened.png`

## What to test when you return

### Calls

1. Open `Calls`.
2. Start an audio call from the recent or favorites list.
3. Confirm the selected speaker state is clearly highlighted.
4. Toggle mute and speaker a few times in both light and dark mode and confirm state readability stays obvious.
5. Start a video call.
6. Turn the camera off and confirm the preview stays clean with the `Camera off` state centered and not clipped.
7. Use the preview-card switch control in a light theme video call and confirm it feels lighter, cleaner, and easier on the eye than the earlier dark-looking button.

### App stability

1. Switch between all tabs.
2. Relaunch the app on both platforms.
3. Confirm the app still lands in the shell without the earlier bootstrap warning or launch-time crash.

### Release-readiness review

1. Review `docs/release_readiness.md`.
2. Review `.github/workflows/flutter_ci.yml`.
3. Confirm the CI gate matches how you want pull requests and release candidates validated.

## Remaining non-local blockers for a true public release

These are still infrastructure tasks, not local UI tasks:

- real Firebase or AWS repositories and production APIs
- APNs and FCM token sync and live notification delivery
- a real audio and video calling transport provider
- end-to-end encryption and key management
- abuse prevention, moderation, and server-side rate limiting

## Known note

- Android build currently prints a Flutter warning about `shared_preferences_android` using the old Kotlin Gradle Plugin path. The app still builds and runs, but this dependency should be rechecked when upgrading Flutter or the plugin stack.
