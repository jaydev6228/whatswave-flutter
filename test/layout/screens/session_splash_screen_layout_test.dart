import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/auth/presentation/session_splash_screen.dart';

import '../../support/device_matrix.dart';

void main() {
  // The message is optional and only renders when the auth controller has
  // one, so both states need covering.
  //
  // KNOWN FAILURE, not a broken test: the message case overflows by 12px at
  // 320x568 / 2.0x text with the longest string restoreSession actually
  // sets. The Column sits in a Center with no scroll view, so at 2x the
  // avatar + title + wrapped message + spinner no longer fit 568pt. Left
  // red deliberately -- the fix belongs in the screen, not here.
  testWidgets(
      'SessionSplashScreen survives the layout matrix without a '
      'message', (tester) async {
    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const SessionSplashScreen(),
      ),
    );
  });

  testWidgets(
      'SessionSplashScreen survives the layout matrix with a status '
      'message', (tester) async {
    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        // The longest message AuthController.restoreSession can actually
        // put on this screen. A much longer one overflows the unscrollable
        // Column at 320pt/2x -- see the note in this file's header.
        home: const SessionSplashScreen(
          message: 'No saved session on this device yet.',
        ),
      ),
    );
  });

  // The message state, not the bare one: it renders strictly more -- the muted
  // status line on top of everything the bare state has. Neither state has an
  // interactive control, so the tap-target guidelines are vacuous here and the
  // contrast of that muted line is the whole point.
  testWidgets('SessionSplashScreen meets accessibility guidelines',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const SessionSplashScreen(
          message: 'No saved session on this device yet.',
        ),
      ),
    );
    await pumpForAsyncUi(tester);
    expect(find.byType(SessionSplashScreen), findsOneWidget);

    await expectScreenMeetsAccessibilityGuidelines(tester);
  });
}
