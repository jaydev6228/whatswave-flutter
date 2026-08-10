import '../../../core/models/channel_preview.dart';
import '../../../core/models/status_story.dart';
import '../../../core/models/story_viewer.dart';

class UpdatesFeed {
  const UpdatesFeed({
    required this.stories,
    required this.channels,
  });

  final List<StatusStory> stories;
  final List<ChannelPreview> channels;
}

abstract class UpdatesRepository {
  Future<UpdatesFeed> fetchUpdates();

  /// Live updates, so a change made on another device (e.g. someone else
  /// deleting their status) is reflected without needing to relaunch or
  /// manually refresh. Null for implementations with no real-time backing
  /// (e.g. the local/fake repository) -- callers should fall back to
  /// [fetchUpdates] alone in that case.
  Stream<UpdatesFeed>? watchUpdates();

  Future<List<StatusStory>> createStatus({
    required StatusStoryType type,
    String? caption,
    String? localMediaPath,
    StatusTextStyle? textStyle,
    StatusMediaTransform? mediaTransform,
    List<StatusMediaOverlayItem>? overlayItems,
    String? emoji,
    List<String>? stickers,
    StatusMusicTrack? musicTrack,
    int? durationMillis,
  });

  Future<List<StatusStory>> markStoryViewed(
    String storyId, {
    required int seenSegments,
  });

  Future<List<StatusStory>> deleteStatusSegment({
    required String storyId,
    required String segmentId,
  });

  Future<List<StatusStory>> clearStory({
    required String storyId,
  });

  /// Everyone who has viewed [storyId] -- only meaningful for a story you
  /// own; implementations may return an empty list otherwise. See
  /// [StoryViewer].
  Future<List<StoryViewer>> fetchStoryViewers(String storyId);
}

class UpdatesRepositoryException implements Exception {
  const UpdatesRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
