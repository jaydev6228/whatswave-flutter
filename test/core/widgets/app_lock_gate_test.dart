import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/controllers/app_preferences_controller.dart';
import 'package:whatswave/core/widgets/app_lock_gate.dart';
import 'package:whatswave/features/settings/domain/app_lock_timeout.dart';

void main() {
  testWidgets('shows the app lock overlay after resume and unlocks cleanly',
      (tester) async {
    var now = DateTime(2026, 6, 3, 12);
    final controller = AppPreferencesController(
      nowProvider: () => now,
    )
      ..setAppLockEnabled(true)
      ..setAppLockTimeout(AppLockTimeout.oneMinute);

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          controller: controller,
          isEnabled: true,
          child: const Scaffold(
            body: Center(child: Text('Unlocked app body')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app_lock_overlay')), findsNothing);

    controller.handleLifecycleChange(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 2));
    controller.handleLifecycleChange(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app_lock_overlay')), findsOneWidget);

    await tester.tap(find.byKey(const Key('app_lock_unlock_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app_lock_overlay')), findsNothing);
    expect(find.text('Unlocked app body'), findsOneWidget);
  });
}
