import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';

void main() {
  test('creates a new community and places it at the top of the list',
      () async {
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
    );

    await controller.loadOverview();
    final originalCount = controller.communities.length;

    final didCreate = await controller.createCommunity(
      title: 'Japan Food Club',
      description: 'Restaurant planning, bookings, and photo drops.',
    );

    expect(didCreate, isTrue);
    expect(controller.communities.length, originalCount + 1);
    expect(controller.communities.first.title, 'Japan Food Club');
  });

  test('invites an on-app contact into a community', () async {
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
    );

    await controller.loadOverview();
    final community = controller.communities.first;
    final contact = controller.contactById('priya-rai')!;

    final didInvite = await controller.inviteContactToCommunity(
      communityId: community.id,
      contactId: contact.id,
    );

    expect(didInvite, isTrue);
    expect(
      controller.contactById(contact.id)?.pendingCommunityInviteIds,
      contains(community.id),
    );
    expect(
      controller.communityById(community.id)?.invitedContactIds,
      contains(contact.id),
    );
  });

  test('shares an app invite for an off-app contact', () async {
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
    );

    await controller.loadOverview();

    final didShare = await controller.shareAppInvite('emi-tanaka');

    expect(didShare, isTrue);
    expect(controller.contactById('emi-tanaka')?.appInviteSent, isTrue);
  });

  test('surfaces a transient load failure and succeeds on retry', () async {
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(
        latency: Duration.zero,
        failFetchOnce: true,
      ),
      permissionService: MemoryAppPermissionService(),
    );

    await controller.loadOverview();

    expect(controller.hasLoaded, isFalse);
    expect(controller.errorMessage, 'Transient communities failure');

    await controller.loadOverview();

    expect(controller.hasLoaded, isTrue);
    expect(controller.errorMessage, isNull);
    expect(controller.communities, isNotEmpty);
    expect(controller.contacts, isNotEmpty);
  });
}
