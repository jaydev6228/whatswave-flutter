import 'dart:io';

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
  /// the community document. Exiting drops the uid from the admin roster
  /// too, so a departed admin leaves no ghost role behind holding one of
  /// the 20 slots. The creator cannot exit at all (they deactivate
  /// instead), and the creator is always an admin, so a community can never
  /// be left with no admin.
  Future<CommunitiesOverview> exitCommunity(String communityId);

  /// Grants or revokes an admin role for [memberUid].
  ///
  /// WhatsApp communities have real admin roles, capped: "You can assign up
  /// to 20 community admin roles."
  /// (https://www.whatsapp.com/communities/learning/settingupyourcommunity).
  /// The cap, the admin-only gate, and the rules that the owner can never be
  /// demoted and nobody can promote themselves live in
  /// CommunitiesController so both repositories share them; `firestore.rules`
  /// enforces the same three server-side.
  Future<CommunitiesOverview> setCommunityAdmin({
    required String communityId,
    required String memberUid,
    required bool isAdmin,
  });

  /// Renames [communityId]. Also refreshes the stored initials badge.
  Future<CommunitiesOverview> renameCommunity({
    required String communityId,
    required String title,
  });

  Future<CommunitiesOverview> updateCommunityDescription({
    required String communityId,
    required String description,
  });

  Future<CommunitiesOverview> updateCommunityAvatar({
    required String communityId,
    required File photo,
  });

  Future<CommunitiesOverview> deleteCommunityAvatar(String communityId);

  /// Drops [memberUid] from [communityId]. Admin-only; never the owner,
  /// and never the caller (they [exitCommunity] instead).
  ///
  /// WhatsApp removes that person from the community and its announcement
  /// group, and leaves them in any other groups they were already in
  /// (https://faq.whatsapp.com/2052820105033683).
  Future<CommunitiesOverview> removeCommunityMember({
    required String communityId,
    required String memberUid,
  });

  /// Disconnects [groupId] from [communityId]. The backing chat, if any,
  /// becomes an ordinary group -- the same release deactivation uses.
  Future<CommunitiesOverview> detachGroupFromCommunity({
    required String communityId,
    required String groupId,
  });

  /// Adds a new member group to [communityId]. Admin-only.
  Future<CommunitiesOverview> addGroupToCommunity({
    required String communityId,
    required String name,
  });

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
