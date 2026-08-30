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
    this.likedSegmentIds = const <String>[],
    this.viewedSegmentIds = const <String>[],
    this.seenSegments = 0,
  });

  final String uid;
  final String name;
  final String avatarLabel;
  final Color accentColor;
  final String? avatarUrl;

  /// Null if the backend hasn't recorded a timestamp for this view (older
  /// data written before this field existed).
  final DateTime? viewedAt;

  /// Segment ids this viewer hearted -- likes are per status item, not for
  /// the whole story ring.
  final List<String> likedSegmentIds;

  /// Segment ids this viewer actually watched.
  ///
  /// Views are per status item, so they are recorded by id -- the same way
  /// likes are. A plain count could not distinguish items: it was read as
  /// "has seen at least N segments", so anyone who watched a story that
  /// has since been deleted still counted toward the first segment of the
  /// next one, and a brand-new status opened showing views it never had.
  final List<String> viewedSegmentIds;

  /// How many segments this viewer has watched through.
  ///
  /// Retained for the story-ring seen/unseen state. Deliberately *not*
  /// used to decide per-segment view totals -- see [viewedSegmentIds].
  final int seenSegments;

  bool likedSegment(String segmentId) => likedSegmentIds.contains(segmentId);

  bool viewedSegment(String segmentId) => viewedSegmentIds.contains(segmentId);
}
