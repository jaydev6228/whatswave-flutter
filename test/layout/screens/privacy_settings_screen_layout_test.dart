import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/controllers/app_preferences_controller.dart';
import 'package:whatswave/features/settings/presentation/privacy_settings_screen.dart';

import '../../support/device_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('PrivacySettingsScreen survives the layout matrix',
      (tester) async {
    final controller = AppPreferencesController();
    await controller.ensureLoaded();

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: PrivacySettingsScreen(controller: controller),
      ),
    );
  });
}
