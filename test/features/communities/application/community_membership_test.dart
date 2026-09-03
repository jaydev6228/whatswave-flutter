import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/community_announcement.dart';
import 'package:whatswave/features/communities/domain/community_hub.dart';

/// Covers the admin-versus-member split WhatsApp draws around a community:
/// only admins deactivate one (https://faq.whatsapp.com/785738926054798),
/// and every member can exit one at any time
/// (https://faq.whatsapp.com/1312647189536807).
CommunityHub _community({required String id, required bool viewerIsAdmin}) {
  return CommunityHub(
    id: id,
    title: 'Neighbourhood $id',
    description: 'Street updates.',
    avatarLabel: 'N',
    accentColor: const Color(0xFF00A884),
    memberCount: 4,
    viewerIsAdmin: viewerIsAdmin,
    announcement: CommunityAnnouncement(
      headline: 'Bin day moved',
      body: 'Collections shift to Thursday this week.',
      publishedAt: DateTime(2026, 1, 1),
    ),
    groups: const [],
  );
}

CommunitiesController _controllerFor(List<CommunityHub> communities) {
  return CommunitiesController(
    repository: FakeCommunitiesRepository(
      latency: Duration.zero,
      initialCommunities: communities,
      initialContacts: DemoData.buildCommunityContacts(),
    ),
    permissionService: MemoryAppPermissionService(),
  );
}

void main() {
  test('a member can exit a community, which drops it from their list',
      () async {
    final controller = _controllerFor([
      _community(id: 'theirs', viewerIsAdmin: false),
      _community(id: 'mine', viewerIsAdmin: true),
    ]);
    await controller.loadOverview();

    final didExit = await controller.exitCommunity('theirs');

    expect(didExit, isTrue);
    expect(controller.errorMessage, isNull);
    expect(
      controller.communities.map((community) => community.id),
      ['mine'],
    );
  });

  test('a member cannot delete a community they do not admin', () async {
    final controller = _controllerFor([
      _community(id: 'theirs', viewerIsAdmin: false),
    ]);
    await controller.loadOverview();

    final didDelete = await controller.deactivateCommunity('theirs');

    expect(didDelete, isFalse);
    expect(controller.errorMessage, contains('Only community admins'));
    expect(controller.communities.map((community) => community.id), ['theirs']);
  });

  test('an admin deletes their own community instead of exiting it', () async {
    final controller = _controllerFor([
      _community(id: 'mine', viewerIsAdmin: true),
    ]);
    await controller.loadOverview();

    final didExit = await controller.exitCommunity('mine');
    expect(didExit, isFalse);
    expect(controller.errorMessage, contains('Delete it instead'));
    expect(controller.communities, hasLength(1));

    final didDelete = await controller.deactivateCommunity('mine');
    expect(didDelete, isTrue);
    expect(controller.communities, isEmpty);
  });
}
