import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/controllers/app_preferences_controller.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/settings/presentation/storage_data_screen.dart';

import '../../support/device_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('StorageDataScreen survives the layout matrix', (tester) async {
    final preferencesController = AppPreferencesController();
    await preferencesController.ensureLoaded();

    final chatsController = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
    );
    await chatsController.ensureLoaded();

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: StorageDataScreen(
          chatsController: chatsController,
          preferencesController: preferencesController,
        ),
      ),
    );
  });
}
