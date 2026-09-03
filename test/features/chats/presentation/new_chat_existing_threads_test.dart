import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/domain/chat_message.dart';
import 'package:whatswave/features/chats/domain/chat_thread.dart';
import 'package:whatswave/features/chats/presentation/new_chat_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/community_contact.dart';
import 'package:whatswave/features/communities/domain/contact_access_status.dart';

// Ava has an active thread, Noah an archived one, Mia none at all, and Emi
// isn't on WhatsWave -- one contact per rule the "On WhatsWave" list has to
// enforce.
const _contacts = <CommunityContact>[
  CommunityContact(
    id: 'ava-patel',
    name: 'Ava Patel',
    phoneNumber: '+81 90 3000 1122',
    avatarLabel: 'AP',
    accentColor: AppPalette.green,
    about: 'Already chatting.',
    matchedUid: 'uid-ava',
  ),
  CommunityContact(
    id: 'noah-kim',
    name: 'Noah Kim',
    phoneNumber: '+81 90 3000 2233',
    avatarLabel: 'NK',
    accentColor: AppPalette.sky,
    about: 'Archived chat.',
    matchedUid: 'uid-noah',
  ),
  CommunityContact(
    id: 'mia-ono',
    name: 'Mia Ono',
    phoneNumber: '+81 90 3000 4455',
    avatarLabel: 'MO',
    accentColor: AppPalette.emerald,
    about: 'Never chatted.',
    matchedUid: 'uid-mia',
  ),
  CommunityContact(
    id: 'emi-tanaka',
    name: 'Emi Tanaka',
    phoneNumber: '+81 90 3000 5566',
    avatarLabel: 'ET',
    accentColor: AppPalette.emerald,
    about: 'Not on WhatsWave yet.',
    isOnWhatsWave: false,
  ),
];

ChatThread _thread({
  required String id,
  required String name,
  required String participantUid,
  bool isArchived = false,
}) {
  return ChatThread(
    id: id,
    name: name,
    avatarLabel: 'XX',
    accentColor: AppPalette.green,
    participantUid: participantUid,
    isArchived: isArchived,
    messages: [
      ChatMessage(
        id: '$id-message',
        senderName: name,
        senderUid: participantUid,
        sentAt: DateTime(2026, 1, 1, 9),
        isFromCurrentUser: false,
        text: 'Hello',
      ),
    ],
  );
}

Future<ChatsController> _loadedChats(List<ChatThread> threads) async {
  final controller = ChatsController(
    repository: FakeChatRepository(
      latency: Duration.zero,
      initialThreads: threads,
    ),
  );
  await controller.loadThreads();
  return controller;
}

Future<void> _openNewChat(
  WidgetTester tester,
  ChatsController chatsController,
) async {
  final communitiesController = CommunitiesController(
    repository: FakeCommunitiesRepository(
      latency: Duration.zero,
      initialContacts: _contacts,
    ),
    permissionService: MemoryAppPermissionService(
      contactsStatus: ContactAccessStatus.granted,
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(),
      home: NewChatScreen(
        communitiesController: communitiesController,
        chatsController: chatsController,
        callsController: CallsController(
          repository: FakeCallsRepository(latency: Duration.zero),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'hides contacts with an active or archived thread, keeps the rest and '
      'the invite section', (tester) async {
    final chatsController = await _loadedChats([
      _thread(id: 'ava', name: 'Ava Patel', participantUid: 'uid-ava'),
      _thread(
        id: 'noah',
        name: 'Noah Kim',
        participantUid: 'uid-noah',
        isArchived: true,
      ),
    ]);

    await _openNewChat(tester, chatsController);

    expect(find.byKey(const Key('new_chat_contact_ava-patel')), findsNothing);
    expect(find.byKey(const Key('new_chat_contact_noah-kim')), findsNothing);
    expect(find.byKey(const Key('new_chat_contact_mia-ono')), findsOneWidget);
    expect(find.text('On WhatsWave'), findsOneWidget);

    expect(find.text('Invite to WhatsWave'), findsOneWidget);
    expect(find.byKey(const Key('new_chat_invite_emi-tanaka')), findsOneWidget);
  });

  testWidgets('a contact whose chat was deleted shows up again',
      (tester) async {
    final chatsController = await _loadedChats([
      _thread(id: 'ava', name: 'Ava Patel', participantUid: 'uid-ava'),
    ]);
    // Deleting a chat leaves no thread behind (a per-user hide server-side,
    // a removal in the fake repository), which is what makes the contact
    // startable again.
    expect(await chatsController.deleteThread('ava'), isTrue);

    await _openNewChat(tester, chatsController);

    expect(find.byKey(const Key('new_chat_contact_ava-patel')), findsOneWidget);
  });

  testWidgets('a contact that cannot be matched to a thread still shows',
      (tester) async {
    // Same phone-book contacts, but the thread carries no participantUid --
    // no confident match, so nobody gets hidden.
    final chatsController = await _loadedChats([
      ChatThread(
        id: 'unmatched',
        name: 'Ava Patel',
        avatarLabel: 'AP',
        accentColor: AppPalette.green,
        messages: [
          ChatMessage(
            id: 'unmatched-message',
            senderName: 'Ava Patel',
            sentAt: DateTime(2026, 1, 1, 9),
            isFromCurrentUser: false,
            text: 'Hello',
          ),
        ],
      ),
    ]);

    await _openNewChat(tester, chatsController);

    expect(find.byKey(const Key('new_chat_contact_ava-patel')), findsOneWidget);
  });
}
