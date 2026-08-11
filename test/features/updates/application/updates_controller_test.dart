import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/core/models/story_viewer.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';
import 'package:whatswave/features/updates/data/status_media_store.dart';
import 'package:whatswave/features/updates/data/updates_repository.dart';

void main() {
  group('UpdatesController', () {
    late UpdatesController controller;

    setUp(() {
      controller = UpdatesController(
        repository: FakeUpdatesRepository(latency: Duration.zero),
      );
    });

    test('loads updates and splits recent versus viewed stories', () async {
      await controller.loadUpdates();

      expect(controller.hasLoaded, isTrue);
      expect(controller.myStatus?.id, 'my-status');
      expect(
        controller.recentStories.map((story) => story.id),
        containsAll(<String>['ava-story', 'noah-story']),
      );
      expect(controller.viewedStories.single.id, 'priya-story');
      expect(controller.channels, hasLength(2));
    });

    test('creates a new status and refreshes the my-status card', () async {
      final mediaBackedController = UpdatesController(
        repository: FakeUpdatesRepository(
          latency: Duration.zero,
          mediaStore: const _PassThroughStatusMediaStore('/local/photo.jpg'),
        ),
      );
      await mediaBackedController.loadUpdates();

      final didCreate = await mediaBackedController.createStatus(
        type: StatusStoryType.photo,
        caption: 'Night build gallery is ready.',
        localMediaPath: '/picked/photo.jpg',
        emoji: '✨',
        stickers: const <String>['NEW DROP', 'ON AIR'],
        musicTrack: const StatusMusicTrack(
          id: 'city-pulse',
          title: 'City Pulse',
          artist: 'Whatswave House',
          colorValue: 0xFF25D366,
        ),
        durationMillis: 9000,
      );

      expect(didCreate, isTrue);
      expect(
        mediaBackedController.myStatus?.previewText,
        'Night build gallery is ready.',
      );
      expect(mediaBackedController.myStatus?.timeLabel, 'Just now');
      expect(mediaBackedController.myStatus?.type, StatusStoryType.photo);
      expect(mediaBackedController.myStatus?.totalSegments, 1);
      expect(
        mediaBackedController.myStatus?.latestSegment?.localMediaPath,
        '/local/photo.jpg',
      );
      expect(mediaBackedController.myStatus?.latestSegment?.emoji, '✨');
      expect(
        mediaBackedController.myStatus?.latestSegment?.stickers,
        const <String>['NEW DROP', 'ON AIR'],
      );
      expect(
        mediaBackedController.myStatus?.latestSegment?.musicTrack?.title,
        'City Pulse',
      );
      expect(
        mediaBackedController.myStatus?.latestSegment?.durationMillis,
        9000,
      );
    });

    test('moves a story into viewed once it is marked seen', () async {
      await controller.loadUpdates();

      await controller.markStoryViewed('ava-story', seenSegments: 3);

      expect(
        controller.recentStories.any((story) => story.id == 'ava-story'),
        isFalse,
      );
      expect(
        controller.viewedStories.any((story) => story.id == 'ava-story'),
        isTrue,
      );
    });

    test('keeps partially viewed stories in recent until all segments are seen',
        () async {
      await controller.loadUpdates();

      await controller.markStoryViewed('noah-story', seenSegments: 2);

      expect(
        controller.recentStories.any((story) => story.id == 'noah-story'),
        isTrue,
      );
      expect(
        controller.viewedStories.any((story) => story.id == 'noah-story'),
        isFalse,
      );
      expect(
        controller.recentStories
            .singleWhere((story) => story.id == 'noah-story')
            .seenSegments,
        2,
      );
    });

    test('deletes a single status segment and keeps remaining items intact',
        () async {
      await controller.loadUpdates();
      await controller.createStatus(
        type: StatusStoryType.text,
        caption: 'Older status',
      );
      await controller.createStatus(
        type: StatusStoryType.text,
        caption: 'Latest status',
      );

      final segmentIdToDelete = controller.myStatus!.segments.first.id;
      final didDelete =
          await controller.deleteMyStatusSegment(segmentIdToDelete);

      expect(didDelete, isTrue);
      expect(controller.myStatus?.totalSegments, 1);
      expect(
        controller.myStatus?.latestSegment?.previewText,
        'Latest status',
      );
      expect(
        controller.myStatus?.segments
            .any((segment) => segment.id == segmentIdToDelete),
        isFalse,
      );
    });

    test('clears all of my statuses and returns to an empty state', () async {
      await controller.loadUpdates();
      await controller.createStatus(
        type: StatusStoryType.text,
        caption: 'One more update',
      );

      final didClear = await controller.clearMyStatuses();

      expect(didClear, isTrue);
      expect(controller.myStatus?.hasSegments, isFalse);
      expect(controller.myStatus?.totalSegments, 0);
      expect(
        controller.myStatus?.previewText,
        'Tap to add a text, photo, or video update',
      );
      expect(controller.myStatus?.latestSegment, isNull);
    });

    test('surfaces repository failures on initial load', () async {
      final failingController = UpdatesController(
        repository: _FailingUpdatesRepository(),
      );

      await failingController.loadUpdates();

      expect(failingController.hasLoaded, isFalse);
      expect(
        failingController.errorMessage,
        'Updates backend unavailable',
      );
      expect(failingController.stories, isEmpty);
    });
  });
}

class _PassThroughStatusMediaStore implements StatusMediaStore {
  const _PassThroughStatusMediaStore(this.targetPath);

  final String targetPath;

  @override
  Future<String> importMedia(
    String sourcePath, {
    required StatusStoryType type,
  }) async {
    return targetPath;
  }

  @override
  Future<void> deleteMedia(Iterable<String> mediaPaths) async {}
}

class _FailingUpdatesRepository implements UpdatesRepository {
  @override
  Stream<UpdatesFeed>? watchUpdates() => null;

  @override
  Future<UpdatesFeed> fetchUpdates() {
    throw const UpdatesRepositoryException('Updates backend unavailable');
  }

  @override
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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<StatusStory>> markStoryViewed(
    String storyId, {
    required int seenSegments,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<StatusStory>> deleteStatusSegment({
    required String storyId,
    required String segmentId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<StatusStory>> clearStory({
    required String storyId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<StoryViewer>> fetchStoryViewers(String storyId) {
    throw UnimplementedError();
  }

  @override
  Future<bool> isStoryLikedByMe(String storyId) {
    throw UnimplementedError();
  }

  @override
  Future<void> setStoryLiked(String storyId, {required bool liked}) {
    throw UnimplementedError();
  }

  @override
  Stream<List<StoryViewer>>? watchStoryViewers(String storyId) {
    throw UnimplementedError();
  }
}
