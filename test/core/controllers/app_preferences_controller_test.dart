import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/core/controllers/app_preferences_controller.dart';
import 'package:whatswave/features/settings/domain/app_lock_timeout.dart';
import 'package:whatswave/features/settings/domain/privacy_audience.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('AppPreferencesController', () {
    test('updates theme mode on the happy path', () {
      final controller = AppPreferencesController();

      controller.setThemeMode(ThemeMode.dark);

      expect(controller.themeMode, ThemeMode.dark);
    });

    test('does not notify listeners when the same theme mode is set again', () {
      final controller = AppPreferencesController();
      var notifications = 0;

      controller.addListener(() {
        notifications += 1;
      });

      controller.setThemeMode(ThemeMode.system);

      expect(notifications, 0);
      expect(controller.themeMode, ThemeMode.system);
    });

    test('persists updated preferences and restores them on relaunch',
        () async {
      final firstController = AppPreferencesController();
      await firstController.ensureLoaded();

      firstController.setThemeMode(ThemeMode.dark);
      firstController.setAppLockEnabled(true);
      firstController.setAppLockTimeout(AppLockTimeout.fifteenMinutes);
      firstController.setNotificationsEnabled(false);
      firstController.setReadReceiptsEnabled(false);
      firstController.setLastSeenAudience(PrivacyAudience.nobody);
      firstController.setProfilePhotoAudience(PrivacyAudience.contacts);
      firstController.setStatusAudience(PrivacyAudience.everyone);
      firstController.setGroupsAudience(PrivacyAudience.nobody);
      firstController.setSecurityNotificationsEnabled(false);
      await firstController.waitForPendingPersistence();

      final relaunchedController = AppPreferencesController();
      await relaunchedController.ensureLoaded();

      expect(relaunchedController.themeMode, ThemeMode.dark);
      expect(relaunchedController.appLockEnabled, isTrue);
      expect(
        relaunchedController.appLockTimeout,
        AppLockTimeout.fifteenMinutes,
      );
      expect(relaunchedController.notificationsEnabled, isFalse);
      expect(relaunchedController.readReceiptsEnabled, isFalse);
      expect(relaunchedController.lastSeenAudience, PrivacyAudience.nobody);
      expect(
        relaunchedController.profilePhotoAudience,
        PrivacyAudience.contacts,
      );
      expect(relaunchedController.statusAudience, PrivacyAudience.everyone);
      expect(relaunchedController.groupsAudience, PrivacyAudience.nobody);
      expect(relaunchedController.securityNotificationsEnabled, isFalse);
    });

    test('locks the app after resume once the timeout elapses', () {
      var now = DateTime(2026, 6, 3, 10);
      final controller = AppPreferencesController(
        nowProvider: () => now,
      );

      controller.setAppLockEnabled(true);
      controller.setAppLockTimeout(AppLockTimeout.oneMinute);
      controller.handleLifecycleChange(AppLifecycleState.paused);

      now = now.add(const Duration(minutes: 2));
      controller.handleLifecycleChange(AppLifecycleState.resumed);

      expect(controller.isAppLocked, isTrue);

      controller.unlockApp();

      expect(controller.isAppLocked, isFalse);
    });

    test('does not lock the app before the timeout threshold', () {
      var now = DateTime(2026, 6, 3, 10);
      final controller = AppPreferencesController(
        nowProvider: () => now,
      );

      controller.setAppLockEnabled(true);
      controller.setAppLockTimeout(AppLockTimeout.fifteenMinutes);
      controller.handleLifecycleChange(AppLifecycleState.paused);

      now = now.add(const Duration(minutes: 3));
      controller.handleLifecycleChange(AppLifecycleState.resumed);

      expect(controller.isAppLocked, isFalse);
    });
  });
}
