import 'communities_overview.dart';

abstract class CommunitiesRepository {
  Future<CommunitiesOverview> fetchOverview();

  Future<CommunitiesOverview> createCommunity({
    required String title,
    required String description,
  });

  Future<CommunitiesOverview> markCommunityOpened(String communityId);

  /// Deactivates [communityId]: it disappears from every member's list,
  /// its member groups carry on as ordinary group chats, and the
  /// announcement group closes.
  ///
  /// WhatsApp's deactivation disconnects a community's groups rather than
  /// destroying them -- the groups survive and stay usable, only the
  /// community and its announcement group go
  /// (https://faq.whatsapp.com/785738926054798). It cannot be undone.
  /// This used to be a hard delete of the community document, which took
  /// the group roster with it and stranded the groups' chat threads:
  /// they survived in the backend but were reachable from nowhere, since
  /// ChatsController filters community-backed threads out of the Chats tab
  /// and the community that linked them no longer existed.
  Future<CommunitiesOverview> deactivateCommunity(String communityId);

  /// Removes the signed-in user from [communityId], leaving it standing for
  /// everyone else.
  ///
  /// WhatsApp gives every member an unconditional way out of a community
  /// that is separate from an admin deactivating it -- exiting takes you
  /// out of the community and its announcement group while the community
  /// itself carries on
  /// (https://faq.whatsapp.com/1312647189536807). Without this a member
  /// added by an admin has no exit at all, since only the owner can write
  /// the community document.
  Future<CommunitiesOverview> exitCommunity(String communityId);

  /// Records which real [ChatThread] backs a community group's messaging,
  /// once one has been created (see CommunitiesController).
  Future<CommunitiesOverview> attachGroupThread({
    required String communityId,
    required String groupId,
    required String threadId,
  });

  Future<CommunitiesOverview> attachAnnouncementThread({
    required String communityId,
    required String threadId,
  });

  Future<CommunitiesOverview> inviteContactToCommunity({
    required String communityId,
    required String contactId,
  });

  Future<CommunitiesOverview> shareAppInvite(String contactId);

  /// Fires when the device's contacts database changes underneath the app
  /// (see DeviceContactsService.watchContactsChanged) -- null for
  /// implementations with no real device-contacts backing.
  Stream<void>? watchDeviceContactsChanged();
}

class CommunitiesRepositoryException implements Exception {
  const CommunitiesRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
