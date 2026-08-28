import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';
import 'package:whatswave/features/updates/data/status_media_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('persists locally created statuses across repository instances',
      () async {
    final firstLaunchRepository = FakeUpdatesRepository(
      latency: Duration.zero,
      persistStories: true,
    );

    await firstLaunchRepository.createStatus(
      type: StatusStoryType.text,
      caption: 'Local story persistence is ready.',
      textStyle: const StatusTextStyle(
        fontId: 'poster',
        backgroundId: 'sunset_glow',
        layout: StatusTextLayout.invitation,
        alignment: StatusTextAlignment.center,
        textColorValue: 0xFF111B21,
        backgroundColorValue: 0xFF7C3AED,
        useSolidBackground: true,
        sizeScale: 1.12,
      ),
    );

    final relaunchedRepository = FakeUpdatesRepository(
      latency: Duration.zero,
      persistStories: true,
    );
    final updatesFeed = await relaunchedRepository.fetchUpdates();
    final myStatus = updatesFeed.stories.singleWhere((story) => story.isMine);

    expect(myStatus.previewText, 'Local story persistence is ready.');
    expect(myStatus.totalSegments, 1);
    expect(
      myStatus.latestSegment?.previewText,
      'Local story persistence is ready.',
    );
    expect(myStatus.latestSegment?.textStyle?.fontId, 'poster');
    expect(
      myStatus.latestSegment?.textStyle?.backgroundId,
      'sunset_glow',
    );
    expect(
      myStatus.latestSegment?.textStyle?.backgroundColorValue,
      0xFF7C3AED,
    );
    expect(
      myStatus.latestSegment?.textStyle?.useSolidBackground,
      isTrue,
    );
    expect(
      myStatus.latestSegment?.textStyle?.layout,
      StatusTextLayout.invitation,
    );
  });

  test('stores imported local media metadata for photo statuses', () async {
    final repository = FakeUpdatesRepository(
      latency: Duration.zero,
      mediaStore: const _PassThroughStatusMediaStore('/local/status/photo.jpg'),
    );

    final updatedStories = await repository.createStatus(
      type: StatusStoryType.photo,
      caption: 'Sunrise build check-in',
      localMediaPath: '/picked/photo.jpg',
      textStyle: const StatusTextStyle(
        fontId: 'journal',
        backgroundId: 'midnight_drive',
        layout: StatusTextLayout.note,
        alignment: StatusTextAlignment.left,
        textColorValue: 0xFFF8FAFF,
        sizeScale: 1.08,
      ),
      emoji: '🔥',
      stickers: const <String>['LIVE NOW'],
      musicTrack: const StatusMusicTrack(
        id: 'afterglow',
        title: 'Afterglow',
        artist: 'Velvet Metro',
        colorValue: 0xFF8C6BFF,
      ),
      durationMillis: 11000,
    );
    final myStatus = updatedStories.singleWhere((story) => story.isMine);

    expect(myStatus.type, StatusStoryType.photo);
    expect(myStatus.totalSegments, 1);
    expect(myStatus.latestSegment?.localMediaPath, '/local/status/photo.jpg');
    expect(myStatus.latestSegment?.previewText, 'Sunrise build check-in');
    expect(myStatus.latestSegment?.textStyle?.fontId, 'journal');
    expect(
        myStatus.latestSegment?.textStyle?.alignment, StatusTextAlignment.left);
    expect(myStatus.latestSegment?.textStyle?.sizeScale, 1.08);
    expect(myStatus.latestSegment?.emoji, '🔥');
    expect(myStatus.latestSegment?.stickers, const <String>['LIVE NOW']);
    expect(myStatus.latestSegment?.musicTrack?.title, 'Afterglow');
    expect(myStatus.latestSegment?.durationMillis, 11000);
  });

  test('cleans up orphaned media when statuses are deleted', () async {
    final mediaStore = _RecordingStatusMediaStore(<String>[
      '/local/status/older-photo.jpg',
      '/local/status/latest-video.mp4',
    ]);
    final repository = FakeUpdatesRepository(
      latency: Duration.zero,
      mediaStore: mediaStore,
    );

    await repository.createStatus(
      type: StatusStoryType.photo,
      caption: 'Older photo',
      localMediaPath: '/picked/older-photo.jpg',
    );
    final updatedStories = await repository.createStatus(
      type: StatusStoryType.video,
      caption: 'Latest video',
      localMediaPath: '/picked/latest-video.mp4',
    );

    final myStatus = updatedStories.singleWhere((story) => story.isMine);
    final olderSegmentId = myStatus.segments.first.id;

    final storiesAfterDelete = await repository.deleteStatusSegment(
      storyId: myStatus.id,
      segmentId: olderSegmentId,
    );
    final afterSingleDelete =
        storiesAfterDelete.singleWhere((story) => story.isMine);

    expect(
      mediaStore.deletedPaths,
      contains('/local/status/older-photo.jpg'),
    );
    expect(afterSingleDelete.totalSegments, 1);
    expect(
      afterSingleDelete.latestSegment?.localMediaPath,
      '/local/status/latest-video.mp4',
    );

    await repository.clearStory(storyId: myStatus.id);

    expect(
      mediaStore.deletedPaths,
      contains('/local/status/latest-video.mp4'),
    );
  });

  test('refreshes persisted seeded stories when demo story data changes',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'demo_updates_stories_v2': <String>[
        jsonEncode(
          const StatusStory(
            id: 'ava-story',
            name: 'Ava',
            avatarLabel: 'AP',
            previewText: 'Late-night launch coffee',
            timeLabel: '15m ago',
            accentColor: AppPalette.green,
            type: StatusStoryType.photo,
            totalSegments: 1,
            seenSegments: 0,
            segments: <StatusStorySegment>[
              StatusStorySegment(
                id: 'ava-story-0',
                type: StatusStoryType.photo,
                previewText: 'Shared a new photo update',
                localMediaPath:
                    'asset://assets/media/status_demo/launch_cafe.jpg',
                overlayItems: <StatusMediaOverlayItem>[
                  StatusMediaOverlayItem(
                    id: 'ava-story-0-emoji',
                    type: StatusMediaOverlayType.emoji,
                    label: '☕',
                    positionDx: 0.82,
                    positionDy: 0.2,
                    scale: 1.08,
                  ),
                ],
              ),
            ],
          ).toJson(),
        ),
      ],
    });

    final repository = FakeUpdatesRepository(
      latency: Duration.zero,
      persistStories: true,
    );
    final updatesFeed = await repository.fetchUpdates();
    final avaStory = updatesFeed.stories.singleWhere(
      (story) => story.id == 'ava-story',
    );
    final emojiOverlay = avaStory.segments.first.overlayItems.firstWhere(
      (item) => item.type == StatusMediaOverlayType.emoji,
    );

    expect(emojiOverlay.label, '☕️');
  });

  test('tracks story likes per segment instead of for the whole ring',
      () async {
    final repository = FakeUpdatesRepository(latency: Duration.zero);

    await repository.setStoryLiked(
      'ava-story',
      segmentId: 'ava-story-0',
      liked: true,
    );
    expect(
      await repository.isStoryLikedByMe(
        'ava-story',
        segmentId: 'ava-story-0',
      ),
      isTrue,
    );
    expect(
      await repository.isStoryLikedByMe(
        'ava-story',
        segmentId: 'ava-story-1',
      ),
      isFalse,
    );

    await repository.setStoryLiked(
      'ava-story',
      segmentId: 'ava-story-0',
      liked: false,
    );
    expect(
      await repository.isStoryLikedByMe(
        'ava-story',
        segmentId: 'ava-story-0',
      ),
      isFalse,
    );
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

class _RecordingStatusMediaStore implements StatusMediaStore {
  _RecordingStatusMediaStore(this._importTargets);

  final List<String> _importTargets;
  final List<String> deletedPaths = <String>[];
  int _nextImportIndex = 0;

  @override
  Future<String> importMedia(
    String sourcePath, {
    required StatusStoryType type,
  }) async {
    final targetPath = _importTargets[_nextImportIndex];
    _nextImportIndex += 1;
    return targetPath;
  }

  @override
  Future<void> deleteMedia(Iterable<String> mediaPaths) async {
    deletedPaths.addAll(mediaPaths);
  }
}
