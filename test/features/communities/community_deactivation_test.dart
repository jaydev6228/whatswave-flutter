import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/domain/chat_message.dart';
import 'package:whatswave/features/chats/domain/chat_thread.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/communities_overview.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/community_announcement.dart';
import 'package:whatswave/features/communities/domain/community_group_preview.dart';
import 'package:whatswave/features/communities/domain/community_hub.dart';
import 'package:whatswave/features/communities/presentation/community_detail_screen.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

/// Deactivating a community disconnects its member groups -- they survive
/// and stay usable -- closes the announcement group, drops the community
/// out of every member's list, and cannot be undone
/// (https://faq.whatsapp.com/785738926054798). It used to be a hard delete
/// of the community document, which took the group roster with it.

/// Deactivation belongs to the creator alone, so these fixtures make the
/// admin the owner: an admin who did not create the community is offered
/// exit, not deactivation.
CommunityHub _community({required String id, required bool viewerIsAdmin}) {
  return CommunityHub(
    id: id,
    title: 'Neighbourhood $id',
    description: 'Street updates.',
    avatarLabel: 'N',
    accentColor: const Color(0xFF00A884),
    memberCount: 4,
    viewerIsAdmin: viewerIsAdmin,
    ownerUid: viewerIsAdmin ? 'me' : 'someone-else',
    viewerUid: 'me',
    memberUids: const ['me'],
    adminUids: viewerIsAdmin ? const ['me'] : const ['someone-else'],
    announcementThreadId: '$id-announcements',
    announcement: CommunityAnnouncement(
      headline: 'Bin day moved',
      body: 'Collections shift to Thursday this week.',
      publishedAt: DateTime(2026, 1, 1),
    ),
    groups: [
      CommunityGroupPreview(
        id: '$id-general',
        name: 'General',
        summary: 'Everyone',
        memberCount: 4,
        lastActivityAt: DateTime(2026, 1, 2),
        threadId: '$id-general-thread',
      ),
    ],
  );
}

CommunitiesController _controllerOver(FakeCommunitiesRepository repository) {
  return CommunitiesController(
    repository: repository,
    permissionService: MemoryAppPermissionService(),
  );
}

/// Serves the demo communities with the viewer's admin role forced, since
/// only an admin is offered deactivation at all.
class _AdminRepository extends FakeCommunitiesRepository {
  _AdminRepository() : super(latency: Duration.zero);

  @override
  Future<CommunitiesOverview> fetchOverview() async {
    final overview = await super.fetchOverview();
    return CommunitiesOverview(
      communities: [
        for (final community in overview.communities)
          community.copyWith(viewerIsAdmin: true, ownerUid: 'me'),
      ],
      contacts: overview.contacts,
    );
  }
}

ChatThread _groupThread({
  required String id,
  required String name,
  required bool isCommunityGroup,
}) {
  return ChatThread(
    id: id,
    name: name,
    avatarLabel: name.substring(0, 1),
    accentColor: AppPalette.emerald,
    messages: [
      ChatMessage(
        id: '$id-m1',
        senderName: 'Priya',
        sentAt: DateTime(2026, 8, 9, 10),
        isFromCurrentUser: false,
        text: 'Match day is on',
      ),
    ],
    isGroup: true,
    isCommunityGroup: isCommunityGroup,
  );
}

void main() {
  test('a deactivated community leaves the list for every member', () async {
    final repository = FakeCommunitiesRepository(
      latency: Duration.zero,
      initialCommunities: [
        _community(id: 'mine', viewerIsAdmin: true),
        _community(id: 'other', viewerIsAdmin: true),
      ],
      initialContacts: DemoData.buildCommunityContacts(),
    );
    // Two sessions over one store: the second stands in for another member,
    // who never called deactivate and whose list must lose the community
    // anyway. A hard delete got that for free; a state change only gets it
    // if the overview itself filters deactivated communities out.
    final admin = _controllerOver(repository);
    final otherMember = _controllerOver(repository);
    await admin.loadOverview();
    await otherMember.loadOverview();

    final didDeactivate = await admin.deactivateCommunity('mine');

    expect(didDeactivate, isTrue);
    expect(admin.errorMessage, isNull);
    expect(admin.communities.map((community) => community.id), ['other']);

    await otherMember.loadOverview();
    expect(
      otherMember.communities.map((community) => community.id),
      ['other'],
    );
  });

  test('deactivating keeps the community itself instead of destroying it',
      () async {
    final repository = FakeCommunitiesRepository(
      latency: Duration.zero,
      initialCommunities: [_community(id: 'mine', viewerIsAdmin: true)],
      initialContacts: DemoData.buildCommunityContacts(),
    );
    final controller = _controllerOver(repository);
    await controller.loadOverview();

    await controller.deactivateCommunity('mine');

    expect(controller.communities, isEmpty);
    // The document survives with its group roster, which is what lets the
    // member groups be released rather than stranded -- deleting it took
    // the only record of which threads belonged here.
    expect(repository.debugCommunityIdsInStore, ['mine']);
  });

  test('a released community group thread is an ordinary chat again',
      () async {
    // The Chats-side half of the contract deactivation relies on:
    // FirestoreCommunitiesRepository._releaseGroupThreads clears
    // isCommunityGroup on each member group's thread, and cleared, the
    // thread is back in the chat list and can still be messaged. Left set
    // (the announcement thread, and every group thread before this change)
    // it is filtered out of every Chats surface, so a thread whose
    // community is gone would be reachable from nowhere.
    final chats = ChatsController(
      repository: FakeChatRepository(
        latency: Duration.zero,
        initialThreads: [
          _groupThread(
            id: 'announcements',
            name: 'Announcements',
            isCommunityGroup: true,
          ),
          _groupThread(
            id: 'released-general',
            name: 'General',
            isCommunityGroup: false,
          ),
        ],
      ),
    );
    await chats.loadThreads();

    expect(
      chats.inboxThreads().map((thread) => thread.id),
      ['released-general'],
    );

    final didSend = await chats.sendTextMessage(
      threadId: 'released-general',
      text: 'Still works',
    );
    expect(didSend, isTrue);
    expect(
      chats.threadById('released-general')?.latestMessage?.text,
      'Still works',
    );
  });

  testWidgets('the confirm dialog says what deactivation actually does',
      (tester) async {
    final controller = _controllerOver(_AdminRepository());
    await controller.ensureLoaded();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: CommunityDetailScreen(
          communityId: controller.communities.first.id,
          controller: controller,
          chatsController: ChatsController(
            repository: FakeChatRepository(latency: Duration.zero),
          ),
          callsController: CallsController(
            repository: FakeCallsRepository(latency: Duration.zero),
          ),
          updatesController: UpdatesController(
            repository: FakeUpdatesRepository(latency: Duration.zero),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('community_detail_menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('community_detail_delete_menu_item')),
    );
    await tester.pumpAndSettle();

    // It used to promise the opposite of what happens ("permanently removes
    // X and its groups for everyone").
    expect(
      find.textContaining('groups keep working as ordinary group chats'),
      findsOneWidget,
    );
    expect(find.textContaining('announcements close'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
  });
}
