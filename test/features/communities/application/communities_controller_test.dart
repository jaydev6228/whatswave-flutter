import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/community_contact.dart';

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

  test('deletes a community from the list', () async {
    final controller = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
    );

    await controller.loadOverview();
    final originalCount = controller.communities.length;
    expect(originalCount, greaterThan(0));
    final communityToDelete = controller.communities.first;

    final didDelete = await controller.deleteCommunity(communityToDelete.id);

    expect(didDelete, isTrue);
    expect(controller.communities.length, originalCount - 1);
    expect(
      controller.communities
          .any((community) => community.id == communityToDelete.id),
      isFalse,
    );
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

  test(
      'refreshes contacts when the device reports its contacts database changed',
      () async {
    final repository = FakeCommunitiesRepository(latency: Duration.zero);
    final controller = CommunitiesController(
      repository: repository,
      permissionService: MemoryAppPermissionService(),
    );

    await controller.loadOverview();
    final originalContactCount = controller.contacts.length;

    repository.debugReplaceContacts(const [
      CommunityContact(
        id: 'new-device-contact',
        name: 'New Person',
        phoneNumber: '+1 555 0100',
        avatarLabel: 'NP',
        accentColor: Color(0xFF123456),
        about: 'Just added from Settings.',
      ),
    ]);
    // loadOverview() alone doesn't yet reflect the repository mutation --
    // only the device-contacts-changed stream (or another loadOverview
    // call) does, confirming the refresh really came from the
    // subscription rather than some other path.
    expect(controller.contacts.length, originalContactCount);

    repository.debugEmitContactsChanged();
    await Future<void>.delayed(Duration.zero);

    expect(controller.contacts.length, 1);
    expect(controller.contacts.first.name, 'New Person');
  });
}
