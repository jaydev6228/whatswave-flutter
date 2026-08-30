import '../../../core/models/status_story.dart';

/// Attached to a [ChatMessage] sent from the story viewer's reply bar --
/// a small snapshot of what was being replied to (WhatsApp calls this a
/// "status reply"), so the chat can render a tappable thumbnail card above
/// the reply text without needing a live read of the story.
///
/// [mediaUrl]/[previewText]/[accentColorArgb] are a point-in-time snapshot
/// captured when the reply was sent, not a live reference.
///
/// Tapping the card opens the exact status item that was replied to, found
/// by [segmentId]. Once that item is deleted or expires the card becomes a
/// non-tappable placeholder -- it does *not* fall through to whatever the
/// owner has posted since. Resolving by owner alone meant a reply to a
/// long-gone status opened an unrelated new one.
class StoryReplyContext {
  const StoryReplyContext({
    required this.storyOwnerUid,
    required this.storyOwnerName,
    required this.segmentType,
    this.segmentId,
    this.previewText,
    this.mediaUrl,
    this.accentColorArgb,
  });

  final String storyOwnerUid;
  final String storyOwnerName;
  final StatusStoryType segmentType;

  /// The status item this reply was sent from.
  ///
  /// Null on replies written before this was recorded; those keep the old
  /// owner-only behaviour rather than becoming dead links.
  final String? segmentId;

  /// Caption/text-story content at reply time -- null for a photo/video
  /// segment with no caption.
  final String? previewText;

  /// The segment's own hosted media URL (photo/video) at reply time. Null
  /// for a text-only segment, or if the segment had no uploaded media yet.
  final String? mediaUrl;
  final int? accentColorArgb;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'storyOwnerUid': storyOwnerUid,
      'storyOwnerName': storyOwnerName,
      'segmentType': segmentType.name,
      'segmentId': segmentId,
      'previewText': previewText,
      'mediaUrl': mediaUrl,
      'accentColorArgb': accentColorArgb,
    };
  }

  static StoryReplyContext? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final storyOwnerUid = raw['storyOwnerUid'];
    final storyOwnerName = raw['storyOwnerName'];
    if (storyOwnerUid is! String ||
        storyOwnerUid.isEmpty ||
        storyOwnerName is! String) {
      return null;
    }
    final segmentType = StatusStoryType.values.firstWhere(
      (value) => value.name == raw['segmentType'],
      orElse: () => StatusStoryType.text,
    );
    final segmentId = raw['segmentId'];
    final previewText = raw['previewText'];
    final mediaUrl = raw['mediaUrl'];
    final accentColorArgb = raw['accentColorArgb'];
    return StoryReplyContext(
      storyOwnerUid: storyOwnerUid,
      storyOwnerName: storyOwnerName,
      segmentType: segmentType,
      segmentId: segmentId is String && segmentId.isNotEmpty ? segmentId : null,
      previewText:
          previewText is String && previewText.isNotEmpty ? previewText : null,
      mediaUrl: mediaUrl is String && mediaUrl.isNotEmpty ? mediaUrl : null,
      accentColorArgb: switch (accentColorArgb) {
        int value => value,
        num value => value.toInt(),
        _ => null,
      },
    );
  }
}
