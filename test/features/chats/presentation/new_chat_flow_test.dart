import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/presentation/new_chat_screen.dart';
import 'package:whatswave/features/chats/presentation/new_group_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/community_contact.dart';
import 'package:whatswave/features/communities/domain/contact_access_status.dart';

const _reachableContacts = <CommunityContact>[
  CommunityContact(
    id: 'ava-patel',
    name: 'Ava Patel',
    phoneNumber: '+81 90 3000 1122',
    avatarLabel: 'AP',
    accentColor: AppPalette.green,
    about: 'Already on WhatsWave.',
    matchedUid: 'uid-ava',
  ),
  CommunityContact(
    id: 'noah-kim',
    name: 'Noah Kim',
    phoneNumber: '+81 90 3000 2233',
    avatarLabel: 'NK',
    accentColor: AppPalette.sky,
    about: 'Already on WhatsWave.',
    matchedUid: 'uid-noah',
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

void main() {
  testWidgets('messages an on-WhatsWave contact and pops with the thread id',
      (tester) async {
    final communitiesController = CommunitiesController(
      repository: FakeCommunitiesRepository(
        latency: Duration.zero,
        initialContacts: _reachableContacts,
      ),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );
    final chatsController = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
    );
    final callsController = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
    );

    String? capturedThreadId;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                capturedThreadId = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) => NewChatScreen(
                      communitiesController: communitiesController,
                      chatsController: chatsController,
                      callsController: callsController,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new_chat_screen')), findsOneWidget);
    expect(find.byKey(const Key('new_chat_new_group')), findsOneWidget);
    expect(find.text('Ava Patel'), findsOneWidget);
    expect(find.byKey(const Key('new_chat_call_audio_ava-patel')), findsOneWidget);
    expect(find.byKey(const Key('new_chat_call_video_ava-patel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('new_chat_contact_ava-patel')));
    await tester.pumpAndSettle();

    expect(capturedThreadId, isNotNull);
    expect(find.byKey(const Key('new_chat_screen')), findsNothing);
  });

  testWidgets('shares an invite for a contact not on WhatsWave yet',
      (tester) async {
    final communitiesController = CommunitiesController(
      repository: FakeCommunitiesRepository(
        latency: Duration.zero,
        initialContacts: _reachableContacts,
      ),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );
    final chatsController = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
    );
    final callsController = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: NewChatScreen(
          communitiesController: communitiesController,
          chatsController: chatsController,
          callsController: callsController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Emi Tanaka'), findsOneWidget);
    await tester.tap(find.byKey(const Key('new_chat_invite_emi-tanaka')));
    await tester.pumpAndSettle();

    expect(find.text('Invite Emi Tanaka'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(
      communitiesController.contactById('emi-tanaka')?.appInviteSent,
      isTrue,
    );
  });

  testWidgets('creates a group from selected members and pops with its id',
      (tester) async {
    final communitiesController = CommunitiesController(
      repository: FakeCommunitiesRepository(
        latency: Duration.zero,
        initialContacts: _reachableContacts,
      ),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );
    await communitiesController.ensureLoaded();
    final chatsController = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
    );

    String? capturedThreadId;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                capturedThreadId = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) => NewGroupScreen(
                      communitiesController: communitiesController,
                      chatsController: chatsController,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new_group_members_screen')), findsOneWidget);
    await tester.tap(find.byKey(const Key('new_group_member_ava-patel')));
    await tester.tap(find.byKey(const Key('new_group_member_noah-kim')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('new_group_next_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new_group_details_screen')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('new_group_name_field')),
      'Launch Crew',
    );
    await tester.tap(find.byKey(const Key('new_group_create_button')));
    await tester.pumpAndSettle();

    expect(capturedThreadId, isNotNull);
    final thread = chatsController.threadById(capturedThreadId!);
    expect(thread?.isGroup, isTrue);
    expect(thread?.name, 'Launch Crew');
  });

  testWidgets(
      'system back on the name step returns to member selection instead of exiting',
      (tester) async {
    final communitiesController = CommunitiesController(
      repository: FakeCommunitiesRepository(
        latency: Duration.zero,
        initialContacts: _reachableContacts,
      ),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );
    await communitiesController.ensureLoaded();
    final chatsController = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: NewGroupScreen(
          communitiesController: communitiesController,
          chatsController: chatsController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('new_group_member_ava-patel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new_group_next_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new_group_details_screen')), findsOneWidget);
    await tester.tap(find.byKey(const Key('new_group_back_to_members')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new_group_members_screen')), findsOneWidget);
  });
}
