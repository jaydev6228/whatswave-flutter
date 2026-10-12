import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/controllers/app_preferences_controller.dart';
import 'package:whatswave/core/session/app_lock_authenticator.dart';
import 'package:whatswave/core/widgets/app_lock_gate.dart';
import 'package:whatswave/features/settings/domain/app_lock_timeout.dart';

void main() {
  /// Pumps the gate unlocked, then backgrounds and resumes past the timeout
  /// so the lock engages -- the only way the overlay ever appears.
  Future<AppPreferencesController> lockTheApp(
    WidgetTester tester, {
    required AppLockAuthenticator authenticator,
  }) async {
    var now = DateTime(2026, 6, 3, 12);
    final controller = AppPreferencesController(nowProvider: () => now)
      ..setAppLockEnabled(true)
      ..setAppLockTimeout(AppLockTimeout.oneMinute);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          controller: controller,
          isEnabled: true,
          authenticator: authenticator,
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
    return controller;
  }

  testWidgets('prompts on its own and opens only on a successful check',
      (tester) async {
    final authenticator = _FakeAppLockAuthenticator(grant: true);

    await lockTheApp(tester, authenticator: authenticator);

    // The prompt fires without the user tapping anything first.
    expect(authenticator.attempts, 1);
    expect(find.byKey(const Key('app_lock_overlay')), findsNothing);
    expect(find.text('Unlocked app body'), findsOneWidget);
  });

  testWidgets('stays locked when the check is refused', (tester) async {
    // The regression that matters: the overlay used to wire its button
    // straight to unlockApp, so anyone holding the phone was one tap from
    // the entire message history.
    final authenticator = _FakeAppLockAuthenticator(grant: false);

    await lockTheApp(tester, authenticator: authenticator);

    expect(authenticator.attempts, 1);
    expect(find.byKey(const Key('app_lock_overlay')), findsOneWidget);
    expect(
      find.textContaining('did not match'),
      findsOneWidget,
      reason: 'the user should be told the check failed',
    );
  });

  testWidgets('a refused check can be retried', (tester) async {
    final authenticator = _FakeAppLockAuthenticator(grant: false);

    await lockTheApp(tester, authenticator: authenticator);
    expect(find.byKey(const Key('app_lock_overlay')), findsOneWidget);

    authenticator.grant = true;
    await tester.tap(find.byKey(const Key('app_lock_unlock_button')));
    await tester.pumpAndSettle();

    expect(authenticator.attempts, 2);
    expect(find.byKey(const Key('app_lock_overlay')), findsNothing);
  });

  testWidgets('tapping unlock while refused does not open the app',
      (tester) async {
    final authenticator = _FakeAppLockAuthenticator(grant: false);

    await lockTheApp(tester, authenticator: authenticator);
    await tester.tap(find.byKey(const Key('app_lock_unlock_button')));
    await tester.pumpAndSettle();

    expect(authenticator.attempts, 2);
    expect(find.byKey(const Key('app_lock_overlay')), findsOneWidget);
  });

  testWidgets('explains itself when the device has no lock to check against',
      (tester) async {
    // A device with no passcode and no enrolled biometric. Asking the OS
    // would fail forever, so the lock degrades to an explicit confirm and
    // says why rather than stranding the owner outside their own app.
    final authenticator = _FakeAppLockAuthenticator(
      method: AppLockMethod.unavailable,
      grant: false,
    );

    await lockTheApp(tester, authenticator: authenticator);

    expect(
      authenticator.attempts,
      0,
      reason: 'there is nothing to authenticate against, so do not try',
    );
    expect(find.textContaining('no passcode or biometric'), findsOneWidget);

    await tester.tap(find.byKey(const Key('app_lock_unlock_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app_lock_overlay')), findsNothing);
  });

  testWidgets('names the method it will use', (tester) async {
    final authenticator = _FakeAppLockAuthenticator(
      method: AppLockMethod.faceId,
      grant: false,
    );

    await lockTheApp(tester, authenticator: authenticator);

    // Denied, so the button offers a retry rather than the method name.
    expect(find.text('Try again'), findsOneWidget);
    expect(AppLockMethod.faceId.actionLabel, 'Unlock with Face ID');
  });

  testWidgets('covers the screen on the way out, before the OS snapshot',
      (tester) async {
    // The app switcher shows whatever the OS captured as the app left the
    // foreground. Locking only on resume meant that capture was the open
    // chat, readable by anyone who picked the phone up.
    final authenticator = _FakeAppLockAuthenticator(grant: false);
    final controller = AppPreferencesController(nowProvider: () => DateTime(2026))
      ..setAppLockEnabled(true)
      ..setAppLockTimeout(AppLockTimeout.oneMinute);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          controller: controller,
          isEnabled: true,
          authenticator: authenticator,
          child: const Scaffold(body: Center(child: Text('Unlocked app body'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app_lock_privacy_cover')), findsNothing);

    // inactive fires as the app switcher opens -- before the snapshot.
    controller.handleLifecycleChange(AppLifecycleState.inactive);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app_lock_privacy_cover')), findsOneWidget);
    expect(
      authenticator.attempts,
      0,
      reason: 'covering is not locking; nothing should be prompted yet',
    );
  });

  testWidgets('a quick switch away and back does not demand authentication',
      (tester) async {
    var now = DateTime(2026, 6, 3, 12);
    final authenticator = _FakeAppLockAuthenticator(grant: false);
    final controller = AppPreferencesController(nowProvider: () => now)
      ..setAppLockEnabled(true)
      ..setAppLockTimeout(AppLockTimeout.oneMinute);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          controller: controller,
          isEnabled: true,
          authenticator: authenticator,
          child: const Scaffold(body: Center(child: Text('Unlocked app body'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.handleLifecycleChange(AppLifecycleState.inactive);
    controller.handleLifecycleChange(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app_lock_privacy_cover')), findsOneWidget);

    now = now.add(const Duration(seconds: 5)); // well inside the timeout
    controller.handleLifecycleChange(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app_lock_privacy_cover')), findsNothing);
    expect(find.byKey(const Key('app_lock_overlay')), findsNothing);
    expect(authenticator.attempts, 0);
    expect(find.text('Unlocked app body'), findsOneWidget);
  });

  testWidgets('a transient interruption never starts the lock clock',
      (tester) async {
    // inactive also fires for a permission dialog or Control Centre. Those
    // must not count as "backgrounded" or a long dialog would lock the app.
    var now = DateTime(2026, 6, 3, 12);
    final authenticator = _FakeAppLockAuthenticator(grant: false);
    final controller = AppPreferencesController(nowProvider: () => now)
      ..setAppLockEnabled(true)
      ..setAppLockTimeout(AppLockTimeout.oneMinute);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          controller: controller,
          isEnabled: true,
          authenticator: authenticator,
          child: const Scaffold(body: Center(child: Text('Unlocked app body'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.handleLifecycleChange(AppLifecycleState.inactive);
    now = now.add(const Duration(minutes: 10));
    controller.handleLifecycleChange(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(controller.isAppLocked, isFalse);
    expect(find.byKey(const Key('app_lock_overlay')), findsNothing);
  });
}

class _FakeAppLockAuthenticator implements AppLockAuthenticator {
  _FakeAppLockAuthenticator({
    this.method = AppLockMethod.faceId,
    required this.grant,
  });

  AppLockMethod method;
  bool grant;
  int attempts = 0;

  @override
  Future<AppLockMethod> availableMethod() async => method;

  @override
  Future<bool> authenticate({required String reason}) async {
    attempts++;
    return grant;
  }
}
