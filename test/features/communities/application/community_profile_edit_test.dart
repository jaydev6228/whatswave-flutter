import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/community_announcement.dart';
import 'package:whatswave/features/communities/domain/community_hub.dart';

CommunityHub _community({
  required bool viewerIsAdmin,
  String viewerUid = 'me',
}) {
  return CommunityHub(
    id: 'street',
    title: 'Neighbourhood',
    description: 'Street updates.',
    avatarLabel: 'N',
    accentColor: const Color(0xFF00A884),
    memberCount: 1,
    viewerIsAdmin: viewerIsAdmin,
    ownerUid: 'me',
    viewerUid: viewerUid,
    memberUids: const ['me', 'ana'],
    adminUids: viewerIsAdmin ? const ['me'] : const ['someone'],
    announcement: CommunityAnnouncement(
      headline: 'Bin day moved',
      body: 'Collections shift to Thursday this week.',
      publishedAt: DateTime(2026, 1, 1),
    ),
    groups: const [],
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
  test('an admin renames and updates the community description', () async {
    final controller = _controllerFor(
      _community(viewerIsAdmin: true),
    );
    await controller.loadOverview();

    final didRename = await controller.renameCommunity(
      communityId: 'street',
      title: 'Block party',
    );
    expect(didRename, isTrue);
    expect(controller.communityById('street')!.title, 'Block party');
    expect(
      controller.communityById('street')!.avatarLabel,
      'BP',
    );

    final didUpdate = await controller.updateCommunityDescription(
      communityId: 'street',
      description: 'Weekly meetups.',
    );
    expect(didUpdate, isTrue);
    expect(
      controller.communityById('street')!.description,
      'Weekly meetups.',
    );
  });

  test('a non-admin cannot edit the community profile', () async {
    final controller = _controllerFor(
      _community(viewerIsAdmin: false, viewerUid: 'ana'),
    );
    await controller.loadOverview();

    final didRename = await controller.renameCommunity(
      communityId: 'street',
      title: 'Hacked',
    );
    expect(didRename, isFalse);
    expect(controller.errorMessage, contains('Only community admins'));
    expect(controller.communityById('street')!.title, 'Neighbourhood');
  });

  test('an admin can set and remove a community photo', () async {
    final controller = _controllerFor(
      _community(viewerIsAdmin: true),
    );
    await controller.loadOverview();

    final photo = File('test/fixtures/test_photo.png');
    final didUpload = await controller.updateCommunityAvatar(
      communityId: 'street',
      photo: photo,
    );
    expect(didUpload, isTrue);
    expect(controller.communityById('street')!.avatarUrl, photo.path);

    final didRemove = await controller.deleteCommunityAvatar('street');
    expect(didRemove, isTrue);
    expect(controller.communityById('street')!.avatarUrl, isNull);
  });
}
