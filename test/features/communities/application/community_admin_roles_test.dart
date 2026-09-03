import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/community_announcement.dart';
import 'package:whatswave/features/communities/domain/community_hub.dart';

/// Communities have real admin roles, not a single owner: "You can assign
/// up to 20 community admin roles."
/// (https://www.whatsapp.com/communities/learning/settingupyourcommunity).
/// Admins can add and remove members and groups, so the roster -- not
/// ownerUid -- is what every admin gate reads. Deactivating stays with the
/// creator, who is also the one admin nobody can demote, which is what keeps
/// a community from ever running out of admins.
CommunityHub _community({
  required List<String> memberUids,
  required List<String> adminUids,
  String ownerUid = 'me',
  String viewerUid = 'me',
}) {
  return CommunityHub(
    id: 'street',
    title: 'Neighbourhood',
    description: 'Street updates.',
    avatarLabel: 'N',
    accentColor: const Color(0xFF00A884),
    memberCount: memberUids.length - 1,
    viewerIsAdmin: adminUids.contains(viewerUid),
    ownerUid: ownerUid,
    viewerUid: viewerUid,
    memberUids: memberUids,
    adminUids: adminUids,
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
      initialContacts: DemoData.buildCommunityContacts(),
    ),
    permissionService: MemoryAppPermissionService(),
  );
}

void main() {
  test('an admin promotes a member, and demotes them again', () async {
    final controller = _controllerFor(
      _community(memberUids: ['me', 'ana'], adminUids: ['me']),
    );
    await controller.loadOverview();

    final didPromote = await controller.setCommunityAdmin(
      communityId: 'street',
      memberUid: 'ana',
      isAdmin: true,
    );

    expect(didPromote, isTrue);
    expect(controller.errorMessage, isNull);
    expect(controller.communityById('street')!.adminUids, ['me', 'ana']);

    final didDemote = await controller.setCommunityAdmin(
      communityId: 'street',
      memberUid: 'ana',
      isAdmin: false,
    );

    expect(didDemote, isTrue);
    expect(controller.communityById('street')!.adminUids, ['me']);
  });

  test('the 20th admin is the last one: a 21st is refused with a reason',
      () async {
    final admins = ['me', for (var i = 1; i < 20; i++) 'admin-$i'];
    final controller = _controllerFor(
      _community(memberUids: [...admins, 'ana'], adminUids: admins),
    );
    await controller.loadOverview();
    expect(admins, hasLength(CommunityHub.maxAdmins));

    final didPromote = await controller.setCommunityAdmin(
      communityId: 'street',
      memberUid: 'ana',
      isAdmin: true,
    );

    expect(didPromote, isFalse);
    expect(controller.errorMessage, contains('already has 20 admins'));
    expect(controller.communityById('street')!.adminUids, admins);
  });

  test('a member who is not an admin cannot promote anyone', () async {
    final controller = _controllerFor(
      _community(
        memberUids: ['owner', 'me', 'ana'],
        adminUids: ['owner'],
        ownerUid: 'owner',
      ),
    );
    await controller.loadOverview();

    final didPromote = await controller.setCommunityAdmin(
      communityId: 'street',
      memberUid: 'ana',
      isAdmin: true,
    );

    expect(didPromote, isFalse);
    expect(controller.errorMessage, contains('Only community admins'));
    expect(controller.communityById('street')!.adminUids, ['owner']);
  });

  test('nobody promotes themselves, and the creator cannot be demoted',
      () async {
    final controller = _controllerFor(
      _community(
        memberUids: ['owner', 'me', 'ana'],
        adminUids: ['owner', 'me'],
        ownerUid: 'owner',
      ),
    );
    await controller.loadOverview();

    final didSelfPromote = await controller.setCommunityAdmin(
      communityId: 'street',
      memberUid: 'me',
      isAdmin: true,
    );
    expect(didSelfPromote, isFalse);
    expect(controller.errorMessage, contains('your own admin role'));

    final didDemoteOwner = await controller.setCommunityAdmin(
      communityId: 'street',
      memberUid: 'owner',
      isAdmin: false,
    );
    expect(didDemoteOwner, isFalse);
    expect(controller.errorMessage, contains('stays an admin'));
    expect(controller.communityById('street')!.adminUids, ['owner', 'me']);
  });

  test('the last admin cannot exit, but any other admin can', () async {
    // The creator is always an admin and is refused the exit path
    // (deactivating is their action instead), so the roster can never empty.
    final soleAdmin = _controllerFor(
      _community(memberUids: ['me', 'ana'], adminUids: ['me']),
    );
    await soleAdmin.loadOverview();

    final ownerDidExit = await soleAdmin.exitCommunity('street');

    expect(ownerDidExit, isFalse);
    expect(soleAdmin.errorMessage, contains('Delete it instead'));
    expect(soleAdmin.communities, hasLength(1));

    // A promoted admin is still a member, and every member keeps a way out
    // (https://faq.whatsapp.com/1312647189536807) -- the creator is left
    // holding the community.
    final promotedAdmin = _controllerFor(
      _community(
        memberUids: ['owner', 'me'],
        adminUids: ['owner', 'me'],
        ownerUid: 'owner',
      ),
    );
    await promotedAdmin.loadOverview();

    final adminDidExit = await promotedAdmin.exitCommunity('street');

    expect(adminDidExit, isTrue);
    expect(promotedAdmin.errorMessage, isNull);
    expect(promotedAdmin.communities, isEmpty);
  });
}
