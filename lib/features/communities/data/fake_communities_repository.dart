import 'dart:async';

import '../../../core/sample/demo_data.dart';
import '../domain/community_contact.dart';
import '../domain/community_group_preview.dart';
import '../domain/community_hub.dart';
import 'communities_overview.dart';
import 'communities_repository.dart';

class FakeCommunitiesRepository implements CommunitiesRepository {
  FakeCommunitiesRepository({
    List<CommunityHub>? initialCommunities,
    List<CommunityContact>? initialContacts,
    this.latency = const Duration(milliseconds: 180),
    this.failFetchOnce = false,
    this.failCreateNext = false,
    this.failInviteNext = false,
    this.failShareInviteNext = false,
  })  : _communities = _cloneCommunities(
          initialCommunities ?? DemoData.buildCommunities(),
        ),
        _contacts = _cloneContacts(
          initialContacts ?? DemoData.buildCommunityContacts(),
        );

  final Duration latency;
  bool failFetchOnce;
  bool failCreateNext;
  bool failInviteNext;
  bool failShareInviteNext;

  List<CommunityHub> _communities;
  List<CommunityContact> _contacts;
  final Set<String> _deactivatedCommunityIds = <String>{};
  int _createdCommunitySequence = 0;

  Future<void> _wait() {
    if (latency == Duration.zero) {
      return Future<void>.value();
    }
    return Future<void>.delayed(latency);
  }

  @override
  Future<CommunitiesOverview> fetchOverview() async {
    await _wait();
    if (failFetchOnce) {
      failFetchOnce = false;
      throw const CommunitiesRepositoryException(
        'Transient communities failure',
      );
    }

    return _buildOverview();
  }

  @override
  Future<CommunitiesOverview> createCommunity({
    required String title,
    required String description,
  }) async {
    await _wait();
    if (failCreateNext) {
      failCreateNext = false;
      throw const CommunitiesRepositoryException(
        'We could not create that community right now.',
      );
    }

    final normalizedTitle = title.trim();
    final normalizedDescription = description.trim();
    if (normalizedTitle.isEmpty) {
      throw const CommunitiesRepositoryException(
        'Add a community name before creating it.',
      );
    }

    final newCommunity = DemoData.buildDraftCommunity(
      id: 'community-${_createdCommunitySequence++}',
      title: normalizedTitle,
      description: normalizedDescription.isEmpty
          ? 'A community for $normalizedTitle'
          : normalizedDescription,
    );
    _communities = List<CommunityHub>.unmodifiable([
      newCommunity,
      ..._communities,
    ]);
    return _buildOverview();
  }

  @override
  Future<CommunitiesOverview> markCommunityOpened(String communityId) async {
    await _wait();
    _communities = List<CommunityHub>.unmodifiable(
      _communities.map((community) {
        if (community.id != communityId) {
          return community;
        }
        return community.copyWith(unreadCount: 0);
      }),
    );
    return _buildOverview();
  }

  @override
  Future<CommunitiesOverview> deactivateCommunity(String communityId) async {
    await _wait();
    // Deactivation is a state change, not a delete (see
    // CommunitiesRepository.deactivateCommunity) -- the community stays in
    // the store and _buildOverview is what keeps it out of every member's
    // list. Modelled that way here rather than dropping it, so the filter
    // is what tests exercise: that filter is the part a hard delete used to
    // get for free.
    _deactivatedCommunityIds.add(communityId);
    return _buildOverview();
  }

  @override
  Future<CommunitiesOverview> exitCommunity(String communityId) async {
    await _wait();
    // The in-memory fake has a single viewer, so leaving a community and
    // dropping it from this viewer's list are the same thing. The role
    // check that stops an admin from exiting instead of deactivating lives
    // in CommunitiesController, so both repositories share it.
    _communities = List<CommunityHub>.unmodifiable(
      _communities.where((community) => community.id != communityId),
    );
    return _buildOverview();
  }

  @override
  Future<CommunitiesOverview> attachGroupThread({
    required String communityId,
    required String groupId,
    required String threadId,
  }) async {
    await _wait();
    _communities = List<CommunityHub>.unmodifiable(
      _communities.map((community) {
        if (community.id != communityId) {
          return community;
        }
        return community.copyWith(
          groups: community.groups.map((group) {
            if (group.id != groupId) {
              return group;
            }
            return group.copyWith(threadId: threadId);
          }).toList(growable: false),
        );
      }),
    );
    return _buildOverview();
  }

  @override
  Future<CommunitiesOverview> attachAnnouncementThread({
    required String communityId,
    required String threadId,
  }) async {
    await _wait();
    _communities = List<CommunityHub>.unmodifiable(
      _communities.map((community) {
        if (community.id != communityId) {
          return community;
        }
        return community.copyWith(announcementThreadId: threadId);
      }),
    );
    return _buildOverview();
  }

