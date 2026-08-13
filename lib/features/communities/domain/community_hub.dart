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
  });

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
    );
  }
}
