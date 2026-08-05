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
    if (normalizedTitle.isEmpty || normalizedDescription.isEmpty) {
      throw const CommunitiesRepositoryException(
        'Add a name and a short description before creating a community.',
      );
    }

    final newCommunity = DemoData.buildDraftCommunity(
      id: 'community-${_createdCommunitySequence++}',
      title: normalizedTitle,
      description: normalizedDescription,
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

  /// Test-only hook to simulate the OS handing back an updated contact list
  /// (e.g. the user edited their limited-contacts selection in Settings) --
  /// there's no real "contacts changed" event to listen for, only a fresh
  /// fetchOverview() after the app resumes (see NewChatScreen).
  void debugReplaceContacts(List<CommunityContact> contacts) {
    _contacts = _cloneContacts(contacts);
  }

  CommunitiesOverview _buildOverview() {
    return CommunitiesOverview(
      communities: _cloneCommunities(_communities),
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
