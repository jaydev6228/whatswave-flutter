# Testing And QA

## Automated validation baseline

Run this before handing off any meaningful change:

```bash
flutter analyze
flutter test
```

For release-oriented validation also run:

```bash
flutter build apk --release
flutter build appbundle --release
flutter build ios --release
```

## Current automated coverage inventory

App and shell:

- `test/app/whatswave_app_test.dart`
- `test/app/theme/app_theme_test.dart`

Core:

- `test/core/config/backend_runtime_config_test.dart`
- `test/core/controllers/app_preferences_controller_test.dart`
- `test/core/integrations/backend_repository_bundle_test.dart`
- `test/core/integrations/integration_hub_controller_test.dart`
- `test/core/observability/app_telemetry_test.dart`
- `test/core/widgets/app_lock_gate_test.dart`

Auth:

- `test/features/auth/application/auth_controller_test.dart`
- `test/features/auth/data/fake_auth_repository_test.dart`
- `test/features/auth/presentation/auth_flow_screen_test.dart`

Chats:

- `test/features/chats/application/chats_controller_test.dart`
- `test/features/chats/presentation/chats_screen_test.dart`

Updates:

- `test/features/updates/application/updates_controller_test.dart`
- `test/features/updates/presentation/updates_screen_test.dart`
- `test/features/updates/presentation/status_story_viewer_screen_test.dart`
- `test/features/updates/presentation/widgets/status_ring_avatar_test.dart`

Calls:

- `test/features/calls/application/calls_controller_test.dart`
- `test/features/calls/presentation/calls_screen_test.dart`

Communities:

- `test/features/communities/application/communities_controller_test.dart`
- `test/features/communities/presentation/communities_screen_test.dart`

Settings:

- `test/features/settings/presentation/settings_screen_test.dart`

## Manual QA device matrix

Minimum visual QA targets:

- iPhone SE (3rd generation)
- iPhone 17 Pro
- small Android phone
- medium Android phone

Check both:

- light mode
- dark mode

## Manual QA by screen and feature

### Splash and session restore

Happy path:

- app opens without crash
- restored local session lands in shell
- splash does not hang

Sad path:

- no saved session falls back to auth flow
- app lock does not trap the user in a loop

### Auth flow

Happy path:

- country code defaults sensibly
- phone entry looks correct before and after focus
- OTP success transitions to next step
- profile completion persists

Sad path:

- invalid phone input shows inline guidance
- wrong OTP shows inline error
- profile validation errors stay readable on compact screens

### Chats list

Happy path:

- search works
- filters work
- archive opens and restores correctly
- scroll position is preserved when returning from a thread
- profile story ring opens story viewer

Sad path:

- list drag dismisses search focus cleanly
- actions menu labels are fully visible
- no overflow or clipped content on compact devices

### Chat thread

Happy path:

- sending short and long text messages feels stable
- latest message remains visually clear after send
- attachment grid opens cleanly
- full-screen media preview opens
- location attachment entry remains available

Sad path:

- failed outgoing message state shows and retry works
- long message send does not jerk the list
- no composer overlap or hidden final bubble

### Updates list

Happy path:

- my status card updates after posting
- recent and viewed sections are correct
- viewed-state logic keeps partially viewed stories in the correct section
- tapping avatars from chats opens story viewer

Sad path:

- empty or failed states remain readable
- story rings keep visible spacing in viewed and unviewed states

### Story viewer

Happy path:

- stories auto-play
- progress bars advance correctly
- tap right and left navigation behaves like standard social story UX
- viewer closes when a user has no more stories

Sad path:

- opening a viewed story starts from the correct first segment behavior
- left tap on the first story does not close unexpectedly if behavior is intentionally retained
- progress bars do not freeze or show all segments as the same state

### Calls list and call experience

Happy path:

- favorites and recents render correctly
- starting audio and video calls works from the list
- speaker, mute, and camera states are visually obvious
- video preview switch control is placed and styled correctly

Sad path:

- permission-denied states remain clear
- no layout break or button overlap on small devices
- camera off state remains centered and clean
- light and dark mode selected states match across related controls

### Communities and contacts

Happy path:

- create community works
- invite contact works
- share invite works
- search and filters work

Sad path:

- denied contact permission stays readable
- empty states are intentional, not broken-looking

### Settings, privacy, and app lock

Happy path:

- profile edit saves and updates header
- theme switch works
- privacy center updates persist
- app lock unlock flow works after resume
- backend and sync screen opens

Sad path:

- validation errors show inline
- app lock does not loop forever after relaunch
- backend sync screen handles missing setup cleanly

### Backend and sync screen

Happy path:

- runtime config card reflects active flags
- provider readiness is sensible
- repository adapters section reflects current backend mode
- media pipeline and push sections update as flows happen

Sad path:

- incomplete Firebase setup shows action-required guidance
- failed transfer retry still works
- no stale or misleading provider labels after backend work lands

## Manual QA after backend integration starts

Once live Firebase or AWS adapters exist, add:

- real auth success and failure
- real push permission and token sync
- real remote message send and receive
- real media upload and retry
- offline recovery and stale-cache checks
- environment separation verification between dev and prod

## Regression hotspots

Pay extra attention to these whenever adjacent code changes:

- chat composer and scroll behavior
- story viewer progress
- app lock lifecycle behavior
- call control layout and selected-state contrast
- settings navigation and backend sync screen

## Release candidate QA reminders

- demo-only flags off
- no preview-only UI in release
- privacy copy reviewed
- permission copy reviewed
- icons and launch assets reviewed
- backend environment values point to correct project
