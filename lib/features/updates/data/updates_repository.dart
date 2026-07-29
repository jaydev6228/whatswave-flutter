import '../../../core/models/channel_preview.dart';
import '../../../core/models/status_story.dart';

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
}

class UpdatesRepositoryException implements Exception {
  const UpdatesRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
