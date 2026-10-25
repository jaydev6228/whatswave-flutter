import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';
import 'package:whatswave/features/updates/presentation/updates_screen.dart';

import '../../support/device_matrix.dart';

/// Accessibility coverage for the Updates tab. Behavioural layout coverage
/// already lives in test/features/updates/presentation/updates_screen_test.dart;
/// this adds the screen-reader side of it.
void main() {
  testWidgets('UpdatesScreen meets accessibility guidelines', (tester) async {
    final controller = UpdatesController(
      repository: FakeUpdatesRepository(latency: Duration.zero),
    );

    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: Scaffold(
          body: UpdatesScreen(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Proof the guidelines below ran against a rendered feed rather than an
    // empty tree, which would pass every one of them.
    expect(find.byType(UpdatesScreen), findsOneWidget);
    expect(find.byKey(const Key('updates_my_status_card')), findsOneWidget);

    await expectScreenMeetsAccessibilityGuidelines(tester);
  });
}
