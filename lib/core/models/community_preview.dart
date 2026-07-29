import 'package:flutter/material.dart';

class CommunityPreview {
  const CommunityPreview({
    required this.title,
    required this.summary,
    required this.groupsLabel,
    required this.avatarLabel,
    required this.accentColor,
    this.unreadCount = 0,
  });

  final String title;
  final String summary;
  final String groupsLabel;
  final String avatarLabel;
  final Color accentColor;
  final int unreadCount;
}
