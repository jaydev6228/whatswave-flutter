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

  int get groupCount => groups.length;

  bool get hasUnread => unreadCount > 0;

  bool get hasFreshAnnouncement =>
      DateTime.now().difference(announcement.publishedAt) <=
      const Duration(days: 1);

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
    );
  }
}
