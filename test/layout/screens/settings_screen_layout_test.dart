import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/controllers/app_preferences_controller.dart';
import 'package:whatswave/core/integrations/integration_hub_controller.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/auth/application/auth_controller.dart';
import 'package:whatswave/features/auth/data/fake_auth_repository.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/settings/presentation/settings_screen.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

import '../../support/device_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // Returns a builder, not a widget: the layout sweep rebuilds for every
  // size/variant combination on purpose, so a screen holding controllers
  // does not carry state between them. The controllers themselves are set
  // up once -- loading them is the expensive part, not the screen.
  //
  // Builds the bare screen rather than a whole MaterialApp, because the two
  // tests need different wrappers: the sweep only needs a theme, while the
  // accessibility check needs the Scaffold that AppShell really supplies
  // (see the note on that test).
  Future<Widget Function()> settingsScreenBuilder(WidgetTester tester) async {
    final authController = AuthController(
      repository: FakeAuthRepository(
        restoredUser: DemoData.currentUser,
        latency: Duration.zero,
      ),
    );
    // runAsync, not a bare await: FakeAuthRepository._wait() arms a
    // Future.delayed even at zero latency, and a fake-async timer does not
    // fire until the first pump -- so awaiting it here would deadlock.
    await tester.runAsync(authController.restoreSession);

    final preferencesController = AppPreferencesController();
    await preferencesController.ensureLoaded();

    final integrationController = IntegrationHubController();
    await integrationController.ensureLoaded();

    return () => SettingsScreen(
          authController: authController,
          currentUser: authController.currentUser ?? DemoData.currentUser,
          preferencesController: preferencesController,
          integrationController: integrationController,
          chatsController: ChatsController(
            repository: FakeChatRepository(latency: Duration.zero),
          ),
          callsController: CallsController(
            repository: FakeCallsRepository(latency: Duration.zero),
          ),
          updatesController: UpdatesController(
            repository: FakeUpdatesRepository(latency: Duration.zero),
          ),
          communitiesController: CommunitiesController(
            repository: FakeCommunitiesRepository(latency: Duration.zero),
          ),
        );
  }

  testWidgets('SettingsScreen survives the layout matrix', (tester) async {
    final buildScreen = await settingsScreenBuilder(tester);

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: buildScreen(),
      ),
    );
  });

  // Accessibility is its own test, not an extra assertion on the sweep above:
  // a contrast failure reported as a layout failure tells nobody what broke.
  // One realistic size, default text scale -- the guidelines are about colour
  // and target size, which do not need the size matrix.
  //
  // The Scaffold is not decoration. This screen is a tab body and has no
  // Scaffold of its own -- AppShell supplies it. Pumped straight into `home`
  // nothing opaque paints behind it, and the contrast guideline then samples
  // a transparent backdrop and reports every line on the screen as failing
  // at ratios like 1.23 that have nothing to do with the palette. The
  // Scaffold reproduces the parent the screen actually ships inside.
  testWidgets('SettingsScreen meets accessibility guidelines', (tester) async {
    final buildScreen = await settingsScreenBuilder(tester);

    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: Scaffold(body: buildScreen()),
      ),
    );
    await pumpForAsyncUi(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);

    await expectScreenMeetsAccessibilityGuidelines(tester);
  });
}
