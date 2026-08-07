import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/core/controllers/app_preferences_controller.dart';
import 'package:whatswave/core/integrations/integration_hub_controller.dart';
import 'package:whatswave/core/models/app_user.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/auth/application/auth_controller.dart';
import 'package:whatswave/features/auth/data/auth_repository.dart';
import 'package:whatswave/features/settings/domain/privacy_audience.dart';
import 'package:whatswave/features/settings/presentation/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('shows the richer Phase 7 settings sections on the happy path',
      (tester) async {
    final authController = await _createAuthenticatedAuthController();
    final preferencesController = AppPreferencesController();
    await preferencesController.ensureLoaded();

    await _pumpSettingsScreen(
      tester,
      authController: authController,
      preferencesController: preferencesController,
    );

    expect(find.byKey(const Key('settings_profile_header')), findsOneWidget);
    expect(find.text('Theme mode'), findsOneWidget);
    expect(find.text('Privacy center'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.byKey(const Key('settings_backend_sync_tile')), findsOneWidget);
  });

  testWidgets('edits the profile and refreshes the settings header',
      (tester) async {
    final authController = await _createAuthenticatedAuthController();
    final preferencesController = AppPreferencesController();
    await preferencesController.ensureLoaded();

    await _pumpSettingsScreen(
      tester,
      authController: authController,
      preferencesController: preferencesController,
    );

    await tester.tap(find.byKey(const Key('settings_profile_edit_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('profile_name_field')),
      'Taylor Devra',
    );
    await tester.enterText(
      find.byKey(const Key('profile_about_field')),
      'Keeping settings, privacy, and quality bars aligned.',
    );
    await tester.tap(find.byKey(const Key('profile_save_button')));
    await tester.pumpAndSettle();

    expect(authController.currentUser?.name, 'Taylor Devra');
    expect(find.text('Taylor Devra'), findsOneWidget);
  });

  testWidgets('surfaces a validation error when the edited profile is invalid',
      (tester) async {
    final authController = await _createAuthenticatedAuthController();
    final preferencesController = AppPreferencesController();
    await preferencesController.ensureLoaded();

    await _pumpSettingsScreen(
      tester,
      authController: authController,
      preferencesController: preferencesController,
    );

    await tester.tap(find.byKey(const Key('settings_profile_edit_button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('profile_name_field')), 'A');
    await tester.tap(find.byKey(const Key('profile_save_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Use at least 2 characters for your display name.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('profile_settings_screen')), findsOneWidget);
  });

  testWidgets('updates privacy audiences and security toggles', (tester) async {
    final authController = await _createAuthenticatedAuthController();
    final preferencesController = AppPreferencesController();
    await preferencesController.ensureLoaded();

    await _pumpSettingsScreen(
      tester,
      authController: authController,
      preferencesController: preferencesController,
    );

    await _scrollUntilVisibleOnSettings(
      tester,
      find.byKey(const Key('settings_privacy_center_tile')),
    );
    await tester.tap(find.byKey(const Key('settings_privacy_center_tile')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('privacy_last_seen_tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy_audience_option_nobody')));
    await tester.pumpAndSettle();

    await _scrollUntilVisibleOnPrivacy(
      tester,
      find.byKey(const Key('privacy_app_lock_switch')),
    );
    await tester.tap(find.byKey(const Key('privacy_app_lock_switch')));
    await tester.pumpAndSettle();
    await _scrollUntilVisibleOnPrivacy(
      tester,
      find.byKey(const Key('privacy_security_notifications_switch')),
    );
    await tester.tap(
      find.byKey(const Key('privacy_security_notifications_switch')),
    );
    await tester.pumpAndSettle();

    expect(preferencesController.lastSeenAudience, PrivacyAudience.nobody);
    expect(preferencesController.appLockEnabled, isTrue);
    expect(preferencesController.securityNotificationsEnabled, isFalse);
  });

  testWidgets('opens the backend and sync center from settings',
      (tester) async {
    final authController = await _createAuthenticatedAuthController();
    final preferencesController = AppPreferencesController();
    await preferencesController.ensureLoaded();
    final integrationController = IntegrationHubController();
    await integrationController.ensureLoaded();
    await integrationController.applyRuntimeContext(
      notificationsEnabled: true,
      isAuthenticated: true,
    );
    await integrationController.recordSyncSuccess(
      source: 'Chats',
      title: 'Message synced',
      details: 'Hello there',
    );
    await integrationController.queueMediaTransfer(
      source: 'Updates',
      label: 'Status photo',
      kind: MediaTransferKind.statusPhoto,
    );

    await _pumpSettingsScreen(
      tester,
      authController: authController,
      preferencesController: preferencesController,
      integrationController: integrationController,
    );

    await _scrollUntilVisibleOnSettings(
      tester,
      find.byKey(const Key('settings_backend_sync_tile')),
    );
    await tester.tap(find.byKey(const Key('settings_backend_sync_tile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backend_sync_screen')), findsOneWidget);
    expect(
      find.byKey(const Key('backend_sync_provider_readiness_card')),
      findsOneWidget,
    );
    expect(
        find.byKey(const Key('backend_sync_repository_card')), findsOneWidget);
    expect(find.byKey(const Key('backend_sync_push_card')), findsOneWidget);
    expect(find.text('Provider readiness'), findsOneWidget);
    expect(find.text('Repository adapters'), findsOneWidget);
    expect(find.text('FlutterFire adapters'), findsOneWidget);
    expect(find.text('Auth and session'), findsOneWidget);
    expect(find.text('Local push simulator'), findsOneWidget);
    expect(
      find.text('Active upload adapter: Local media transfer pipeline'),
      findsOneWidget,
    );
    expect(find.text('Recent sync activity'), findsOneWidget);
    expect(find.text('Media pipeline'), findsOneWidget);
    expect(find.text('Message synced'), findsOneWidget);
    expect(find.text('Status photo'), findsOneWidget);
  });

  testWidgets('keeps the session when sign out is cancelled', (tester) async {
    final authController = await _createAuthenticatedAuthController();
    final preferencesController = AppPreferencesController();
    await preferencesController.ensureLoaded();

    await _pumpSettingsScreen(
      tester,
      authController: authController,
      preferencesController: preferencesController,
    );

    await _scrollUntilVisibleOnSettings(
      tester,
      find.byKey(const Key('settings_sign_out_tile')),
    );
    await tester.tap(find.byKey(const Key('settings_sign_out_tile')));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(authController.isAuthenticated, isTrue);
  });

  testWidgets('signs out and returns to phone entry when confirmed',
      (tester) async {
    final authController = await _createAuthenticatedAuthController();
    final preferencesController = AppPreferencesController();
    await preferencesController.ensureLoaded();

    await _pumpSettingsScreen(
      tester,
      authController: authController,
      preferencesController: preferencesController,
    );

    await _scrollUntilVisibleOnSettings(
      tester,
      find.byKey(const Key('settings_sign_out_tile')),
    );
    await tester.tap(find.byKey(const Key('settings_sign_out_tile')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings_confirm_sign_out_button')));
    await tester.pumpAndSettle();

    expect(authController.isAuthenticated, isFalse);
    expect(authController.step, AuthStep.phoneEntry);
  });
}

Future<AuthController> _createAuthenticatedAuthController() async {
  final controller = AuthController(
    repository: _ImmediateAuthRepository(
      restoredUser: DemoData.currentUser,
    ),
  );
  await controller.restoreSession();
  return controller;
}

Future<void> _pumpSettingsScreen(
  WidgetTester tester, {
  required AuthController authController,
  required AppPreferencesController preferencesController,
  IntegrationHubController? integrationController,
}) async {
  final backendController = integrationController ?? IntegrationHubController();
  await backendController.ensureLoaded();
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        authController: authController,
        currentUser: authController.currentUser ?? DemoData.currentUser,
        preferencesController: preferencesController,
        integrationController: backendController,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _scrollUntilVisibleOnSettings(
  WidgetTester tester,
  Finder finder,
) async {
  final scrollable = find
      .descendant(
        of: find.byKey(const Key('settings_screen')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: scrollable,
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollUntilVisibleOnPrivacy(
  WidgetTester tester,
  Finder finder,
) async {
  final scrollable = find
      .descendant(
        of: find.byKey(const Key('privacy_settings_scroll_view')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: scrollable,
  );
  await tester.pumpAndSettle();
}

class _ImmediateAuthRepository implements AuthRepository {
  _ImmediateAuthRepository({required this.restoredUser});

  AppUser? restoredUser;

  @override
  Future<AppUser> completeProfile({
    required String phoneNumber,
    required String name,
    required String about,
  }) async {
    final user = _buildUser(
      phoneNumber: phoneNumber,
      name: name,
      about: about,
    );
    restoredUser = user;
    return user;
  }

  @override
  Future<void> requestOtp(String phoneNumber) async {}

  @override
  Future<AppUser?> restoreSession() async => restoredUser;

  @override
  Future<void> signOut() async {
    restoredUser = null;
  }

  @override
  Future<AuthVerificationResult> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    final user = restoredUser;
    if (user == null) {
      return const AuthVerificationResult.profileRequired();
    }
    return AuthVerificationResult.authenticated(user);
  }

  @override
  Future<AppUser> updateCurrentProfile({
    required String name,
    required String about,
  }) async {
    final currentUser = restoredUser ?? DemoData.currentUser;
    final updatedUser = _buildUser(
      phoneNumber: currentUser.phoneNumber,
      name: name,
      about: about,
    );
    restoredUser = updatedUser;
    return updatedUser;
  }

  AppUser _buildUser({
    required String phoneNumber,
    required String name,
    required String about,
  }) {
    final trimmedName = name.trim();
    final parts = trimmedName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final avatarLabel = switch (parts.length) {
      0 => 'WW',
      1 => parts.first.substring(0, parts.first.length >= 2 ? 2 : 1),
      _ => '${parts.first[0]}${parts.last[0]}',
    }
        .toUpperCase();
    return AppUser(
      name: trimmedName,
      phoneNumber: phoneNumber,
      about: about.trim(),
      avatarLabel: avatarLabel,
      accentColor: Colors.green,
    );
  }
}
