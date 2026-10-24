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

  testWidgets('SettingsScreen survives the layout matrix', (tester) async {
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

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: SettingsScreen(
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
        ),
      ),
    );
  });
}
