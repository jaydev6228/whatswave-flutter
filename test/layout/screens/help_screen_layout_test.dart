import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/settings/presentation/help_screen.dart';

import '../../support/device_matrix.dart';

void main() {
  testWidgets('HelpScreen survives the layout matrix', (tester) async {
    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const HelpScreen(),
      ),
    );
  });
}
