import 'package:flutter/material.dart';

/// One person who has viewed a [StatusStory] you own -- backs the "N
/// views" screen (tap the view count on your own story), matching
/// WhatsApp's own per-viewer list rather than just a bare count.
class StoryViewer {
  const StoryViewer({
    required this.uid,
    required this.name,
    required this.avatarLabel,
    required this.accentColor,
    this.avatarUrl,
    this.viewedAt,
  });

  final String uid;
  final String name;
  final String avatarLabel;
  final Color accentColor;
  final String? avatarUrl;

  /// Null if the backend hasn't recorded a timestamp for this view (older
  /// data written before this field existed).
  final DateTime? viewedAt;
}
