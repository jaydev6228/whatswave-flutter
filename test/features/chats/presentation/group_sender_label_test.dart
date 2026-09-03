import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/auth/application/auth_controller.dart';
import 'package:whatswave/features/auth/data/fake_auth_repository.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/domain/chat_message.dart';
import 'package:whatswave/features/chats/domain/chat_thread.dart';
import 'package:whatswave/features/chats/domain/group_participant.dart';
import 'package:whatswave/features/chats/presentation/chats_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

import '../../../support/device_matrix.dart';

/// A group where the roster knows the sender by their CURRENT name while
/// the message still carries the name captured when it was sent.
ChatThread _renamedSenderThread({
  required String rosterName,
  required String nameWhenSent,
  String? senderUid = 'uid-priya',
}) {
  return ChatThread(
    id: 'rename-group',
    name: 'Rename Group',
    avatarLabel: 'RG',
    accentColor: const Color(0xFF128C7E),
    isGroup: true,
    participants: [
      GroupParticipant(
        uid: 'uid-me',
        name: 'You',
        avatarLabel: 'ME',
        accentColor: const Color(0xFF128C7E),
        isSelf: true,
      ),
      GroupParticipant(
        uid: 'uid-priya',
        name: rosterName,
        avatarLabel: 'PR',
        accentColor: const Color(0xFF8C6BFF),
      ),
    ],
    messages: [
      ChatMessage(
        id: 'group-message',
        senderName: nameWhenSent,
        senderUid: senderUid,
        sentAt: DateTime(2026, 1, 1, 9),
        isFromCurrentUser: false,
        text: 'Sent before the rename',
      ),
    ],
  );
}

Future<void> _openThread(WidgetTester tester, ChatThread thread) async {
  await tester.binding.setSurfaceSize(iphoneProProfile.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Scaffold(
        body: ChatsScreen(
          callsController: CallsController(
            repository: FakeCallsRepository(latency: Duration.zero),
          ),
          communitiesController: CommunitiesController(
            repository: FakeCommunitiesRepository(latency: Duration.zero),
          ),
          controller: ChatsController(
            repository: FakeChatRepository(
              latency: Duration.zero,
              initialThreads: [thread],
            ),
            permissionService: MemoryAppPermissionService(),
          ),
          updatesController: UpdatesController(
            repository: FakeUpdatesRepository(latency: Duration.zero),
          ),
          authController: AuthController(
            repository: FakeAuthRepository(latency: Duration.zero),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('chat_tile_rename-group')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a group bubble labels itself from the live roster',
      (tester) async {
    // ChatMessage.senderName is a snapshot taken at send time, so renaming
    // someone left every message they had already sent labelled with their
    // old name forever.
    await _openThread(
      tester,
      _renamedSenderThread(rosterName: 'Priya Sharma', nameWhenSent: 'Priya'),
    );

    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('Priya'), findsNothing);
  });

  testWidgets('a sender the roster cannot answer for keeps its snapshot',
      (tester) async {
    // Someone who has since left the group, or a backend that never
    // recorded senderUid. A stale name beats a blank one.
    await _openThread(
      tester,
      _renamedSenderThread(
        rosterName: 'Priya Sharma',
        nameWhenSent: 'Departed Member',
        senderUid: 'uid-who-left',
      ),
    );

    expect(find.text('Departed Member'), findsOneWidget);
  });

  testWidgets('a message with no sender uid keeps its snapshot',
      (tester) async {
    await _openThread(
      tester,
      _renamedSenderThread(
        rosterName: 'Priya Sharma',
        nameWhenSent: 'Seeded Name',
        senderUid: null,
      ),
    );

    expect(find.text('Seeded Name'), findsOneWidget);
  });
}
