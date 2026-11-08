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

  // runAsync, not a bare await: FakeAuthRepository._wait() arms a
  // Future.delayed even at zero latency, and a fake-async timer does not
  // fire until the first pump -- so awaiting it here would deadlock.
  Future<AuthController> restoredAuth(WidgetTester tester) async {
    final authController = AuthController(
      repository: FakeAuthRepository(
        restoredUser: DemoData.currentUser,
        latency: Duration.zero,
      ),
    );
    await tester.runAsync(authController.restoreSession);
    return authController;
  }

  testWidgets('ProfileSettingsScreen survives the layout matrix',
      (tester) async {
    final authController = await restoredAuth(tester);

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

  // Accessibility is its own test, not an extra assertion on the sweep above:
  // a contrast failure reported as a layout failure tells nobody what broke.
  //
  // All four guidelines pass. The app bar's "Save" TextButton draws
  // colorScheme.primary on cloud -- which shows through because
  // appBarTheme sets a transparent background -- and that pair was
  // 3.84:1 at 14.0 while emerald was #128C7E. It is 5.38 at #0E7268.
  testWidgets('ProfileSettingsScreen meets accessibility guidelines',
      (tester) async {
    final authController = await restoredAuth(tester);

    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: ProfileSettingsScreen(
          authController: authController,
          currentUser: authController.currentUser ?? DemoData.currentUser,
        ),
      ),
    );
    await pumpForAsyncUi(tester);
    expect(find.byType(ProfileSettingsScreen), findsOneWidget);

    await expectScreenMeetsAccessibilityGuidelines(tester);
  });
}
