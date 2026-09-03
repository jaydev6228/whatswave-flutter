import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/community_announcement.dart';
import 'package:whatswave/features/communities/domain/community_hub.dart';

CommunityHub _community({required bool viewerIsAdmin}) {
  return CommunityHub(
    id: 'street',
    title: 'Neighbourhood',
    description: 'Street updates.',
    avatarLabel: 'N',
    accentColor: const Color(0xFF00A884),
    memberCount: 3,
    viewerIsAdmin: viewerIsAdmin,
    ownerUid: 'me',
    viewerUid: 'me',
    memberUids: const ['me', 'ana', 'bob'],
    adminUids: const ['me'],
    announcement: CommunityAnnouncement(
      headline: 'Bin day moved',
      body: 'Collections shift to Thursday this week.',
      publishedAt: DateTime(2026, 1, 1),
    ),
    groups: const [],
  );
}

void main() {
  test('displayMemberCount matches the roster length', () {
    final community = _community(viewerIsAdmin: true);
    expect(community.displayMemberCount, 3);
    expect(community.memberUids, hasLength(3));
  });

  test('an admin adds a new group to the community', () async {
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(
        latency: Duration.zero,
        initialCommunities: [_community(viewerIsAdmin: true)],
      ),
      permissionService: MemoryAppPermissionService(),
    );
    await controller.loadOverview();

    final didAdd = await controller.addGroupToCommunity(
      communityId: 'street',
      name: 'Events',
    );

    expect(didAdd, isTrue);
    expect(controller.communityById('street')!.groups, hasLength(1));
    expect(controller.communityById('street')!.groups.first.name, 'Events');
  });
}
