// Driver for the `integration_test/` flows.
//
// Local run against an attached device or booted simulator, one flow at a
// time:
//
//   flutter test integration_test/session_handover_test.dart
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/session_handover_test.dart
//
// Firebase Test Lab (docs/test_strategy.md picks it for the device matrix)
// needs this file for the Android instrumentation build, and takes one
// target per build:
//
//   flutter build apk --config-only
//   pushd android && ./gradlew app:assembleAndroidTest \
//     app:assembleDebug -Ptarget=integration_test/session_handover_test.dart \
//     && popd
//   gcloud firebase test android run --type instrumentation \
//     --app build/app/outputs/apk/debug/app-debug.apk \
//     --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
//
// On iOS, build the test bundle with
// `flutter build ios --config-only integration_test/<flow>_test.dart`
// and run it through `xcodebuild test-without-building`.
//
// These flows need no network and no Firebase credentials, but several of
// them destroy the app's local state on the device they run on (keystore
// entries, SharedPreferences, the media cache) -- see each file's header.
// Use a test device or a fresh simulator.

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
