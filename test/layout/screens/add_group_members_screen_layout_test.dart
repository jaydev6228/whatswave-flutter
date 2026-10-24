import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/presentation/add_group_members_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/contact_access_status.dart';

import '../../support/device_matrix.dart';

void main() {
  testWidgets('AddGroupMembersScreen survives the layout matrix',
      (tester) async {
    final chats = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
    );
    await chats.ensureLoaded();
    // Sample data's group thread, so the eligible-contact filter runs
    // against a real participant list rather than an empty one.
    final thread = chats.threadById('design-sprint')!;

    final communities = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );
    await communities.ensureLoaded();
    // Without contacts the screen renders an EmptyStateCard and the member
    // rows -- the part most likely to overflow -- never lay out at all, so
    // the sweep below would pass without having tested anything.
    expect(communities.onWhatsWaveContacts, isNotEmpty);

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: AddGroupMembersScreen(
          communitiesController: communities,
          thread: thread,
        ),
      ),
    );

    expect(
      find.byKey(const Key('add_group_members_screen')),
      findsOneWidget,
      reason: 'the sweep must have rendered the real screen',
    );
  });
}
