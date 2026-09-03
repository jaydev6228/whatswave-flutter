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

void main() {
  testWidgets('adding one contact leaves the other rows tappable',
      (tester) async {
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(
        latency: const Duration(milliseconds: 100),
      ),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );
    await tester.runAsync(controller.ensureLoaded);

    await _pumpCommunityDetail(
      tester,
      controller: controller,
      communityId: 'studio-community',
    );

    await tester.tap(find.byKey(const Key('community_detail_invite_button')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('community_detail_invite_action_priya-rai')),
    );
    await tester.pump(const Duration(milliseconds: 10));

    expect(_actionLabel(tester, 'priya-rai'), 'Adding...');
    expect(_actionLabel(tester, 'noah-kim'), 'Add');
    expect(_actionOnPressed(tester, 'noah-kim'), isNotNull);

    await tester.pumpAndSettle();

    expect(_actionLabel(tester, 'priya-rai'), 'Pending');
    expect(_actionLabel(tester, 'noah-kim'), 'Add');
    expect(_actionOnPressed(tester, 'noah-kim'), isNotNull);
  });

  testWidgets('the member count matches the people actually added',
      (tester) async {
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );
    await controller.ensureLoaded();
    await controller.createCommunity(
      title: 'Japan Food Club',
      description: 'Restaurant planning, bookings, and photo drops.',
    );
    final communityId = controller.communities.first.id;

    await _pumpCommunityDetail(
      tester,
      controller: controller,
      communityId: communityId,
    );

    expect(find.text('0 members · 1 groups'), findsOneWidget);

    await tester.tap(find.byKey(const Key('community_detail_invite_button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('community_detail_invite_action_priya-rai')),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 members · 1 groups'), findsOneWidget);
  });
}

Future<void> _pumpCommunityDetail(
  WidgetTester tester, {
  required CommunitiesController controller,
  required String communityId,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      home: CommunityDetailScreen(
        controller: controller,
        chatsController: ChatsController(
          repository: FakeChatRepository(latency: Duration.zero),
        ),
        callsController: CallsController(
          repository: FakeCallsRepository(latency: Duration.zero),
          permissionService: MemoryAppPermissionService(),
          durationTickInterval: Duration.zero,
        ),
        updatesController: UpdatesController(
          repository: FakeUpdatesRepository(latency: Duration.zero),
        ),
        communityId: communityId,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _actionLabel(WidgetTester tester, String contactId) {
  return tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(Key('community_detail_invite_action_$contactId')),
          matching: find.byType(Text),
        ),
      )
      .data!;
}

VoidCallback? _actionOnPressed(WidgetTester tester, String contactId) {
  return tester
      .widget<ButtonStyleButton>(
        find.byKey(Key('community_detail_invite_action_$contactId')),
      )
      .onPressed;
}
