import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/community_announcement.dart';
import 'package:whatswave/features/communities/domain/community_group_preview.dart';
import 'package:whatswave/features/communities/domain/community_hub.dart';

CommunityHub _community({
  required bool viewerIsAdmin,
  String ownerUid = 'me',
  String viewerUid = 'me',
  List<String> memberUids = const ['me', 'ana'],
  List<String> adminUids = const ['me'],
  List<CommunityGroupPreview> groups = const [],
}) {
  return CommunityHub(
    id: 'street',
    title: 'Neighbourhood',
    description: 'Street updates.',
    avatarLabel: 'N',
    accentColor: const Color(0xFF00A884),
    memberCount: memberUids.where((uid) => uid != viewerUid).length,
    viewerIsAdmin: viewerIsAdmin,
    ownerUid: ownerUid,
    viewerUid: viewerUid,
    memberUids: memberUids,
    adminUids: adminUids,
    announcement: CommunityAnnouncement(
      headline: 'Bin day moved',
      body: 'Collections shift to Thursday this week.',
      publishedAt: DateTime(2026, 1, 1),
    ),
    groups: groups,
  );
}

CommunitiesController _controllerFor(CommunityHub community) {
  return CommunitiesController(
    repository: FakeCommunitiesRepository(
      latency: Duration.zero,
      initialCommunities: [community],
    ),
    permissionService: MemoryAppPermissionService(),
  );
}

void main() {
  test('an admin removes a member from the community roster', () async {
    final controller = _controllerFor(
      _community(viewerIsAdmin: true),
    );
    await controller.loadOverview();

    final didRemove = await controller.removeCommunityMember(
      communityId: 'street',
      memberUid: 'ana',
    );

    expect(didRemove, isTrue);
    expect(controller.communityById('street')!.memberUids, ['me']);
  });

  test('a non-admin cannot remove members', () async {
    final controller = _controllerFor(
      _community(
        viewerIsAdmin: false,
        adminUids: const ['someone'],
        memberUids: const ['me', 'ana'],
      ),
    );
    await controller.loadOverview();

    final didRemove = await controller.removeCommunityMember(
      communityId: 'street',
      memberUid: 'ana',
    );

    expect(didRemove, isFalse);
    expect(controller.errorMessage, contains('Only community admins'));
  });

  test('an admin cannot remove the community creator', () async {
    final controller = _controllerFor(
      _community(
        viewerIsAdmin: true,
        ownerUid: 'ana',
        viewerUid: 'me',
        memberUids: const ['me', 'ana'],
        adminUids: const ['me', 'ana'],
      ),
    );
    await controller.loadOverview();

    final didRemove = await controller.removeCommunityMember(
      communityId: 'street',
      memberUid: 'ana',
    );

    expect(didRemove, isFalse);
    expect(controller.errorMessage, contains('cannot be removed'));
  });

  test('an admin detaches a group from the community', () async {
    final controller = _controllerFor(
      _community(
        viewerIsAdmin: true,
        groups: [
          CommunityGroupPreview(
            id: 'general',
            name: 'General',
            summary: 'Hello',
            memberCount: 2,
            lastActivityAt: DateTime(2026, 1, 1),
            threadId: 'thread-general',
          ),
        ],
      ),
    );
    await controller.loadOverview();

    final didDetach = await controller.detachGroupFromCommunity(
      communityId: 'street',
      groupId: 'general',
    );

    expect(didDetach, isTrue);
    expect(controller.communityById('street')!.groups, isEmpty);
  });
}
