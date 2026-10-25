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

  // Accessibility is its own test, not an extra assertion on the sweep above:
  // a contrast failure reported as a layout failure tells nobody what broke.
  // One realistic size, default text scale -- the guidelines are about colour
  // and target size, which do not need the size matrix.
  testWidgets('HelpScreen meets accessibility guidelines', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const HelpScreen(),
      ),
    );
    await pumpForAsyncUi(tester);
    expect(find.byType(HelpScreen), findsOneWidget);

    await expectScreenMeetsAccessibilityGuidelines(tester);
  });
}
