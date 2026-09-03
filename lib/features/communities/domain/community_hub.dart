import 'package:flutter/material.dart';

import 'community_announcement.dart';
import 'community_group_preview.dart';

class CommunityHub {
  const CommunityHub({
    required this.id,
    required this.title,
    required this.description,
    required this.avatarLabel,
    required this.accentColor,
    required this.memberCount,
    required this.announcement,
    required this.groups,
    this.unreadCount = 0,
    this.invitedContactIds = const <String>[],
    this.announcementThreadId,
    this.viewerIsAdmin = false,
    this.memberUids = const <String>[],
    this.adminUids = const <String>[],
    this.ownerUid,
    this.viewerUid,
    this.avatarUrl,
  });

  /// Derives the initials badge from a community title -- same logic as
  /// [DemoData.buildDraftCommunity].
  static String avatarLabelForTitle(String title) {
    return title
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
  }

  /// WhatsApp's cap: "You can assign up to 20 community admin roles."
  /// (https://www.whatsapp.com/communities/learning/settingupyourcommunity).
  /// Enforced in CommunitiesController and again in `firestore.rules`, so a
  /// stale client cannot hand out a 21st.
  static const int maxAdmins = 20;

  final String id;
  final String title;
  final String description;
  final String avatarLabel;
  final Color accentColor;
  final int memberCount;
  final CommunityAnnouncement announcement;
  final List<CommunityGroupPreview> groups;
  final int unreadCount;
  final List<String> invitedContactIds;

  /// Backing [ChatThread] for the read-only announcements channel.
  final String? announcementThreadId;

  /// Whether the signed-in viewer is a community admin rather than a plain
  /// member -- i.e. whether their uid is in [adminUids]. Derived on read
  /// (see FirestoreCommunitiesRepository) rather than computed here,
  /// because fixtures and demo data set the role directly without a uid.
  ///
  /// WhatsApp draws every destructive community action along this line:
  /// only community admins can deactivate a community, and everyone else
  /// exits instead -- see
  /// https://faq.whatsapp.com/785738926054798 (How to deactivate a
  /// community) and https://faq.whatsapp.com/1312647189536807 (How to exit
  /// a community). Defaults to false so a community whose role is unknown
  /// is treated as someone else's.
  final bool viewerIsAdmin;

  /// Everyone in the community, admins included -- this is the read-access
  /// roster on the document, and what the members list renders.
  final List<String> memberUids;

  /// The subset of [memberUids] holding an admin role. Admins can add and
  /// remove members and groups
  /// (https://www.whatsapp.com/communities/learning/settingupyourcommunity);
  /// [ownerUid] is always in here and can never be demoted.
  final List<String> adminUids;

  /// The creator. Kept as its own field because one action still needs a
  /// single un-removable person: deactivation is irreversible, so it stays
  /// with the one role nobody can take away (see
  /// CommunitiesController.deactivateCommunity).
  final String? ownerUid;

  /// The signed-in viewer's uid, so the members list can mark their own row
  /// and refuse self-promotion. Null for fixtures/demo data with no real
  /// account behind them.
  final String? viewerUid;

  /// Remote download URL or local file path (fake backend). When null the
  /// list and detail screens fall back to [avatarLabel].
  final String? avatarUrl;

  /// Whether the viewer created this community. Distinct from
  /// [viewerIsAdmin]: a promoted admin manages members, but only the
  /// creator can deactivate or is barred from exiting.
  bool get viewerIsOwner => ownerUid != null && ownerUid == viewerUid;

  bool get hasMaxAdmins => adminUids.length >= maxAdmins;

  bool isAdminUid(String uid) => adminUids.contains(uid);

  int get groupCount => groups.length;

  bool get hasUnread => unreadCount > 0;

  bool get hasFreshAnnouncement =>
      DateTime.now().difference(announcement.publishedAt) <=
      const Duration(days: 1);

  /// Latest activity preview for the communities list row.
  String get listPreview {
    CommunityGroupPreview? latestGroup;
    for (final group in groups) {
      if (latestGroup == null ||
          group.lastActivityAt.isAfter(latestGroup.lastActivityAt)) {
        latestGroup = group;
      }
    }
    if (latestGroup != null &&
        latestGroup.lastActivityAt.isAfter(announcement.publishedAt)) {
      return latestGroup.summary;
    }
    return announcement.headline;
  }

  DateTime get lastActivityAt {
    var latest = announcement.publishedAt;
    for (final group in groups) {
      if (group.lastActivityAt.isAfter(latest)) {
        latest = group.lastActivityAt;
      }
    }
    return latest;
  }

  CommunityHub copyWith({
    String? id,
    String? title,
    String? description,
    String? avatarLabel,
    Color? accentColor,
    int? memberCount,
    CommunityAnnouncement? announcement,
    List<CommunityGroupPreview>? groups,
    int? unreadCount,
    List<String>? invitedContactIds,
    String? announcementThreadId,
    bool? viewerIsAdmin,
    List<String>? memberUids,
    List<String>? adminUids,
    String? ownerUid,
    String? viewerUid,
    String? avatarUrl,
    bool clearAvatarUrl = false,
  }) {
    return CommunityHub(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      avatarLabel: avatarLabel ?? this.avatarLabel,
      accentColor: accentColor ?? this.accentColor,
      memberCount: memberCount ?? this.memberCount,
      announcement: announcement ?? this.announcement,
      groups: groups ?? this.groups,
      unreadCount: unreadCount ?? this.unreadCount,
      invitedContactIds: invitedContactIds ?? this.invitedContactIds,
      announcementThreadId: announcementThreadId ?? this.announcementThreadId,
      viewerIsAdmin: viewerIsAdmin ?? this.viewerIsAdmin,
      memberUids: memberUids ?? this.memberUids,
      adminUids: adminUids ?? this.adminUids,
      ownerUid: ownerUid ?? this.ownerUid,
      viewerUid: viewerUid ?? this.viewerUid,
      avatarUrl: clearAvatarUrl ? null : avatarUrl ?? this.avatarUrl,
    );
  }
}
