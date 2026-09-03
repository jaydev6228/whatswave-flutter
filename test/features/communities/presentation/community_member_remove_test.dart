import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/communities_overview.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/presentation/community_detail_screen.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

class _RoleForcedRepository extends FakeCommunitiesRepository {
  _RoleForcedRepository({required this.viewerIsAdmin})
      : super(latency: Duration.zero);

  final bool viewerIsAdmin;

  @override
  Future<CommunitiesOverview> fetchOverview() async {
    final overview = await super.fetchOverview();
    return CommunitiesOverview(
      communities: [
        for (final community in overview.communities)
          community.copyWith(
            viewerIsAdmin: viewerIsAdmin,
            adminUids: viewerIsAdmin ? community.adminUids : const ['someone'],
          ),
      ],
      contacts: overview.contacts,
    );
  }
}

Future<CommunitiesController> _openDetail(WidgetTester tester) async {
  final controller = CommunitiesController(
    repository: _RoleForcedRepository(viewerIsAdmin: true),
  );
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
  return controller;
}

Future<void> _openCommunityInfo(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('community_detail_title_button')));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('community_info_screen')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an admin removes a member from the roster sheet', (tester) async {
    final controller = await _openDetail(tester);
    final communityId = controller.communities.first.id;

    await _openCommunityInfo(tester);

    final noahRow = find.byKey(
      const Key('community_detail_member_row_uid-noah-kim'),
    );
    await _scrollTo(tester, noahRow);

    await tester.tap(noahRow);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('community_detail_member_remove')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm_remove_community_member_button')),
    );
    await tester.pumpAndSettle();

    expect(
      controller.communityById(communityId)!.memberUids,
      isNot(contains('uid-noah-kim')),
    );
  });
}
