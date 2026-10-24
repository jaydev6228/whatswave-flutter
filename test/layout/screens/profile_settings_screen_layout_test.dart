import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/auth/application/auth_controller.dart';
import 'package:whatswave/features/auth/data/fake_auth_repository.dart';
import 'package:whatswave/features/settings/presentation/profile_settings_screen.dart';

import '../../support/device_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('ProfileSettingsScreen survives the layout matrix',
      (tester) async {
    final authController = AuthController(
      repository: FakeAuthRepository(
        restoredUser: DemoData.currentUser,
        latency: Duration.zero,
      ),
    );
    // runAsync, not a bare await: FakeAuthRepository._wait() arms a
    // Future.delayed even at zero latency, and a fake-async timer does not
    // fire until the first pump -- so awaiting it here would deadlock.
    await tester.runAsync(authController.restoreSession);

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: ProfileSettingsScreen(
          authController: authController,
          currentUser: authController.currentUser ?? DemoData.currentUser,
        ),
      ),
    );
  });
}
