import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/data/communities_overview.dart';
import 'package:whatswave/features/communities/presentation/community_detail_screen.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

/// Serves the demo communities with the viewer's role forced. Deactivation
/// is the creator's action, so the forced role has to move ownerUid too --
/// an admin who did not create the community is offered exit like anyone
/// else.
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
            ownerUid: viewerIsAdmin ? 'me' : 'someone-else',
          ),
      ],
      contacts: overview.contacts,
    );
  }
}

Future<void> _openDetail(
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
  await tester.tap(find.byKey(const Key('community_detail_menu_button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an admin is offered Delete community', (tester) async {
    await _openDetail(tester, viewerIsAdmin: true);

    expect(
      find.byKey(const Key('community_detail_delete_menu_item')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('community_detail_exit_menu_item')),
      findsNothing,
    );
  });

  testWidgets('a member is offered Exit community, not Delete',
      (tester) async {
    // Both used to read "Delete community", so a member tapped a
    // destructive item the security rules then refused -- and what they
    // actually wanted, leaving, was never on offer.
    await _openDetail(tester, viewerIsAdmin: false);

    expect(
      find.byKey(const Key('community_detail_exit_menu_item')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('community_detail_delete_menu_item')),
      findsNothing,
    );
  });
}
