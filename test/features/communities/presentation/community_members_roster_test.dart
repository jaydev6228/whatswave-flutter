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

/// The members roster is the only place a community member can be promoted
/// from -- before it, the detail screen listed groups and nothing else, so
/// admin roles ("You can assign up to 20 community admin roles.",
/// https://www.whatsapp.com/communities/learning/settingupyourcommunity)
/// had no surface at all.
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

Future<CommunitiesController> _openDetail(
  WidgetTester tester, {
  required bool viewerIsAdmin,
}) async {
  final controller = CommunitiesController(
    repository: _RoleForcedRepository(viewerIsAdmin: viewerIsAdmin),
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

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('community_detail_screen')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an admin sees the roster with badges and promotes a member',
      (tester) async {
    final controller = await _openDetail(tester, viewerIsAdmin: true);
    final communityId = controller.communities.first.id;

    final noahRow = find.byKey(const Key(
      'community_detail_member_row_uid-noah-kim',
    ));
    await _scrollTo(tester, noahRow);

    // The demo community's second admin already wears the badge; the member
    // being promoted does not.
    expect(
      find.byKey(const Key(
        'community_detail_member_admin_badge_uid-ava-patel',
      )),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key(
        'community_detail_member_admin_badge_uid-noah-kim',
      )),
      findsNothing,
    );

    await tester.tap(noahRow);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('community_detail_member_toggle_admin')),
    );
    await tester.pumpAndSettle();

    expect(
      controller.communityById(communityId)!.adminUids,
      contains('uid-noah-kim'),
    );
    expect(
      find.byKey(const Key(
        'community_detail_member_admin_badge_uid-noah-kim',
      )),
      findsOneWidget,
    );
  });

  testWidgets('a plain member sees the roster but cannot open a role sheet',
      (tester) async {
    await _openDetail(tester, viewerIsAdmin: false);

    final noahRow = find.byKey(const Key(
      'community_detail_member_row_uid-noah-kim',
    ));
    await _scrollTo(tester, noahRow);

    await tester.tap(noahRow);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('community_detail_member_toggle_admin')),
      findsNothing,
    );
  });
}
