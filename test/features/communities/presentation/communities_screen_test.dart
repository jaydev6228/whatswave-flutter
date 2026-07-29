import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/contact_access_status.dart';
import 'package:whatswave/features/communities/presentation/communities_screen.dart';

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
      find.byKey(const Key('community_detail_invite_contact_priya-rai')),
    );
    await tester.pumpAndSettle();

    expect(
      controller.contactById('priya-rai')?.pendingCommunityInviteIds,
      contains(createdCommunityId),
    );
  });

  testWidgets(
      'shows contacts permission gate, allows access, and shares invite',
      (tester) async {
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
    );

    await _pumpCommunitiesScreen(
      tester,
      device: androidSmallProfile,
      controller: controller,
    );

    await tester.tap(find.byKey(const Key('communities_surface_contacts')));
    await tester.pumpAndSettle();

    expect(find.text('Contacts are hidden for now'), findsOneWidget);

    await _scrollUntilVisible(
      tester,
      find.byKey(const Key('contacts_permission_allow')),
    );
    await tester.tap(find.byKey(const Key('contacts_permission_allow')));
    await tester.pumpAndSettle();

    await _scrollUntilVisible(
      tester,
      find.byKey(const Key('contacts_filter_invite')),
    );
    await tester.tap(find.byKey(const Key('contacts_filter_invite')));
    await tester.pumpAndSettle();

    expect(find.text('Emi Tanaka'), findsOneWidget);
    expect(find.text('Ava Patel'), findsNothing);

    await _scrollUntilVisible(
      tester,
      find.byKey(const Key('contact_primary_action_emi-tanaka')),
    );
    await tester
        .tap(find.byKey(const Key('contact_primary_action_emi-tanaka')));
    await tester.pumpAndSettle();

    expect(find.text('Invite Emi Tanaka'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(controller.contactById('emi-tanaka')?.appInviteSent, isTrue);
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

Future<void> _pumpCommunitiesScreen(
  WidgetTester tester, {
  required TestDeviceProfile device,
  required CommunitiesController controller,
}) async {
  await tester.binding.setSurfaceSize(device.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: Scaffold(
        body: CommunitiesScreen(controller: controller),
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
