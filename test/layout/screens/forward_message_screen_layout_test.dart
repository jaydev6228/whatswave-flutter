import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/presentation/forward_message_screen.dart';

import '../../support/device_matrix.dart';

void main() {
  testWidgets('ForwardMessageScreen survives the layout matrix',
      (tester) async {
    final chatsController = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
    );
    await chatsController.loadThreads();
    addTearDown(chatsController.dispose);

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: ForwardMessageScreen(controller: chatsController),
      ),
    );
  });
}