  @override
  Future<CommunitiesOverview> inviteContactToCommunity({
    required String communityId,
    required String contactId,
  }) async {
    await _wait();
    if (failInviteNext) {
      failInviteNext = false;
      throw const CommunitiesRepositoryException(
        'We could not send that community invite right now.',
      );
    }

    final contact = _contactById(contactId);
    if (!contact.isOnWhatsWave) {
      throw const CommunitiesRepositoryException(
        'That person needs an app invite before they can join a community.',
      );
    }

    _communityById(communityId);
    final membershipState = contact.membershipStateFor(communityId);
    if (membershipState == CommunityMembershipState.member ||
        membershipState == CommunityMembershipState.invited) {
      return _buildOverview();
    }

    _contacts = List<CommunityContact>.unmodifiable(
      _contacts.map((entry) {
        if (entry.id != contactId) {
          return entry;
        }
        return entry.copyWith(
          pendingCommunityInviteIds: List<String>.unmodifiable([
            ...entry.pendingCommunityInviteIds,
            communityId,
          ]),
        );
      }),
    );
    _communities = List<CommunityHub>.unmodifiable(
      _communities.map((community) {
        if (community.id != communityId) {
          return community;
        }
        return community.copyWith(
          invitedContactIds: List<String>.unmodifiable([
            ...community.invitedContactIds,
            contactId,
          ]),
          // This store has no member roster to count, so the header count has
          // to move with the invite -- otherwise it stays frozen at its
          // create-time value while members join, which is the "3 members"
          // over a 2-person list bug on the Firestore side.
          memberCount: community.memberCount + 1,
        );
      }),
    );
    return _buildOverview();
  }

  @override
  Future<CommunitiesOverview> shareAppInvite(String contactId) async {
    await _wait();
    if (failShareInviteNext) {
      failShareInviteNext = false;
      throw const CommunitiesRepositoryException(
        'We could not prepare that invite link right now.',
      );
    }

    final contact = _contactById(contactId);
    if (contact.isOnWhatsWave) {
      return _buildOverview();
    }

    _contacts = List<CommunityContact>.unmodifiable(
      _contacts.map((entry) {
        if (entry.id != contactId) {
          return entry;
        }
        return entry.copyWith(appInviteSent: true);
      }),
    );
    return _buildOverview();
  }

  final _deviceContactsChangedController = StreamController<void>.broadcast();

  @override
  Stream<void> watchDeviceContactsChanged() =>
      _deviceContactsChangedController.stream;

  /// Test-only hook to simulate the OS handing back an updated contact list
  /// (e.g. the user edited their limited-contacts selection in Settings) --
  /// call [debugEmitContactsChanged] afterwards to simulate the native
  /// change notification CommunitiesController listens for.
  void debugReplaceContacts(List<CommunityContact> contacts) {
    _contacts = _cloneContacts(contacts);
  }

  void debugEmitContactsChanged() {
    _deviceContactsChangedController.add(null);
  }

  /// Community ids still held by this store, deactivated or not -- lets a
  /// test tell "filtered out of the overview" apart from "deleted".
  List<String> get debugCommunityIdsInStore =>
      _communities.map((community) => community.id).toList(growable: false);

  CommunitiesOverview _buildOverview() {
    return CommunitiesOverview(
      communities: _cloneCommunities(
        _communities
            .where(
              (community) =>
                  !_deactivatedCommunityIds.contains(community.id),
            )
            .toList(growable: false),
      ),
      contacts: _cloneContacts(_contacts),
    );
  }

  CommunityHub _communityById(String communityId) {
    for (final community in _communities) {
      if (community.id == communityId) {
        return community;
      }
    }
    throw const CommunitiesRepositoryException(
      'That community is no longer available. Pull to refresh and try again.',
    );
  }

  CommunityContact _contactById(String contactId) {
    for (final contact in _contacts) {
      if (contact.id == contactId) {
        return contact;
      }
    }
    throw const CommunitiesRepositoryException(
      'That contact is no longer available. Pull to refresh and try again.',
    );
  }

  static List<CommunityHub> _cloneCommunities(List<CommunityHub> communities) {
    return List<CommunityHub>.unmodifiable(
      communities.map((community) {
        return community.copyWith(
          announcement: community.announcement.copyWith(),
          groups: List<CommunityGroupPreview>.unmodifiable(
            community.groups.map((group) => group.copyWith()),
          ),
          invitedContactIds:
              List<String>.unmodifiable(community.invitedContactIds),
        );
      }),
    );
  }

  static List<CommunityContact> _cloneContacts(
      List<CommunityContact> contacts) {
    return List<CommunityContact>.unmodifiable(
      contacts.map((contact) {
        return contact.copyWith(
          memberCommunityIds:
              List<String>.unmodifiable(contact.memberCommunityIds),
          pendingCommunityInviteIds:
              List<String>.unmodifiable(contact.pendingCommunityInviteIds),
        );
      }),
    );
  }
}
