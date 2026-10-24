import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/settings/presentation/blocked_contacts_screen.dart';

import '../../support/device_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<ChatsController> loadedChats() async {
    final controller = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
    );
    await controller.ensureLoaded();
    return controller;
  }

  // Nothing is blocked in the seeded data, so the default render only ever
  // exercises the empty state. The populated list is the other half, so it
  // needs its own pass with a thread blocked first.
  //
  // KNOWN FAILURE, not a broken test: the empty state overflows by 216px at
  // 320x568 / 2.0x text. EmptyStateCard is wrapped in a bare
  // Padding(EdgeInsets.all(24)) with no scroll view, so its Column has
  // nowhere to grow when the icon, title and message all double. Left red
  // deliberately -- the fix belongs in the screen, not here.
  testWidgets('BlockedContactsScreen survives the layout matrix when empty',
      (tester) async {
    final chatsController = await loadedChats();

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: BlockedContactsScreen(chatsController: chatsController),
      ),
    );
  });

  testWidgets('BlockedContactsScreen survives the layout matrix with blocked '
      'contacts', (tester) async {
    final chatsController = await loadedChats();
    for (final thread in chatsController.threads.take(3).toList()) {
      await chatsController.setThreadBlocked(
        threadId: thread.id,
        isBlocked: true,
      );
    }
    expect(
      chatsController.threads.where((thread) => thread.isBlocked),
      isNotEmpty,
      reason: 'the populated branch is the point of this test',
    );

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: BlockedContactsScreen(chatsController: chatsController),
      ),
    );
  });
}
