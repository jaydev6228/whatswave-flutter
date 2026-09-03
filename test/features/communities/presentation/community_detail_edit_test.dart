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

void main() {
  testWidgets('admins see Edit and can save a renamed community',
      (tester) async {
    final controller = await _openDetail(tester, viewerIsAdmin: true);

    expect(find.byKey(const Key('community_detail_edit_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('community_detail_edit_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('community_detail_rename_field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('community_detail_description_field')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('community_detail_rename_field')),
      'New name',
    );
    await tester.tap(find.byKey(const Key('community_detail_save_button')));
    await tester.pumpAndSettle();

    expect(controller.communityById(controller.communities.first.id)!.title,
        'New name');
    expect(find.text('New name'), findsWidgets);
  });

  testWidgets('members do not see the Edit affordance', (tester) async {
    await _openDetail(tester, viewerIsAdmin: false);

    expect(find.byKey(const Key('community_detail_edit_button')), findsNothing);
  });
}
