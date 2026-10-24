import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/contact_access_status.dart';
import 'package:whatswave/features/communities/presentation/community_detail_screen.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

import '../../support/device_matrix.dart';

void main() {
  testWidgets('CommunityDetailScreen survives the layout matrix',
      (tester) async {
    final communities = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );
    await communities.ensureLoaded();
    final communityId = communities.communities.first.id;

    final chats = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
    );
    await chats.ensureLoaded();

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: CommunityDetailScreen(
          controller: communities,
          chatsController: chats,
          callsController: CallsController(
            repository: FakeCallsRepository(latency: Duration.zero),
          ),
          updatesController: UpdatesController(
            repository: FakeUpdatesRepository(latency: Duration.zero),
          ),
          communityId: communityId,
        ),
      ),
    );

    expect(
      find.byKey(const Key('community_detail_screen')),
      findsOneWidget,
      reason: 'the sweep must have rendered the real screen, not the '
          '"Community unavailable" fallback',
    );
  });
}
