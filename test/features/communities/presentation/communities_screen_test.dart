import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/domain/chat_thread.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/contact_access_status.dart';
import 'package:whatswave/features/communities/presentation/communities_screen.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

import '../../../support/device_matrix.dart';

void main() {
  testWidgets('creates a community, opens detail, and invites a contact',
      (tester) async {
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );

    await _pumpCommunitiesScreen(
      tester,
      device: iphoneProProfile,
      controller: controller,
    );

    await tester.tap(find.byKey(const Key('communities_create_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('communities_create_name_field')),
      'Japan Food Club',
    );
    await tester.enterText(
      find.byKey(const Key('communities_create_description_field')),
      'Restaurant planning, bookings, and photo drops.',
    );
    await tester.tap(find.byKey(const Key('communities_create_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Japan Food Club'), findsOneWidget);
    final createdCommunityId = controller.communities.first.id;

    await _scrollUntilVisible(
      tester,
      find.byKey(Key('community_card_$createdCommunityId')),
    );
    await tester.tap(find.byKey(Key('community_card_$createdCommunityId')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('community_detail_screen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('community_detail_invite_button')));
    await tester.pumpAndSettle();

    await _scrollUntilVisibleInSheet(
      tester,
      sheetKey: const Key('community_detail_invite_sheet'),
      finder:
          find.byKey(const Key('community_detail_invite_contact_priya-rai')),
    );
    await tester.tap(
      find.byKey(const Key('community_detail_invite_action_priya-rai')),
    );
    await tester.pumpAndSettle();

    expect(
      controller.contactById('priya-rai')?.pendingCommunityInviteIds,
      contains(createdCommunityId),
    );
  });

  testWidgets('deletes a community from its detail screen', (tester) async {
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );

    await _pumpCommunitiesScreen(
      tester,
      device: iphoneProProfile,
      controller: controller,
    );
    final targetCommunityId = controller.communities.first.id;

    await _scrollUntilVisible(
      tester,
      find.byKey(Key('community_card_$targetCommunityId')),
    );
    await tester.tap(find.byKey(Key('community_card_$targetCommunityId')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('community_detail_screen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('community_detail_menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('community_detail_delete_menu_item')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Deactivate community?'), findsOneWidget);
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('community_detail_screen')), findsNothing);
    expect(
      controller.communities
          .any((community) => community.id == targetCommunityId),
      isFalse,
    );
  });

  testWidgets('tapping a group preview with a real thread opens a conversation',
      (tester) async {
    final matchedContacts = DemoData.buildCommunityContacts().map((contact) {
      if (contact.id != 'priya-rai') {
        return contact;
      }
      return contact.copyWith(matchedUid: 'priya-rai-uid');
    }).toList(growable: false);

    final chatsController = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
    );
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(
        latency: Duration.zero,
        initialContacts: matchedContacts,
      ),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
      createGroupThread: chatsController.createGroup,
    );

    await _pumpCommunitiesScreen(
      tester,
      device: iphoneProProfile,
      controller: controller,
      chatsController: chatsController,
    );
    final targetCommunityId = controller.communities.first.id;

    final didInvite = await controller.inviteContactToCommunity(
      communityId: targetCommunityId,
      contactId: 'priya-rai',
    );
    expect(didInvite, isTrue);
    await tester.pumpAndSettle();

    await _scrollUntilVisible(
      tester,
      find.byKey(Key('community_card_$targetCommunityId')),
    );
    await tester.tap(find.byKey(Key('community_card_$targetCommunityId')));
    await tester.pumpAndSettle();

    final groupId =
        controller.communityById(targetCommunityId)!.groups.first.id;
    await _scrollUntilVisibleInSheet(
      tester,
      sheetKey: const Key('community_detail_screen'),
      finder: find.byKey(Key('community_detail_group_$groupId')),
    );
    await tester.tap(find.byKey(Key('community_detail_group_$groupId')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('conversation_composer_field')), findsOneWidget);
  });

  // WhatsApp's rule for a community's announcement group: admins post,
  // members read (https://faq.whatsapp.com/582420703681043). The composer is
  // gated on the same thread admin list firestore.rules enforces the
  // message-create gate on -- see ChatThread.currentUserCanSend.
  testWidgets('announcement channel hides the composer from a member',
      (tester) async {
    await _openAnnouncementsThread(tester, viewerIsAdmin: false);

    expect(find.byKey(const Key('conversation_composer_field')), findsNothing);
    expect(find.text('Only admins can send messages'), findsOneWidget);
  });

  testWidgets('announcement channel keeps the composer for an admin',
      (tester) async {
    await _openAnnouncementsThread(tester, viewerIsAdmin: true);

    expect(
        find.byKey(const Key('conversation_composer_field')), findsOneWidget);
    expect(find.text('Only admins can send messages'), findsNothing);
  });

  testWidgets('shows an error card and retries after a failed load',
      (tester) async {
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(
        latency: Duration.zero,
        failFetchOnce: true,
      ),
      permissionService: MemoryAppPermissionService(),
    );

    await _pumpCommunitiesScreen(
      tester,
      device: iphoneSeProfile,
      controller: controller,
    );

    expect(find.byKey(const Key('communities_error_card')), findsOneWidget);
    expect(find.text('Transient communities failure'), findsOneWidget);

    await tester.tap(find.byKey(const Key('communities_retry_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('communities_error_card')), findsNothing);
    expect(find.text('Communities'), findsWidgets);
    expect(controller.communities, isNotEmpty);
  });

  testWidgets(
      'community detail invite sheet finds off-app contacts and shares invite',
      (tester) async {
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );

    await _pumpCommunitiesScreen(
      tester,
      device: iphoneSeProfile,
      controller: controller,
    );

    await _openCommunityDetail(tester, communityId: 'studio-community');

    await tester.tap(find.byKey(const Key('community_detail_invite_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('community_detail_invite_search_field')),
      'Emi',
    );
    await tester.pumpAndSettle();

    expect(find.text('Search results'), findsOneWidget);
    expect(
      find.byKey(const Key('community_detail_invite_contact_emi-tanaka')),
      findsOneWidget,
    );

    await _scrollUntilVisibleInSheet(
      tester,
      sheetKey: const Key('community_detail_invite_sheet'),
      finder:
          find.byKey(const Key('community_detail_invite_action_emi-tanaka')),
    );
    await tester.tap(
      find.byKey(const Key('community_detail_invite_action_emi-tanaka')),
    );
    await tester.pumpAndSettle();

    expect(controller.contactById('emi-tanaka')?.appInviteSent, isTrue);
    expect(find.text('Invite sent'), findsOneWidget);
  });

  testWidgets(
      'community detail invite sheet surfaces share invite failures cleanly',
      (tester) async {
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(
        latency: Duration.zero,
        failShareInviteNext: true,
      ),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );

    await _pumpCommunitiesScreen(
      tester,
      device: androidSmallProfile,
      controller: controller,
    );

    await _openCommunityDetail(tester, communityId: 'studio-community');

    await tester.tap(find.byKey(const Key('community_detail_invite_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('community_detail_invite_search_field')),
      'Emi',
    );
    await tester.pumpAndSettle();

    await _scrollUntilVisibleInSheet(
      tester,
      sheetKey: const Key('community_detail_invite_sheet'),
      finder:
          find.byKey(const Key('community_detail_invite_action_emi-tanaka')),
    );
    await tester.tap(
      find.byKey(const Key('community_detail_invite_action_emi-tanaka')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('We could not prepare that invite link right now.'),
      findsOneWidget,
    );
    expect(controller.contactById('emi-tanaka')?.appInviteSent, isFalse);
    expect(find.text('Share app'), findsOneWidget);
  });
}

/// Opens the studio community's announcements channel with the viewer as an
/// admin of that thread, or as a plain member.
Future<void> _openAnnouncementsThread(
  WidgetTester tester, {
  required bool viewerIsAdmin,
}) async {
  await _pumpCommunitiesScreen(
    tester,
    device: iphoneProProfile,
    controller: CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    ),
    chatsController: ChatsController(
      repository: FakeChatRepository(
        latency: Duration.zero,
        initialThreads: _demoThreadsWithAnnouncementAdmin(viewerIsAdmin),
      ),
    ),
  );

  await _openCommunityDetail(tester, communityId: 'studio-community');
  await tester.tap(
    find.byKey(const Key('community_detail_announcements_row')),
  );
  await tester.pumpAndSettle();
}

/// The demo chat threads with the studio community's announcements channel
/// re-pointed at an admin who is, or isn't, the viewer.
List<ChatThread> _demoThreadsWithAnnouncementAdmin(bool viewerIsAdmin) {
  return DemoData.buildChatThreads().map((thread) {
    if (thread.id != 'studio-community-announcements') {
      return thread;
    }
    return thread.copyWith(
      participants: thread.participants!
          .map((p) => p.isSelf ? p.copyWith(isAdmin: viewerIsAdmin) : p)
          .toList(),
    );
  }).toList();
}

Future<void> _pumpCommunitiesScreen(
  WidgetTester tester, {
  required TestDeviceProfile device,
  required CommunitiesController controller,
  ChatsController? chatsController,
}) async {
  await tester.binding.setSurfaceSize(device.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // Communities reads its unread badges and opens its threads through the
  // chats controller, so it has to be loaded here the way the real app
  // loads it -- without this, every community thread resolves to null and
  // a conversation opened from here renders no composer at all.
  final chats = chatsController ??
      ChatsController(repository: FakeChatRepository(latency: Duration.zero));
  await chats.loadThreads();

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: Scaffold(
        body: CommunitiesScreen(
          controller: controller,
          chatsController: chats,
          callsController: CallsController(
            repository: FakeCallsRepository(latency: Duration.zero),
            permissionService: MemoryAppPermissionService(),
            durationTickInterval: Duration.zero,
          ),
          updatesController: UpdatesController(
            repository: FakeUpdatesRepository(latency: Duration.zero),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(
    tester.takeException(),
    isNull,
    reason:
        '${device.name} should render the communities experience without framework exceptions.',
  );
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: find.byKey(const Key('communities_screen')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: scrollable,
  );
  await tester.pumpAndSettle();
}

Future<void> _openCommunityDetail(
  WidgetTester tester, {
  required String communityId,
}) async {
  await _scrollUntilVisible(
    tester,
    find.byKey(Key('community_card_$communityId')),
  );
  await tester.tap(find.byKey(Key('community_card_$communityId')));
  await tester.pumpAndSettle();

  expect(find.byKey(const Key('community_detail_screen')), findsOneWidget);
}

Future<void> _scrollUntilVisibleInSheet(
  WidgetTester tester, {
  required Key sheetKey,
  required Finder finder,
}) async {
  final scrollable = find
      .descendant(
        of: find.byKey(sheetKey),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: scrollable,
  );
  await tester.pumpAndSettle();
}
