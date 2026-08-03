import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/channel_preview.dart';
import '../../../core/models/status_story.dart';
import '../../../core/sample/demo_data.dart';
import 'status_media_store.dart';
import 'updates_repository.dart';

class FakeUpdatesRepository implements UpdatesRepository {
  FakeUpdatesRepository({
    List<StatusStory>? initialStories,
    List<ChannelPreview>? initialChannels,
    this.latency = const Duration(milliseconds: 220),
    this.failFetch = false,
    this.failCreateStatus = false,
    this.persistStories = false,
    SharedPreferences? preferences,
    StatusMediaStore? mediaStore,
  })  : _stories = _cloneStories(initialStories ?? DemoData.stories),
        _channels = _cloneChannels(initialChannels ?? DemoData.channels),
        _preferences = preferences,
        _mediaStore = mediaStore ?? const LocalStatusMediaStore();

  static const _persistedStoriesKey = 'demo_updates_stories_v2';

  final Duration latency;
  final bool failFetch;
  final bool failCreateStatus;
  final bool persistStories;
  List<StatusStory> _stories;
  final List<ChannelPreview> _channels;
  final StatusMediaStore _mediaStore;
  SharedPreferences? _preferences;
  bool _didHydratePersistedState = false;

  Future<void> _wait() {
    if (latency == Duration.zero) {
      return Future<void>.value();
    }
    return Future<void>.delayed(latency);
  }

  @override
  Stream<UpdatesFeed>? watchUpdates() => null;

  @override
  Future<UpdatesFeed> fetchUpdates() async {
    await _hydratePersistedState();
    await _backfillSeededStoriesIfNeeded();
    await _wait();
    if (failFetch) {
      throw const UpdatesRepositoryException(
        'We could not load updates right now.',
      );
    }

    return UpdatesFeed(
      stories: _cloneStories(_stories),
      channels: _cloneChannels(_channels),
    );
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
  }) async {
    await _hydratePersistedState();
    await _wait();
    if (failCreateStatus) {
      throw const UpdatesRepositoryException(
        'We could not share that status right now.',
      );
    }

    final normalizedCaption = caption?.trim() ?? '';
    final normalizedEmoji = emoji?.trim();
    final normalizedStickers = List<String>.unmodifiable(
      (stickers ?? const <String>[])
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty),
    );
    final normalizedOverlayItems = List<StatusMediaOverlayItem>.unmodifiable(
      overlayItems == null || overlayItems.isEmpty
          ? _legacyOverlayItems(
              caption: normalizedCaption,
              textStyle: textStyle,
              emoji: normalizedEmoji,
              stickers: normalizedStickers,
              musicTrack: musicTrack,
            )
          : overlayItems,
    );
    final previewText = normalizedCaption.isEmpty
        ? switch (type) {
            StatusStoryType.text => 'Shared a fresh text update',
            StatusStoryType.photo => 'Shared a new photo update',
            StatusStoryType.video => 'Shared a new video update',
          }
        : normalizedCaption;

    final myStatusIndex = _stories.indexWhere((story) => story.isMine);
    final currentMyStatus = myStatusIndex == -1
        ? const StatusStory(
            id: 'my-status',
            name: 'My Status',
            avatarLabel: 'JD',
            previewText: '',
            timeLabel: 'Add now',
            accentColor: AppPalette.emerald,
            isMine: true,
            totalSegments: 0,
            seenSegments: 0,
          )
        : _stories[myStatusIndex];
    final storedMediaPath =
        await _maybeImportMedia(type: type, localMediaPath: localMediaPath);
    final nextSegments = List<StatusStorySegment>.unmodifiable([
      ..._segmentsFor(currentMyStatus),
      StatusStorySegment(
        id: 'status-${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        previewText: previewText,
        localMediaPath: storedMediaPath,
        mediaTransform: mediaTransform ?? const StatusMediaTransform(),
        durationMillis: durationMillis,
        textStyle: type == StatusStoryType.text
            ? (textStyle ?? const StatusTextStyle())
            : textStyle,
        emoji: normalizedEmoji?.isEmpty == true ? null : normalizedEmoji,
        stickers: normalizedStickers,
        musicTrack: musicTrack,
        overlayItems: normalizedOverlayItems,
      ),
    ]);

    final updatedMyStatus = currentMyStatus.copyWith(
      type: type,
      previewText: previewText,
      timeLabel: 'Just now',
      totalSegments: nextSegments.length,
      seenSegments: 0,
      segments: nextSegments,
    );

    if (myStatusIndex == -1) {
      _stories = List<StatusStory>.unmodifiable([
        updatedMyStatus,
        ..._stories,
      ]);
    } else {
      _stories = List<StatusStory>.unmodifiable([
        updatedMyStatus,
        ..._stories.where((story) => story.id != updatedMyStatus.id),
      ]);
    }

    await _persistCurrentState();
    return _cloneStories(_stories);
  }

  List<StatusMediaOverlayItem> _legacyOverlayItems({
    required String caption,
    required StatusTextStyle? textStyle,
    required String? emoji,
    required List<String> stickers,
    required StatusMusicTrack? musicTrack,
  }) {
    final items = <StatusMediaOverlayItem>[];
    if (caption.isNotEmpty) {
      items.add(
        StatusMediaOverlayItem(
          id: 'overlay-caption',
          type: StatusMediaOverlayType.text,
          label: caption,
          positionDx: 0.5,
          positionDy: 0.82,
          scale: 1,
          textStyle: textStyle,
        ),
      );
    }
    if (emoji?.isNotEmpty == true) {
      items.add(
        StatusMediaOverlayItem(
          id: 'overlay-emoji',
          type: StatusMediaOverlayType.emoji,
          label: emoji!,
          positionDx: 0.8,
          positionDy: 0.18,
          scale: 1,
        ),
      );
    }
    for (var index = 0; index < stickers.length; index++) {
      items.add(
        StatusMediaOverlayItem(
          id: 'overlay-sticker-$index',
          type: StatusMediaOverlayType.sticker,
          label: stickers[index],
          positionDx: 0.32 + (0.18 * (index % 3)),
          positionDy: 0.62 + (0.1 * (index ~/ 3)),
          scale: 1,
        ),
      );
    }
    if (musicTrack != null) {
      items.add(
        StatusMediaOverlayItem(
          id: 'overlay-music',
          type: StatusMediaOverlayType.music,
          label: musicTrack.title,
          subtitle: musicTrack.artist,
          positionDx: 0.24,
          positionDy: 0.14,
          scale: 1,
          accentColorValue: musicTrack.colorValue,
        ),
      );
    }
    return List<StatusMediaOverlayItem>.unmodifiable(items);
  }

  @override
  Future<List<StatusStory>> markStoryViewed(
    String storyId, {
    required int seenSegments,
  }) async {
    await _hydratePersistedState();
    await _wait();
    _stories = List<StatusStory>.unmodifiable(
      _stories.map((story) {
        if (story.id != storyId || story.isMine || !story.hasSegments) {
          return story;
        }
        final normalizedSeenSegments =
            seenSegments.clamp(0, story.totalSegments).toInt();
        if (normalizedSeenSegments <= story.clampedSeenSegments) {
          return story;
        }
        return story.copyWith(seenSegments: normalizedSeenSegments);
      }),
    );
    await _persistCurrentState();
    return _cloneStories(_stories);
  }

  @override
  Future<List<StatusStory>> deleteStatusSegment({
    required String storyId,
    required String segmentId,
  }) async {
    await _hydratePersistedState();
    await _wait();

    final story = _stories.cast<StatusStory?>().firstWhere(
          (entry) => entry?.id == storyId,
          orElse: () => null,
        );
    if (story == null || !story.isMine) {
      throw const UpdatesRepositoryException(
        'Only your own statuses can be deleted right now.',
      );
    }

    final currentSegments = _segmentsFor(story);
    final segmentToDelete =
        currentSegments.cast<StatusStorySegment?>().firstWhere(
              (entry) => entry?.id == segmentId,
              orElse: () => null,
            );
    if (segmentToDelete == null) {
      throw const UpdatesRepositoryException(
        'That status item could not be found anymore.',
      );
    }

    final remainingSegments = List<StatusStorySegment>.unmodifiable(
      currentSegments.where((segment) => segment.id != segmentId),
    );
    final nextStory = _storyAfterSegmentRemoval(
      story,
      remainingSegments,
    );

    await _deleteOrphanedMedia(
      removedSegments: <StatusStorySegment>[segmentToDelete],
      remainingSegments: remainingSegments,
    );

    _stories = List<StatusStory>.unmodifiable([
      nextStory,
      ..._stories.where((entry) => entry.id != storyId),
    ]);
    await _persistCurrentState();
    return _cloneStories(_stories);
  }

  @override
  Future<List<StatusStory>> clearStory({
    required String storyId,
  }) async {
    await _hydratePersistedState();
    await _wait();

    final story = _stories.cast<StatusStory?>().firstWhere(
          (entry) => entry?.id == storyId,
          orElse: () => null,
        );
    if (story == null || !story.isMine) {
      throw const UpdatesRepositoryException(
        'Only your own statuses can be cleared right now.',
      );
    }

    final currentSegments = _segmentsFor(story);
    await _deleteOrphanedMedia(
      removedSegments: currentSegments,
      remainingSegments: const <StatusStorySegment>[],
    );

    final nextStory = _storyAfterSegmentRemoval(
      story,
      const <StatusStorySegment>[],
    );
    _stories = List<StatusStory>.unmodifiable([
      nextStory,
      ..._stories.where((entry) => entry.id != storyId),
    ]);
    await _persistCurrentState();
    return _cloneStories(_stories);
  }

  Future<String?> _maybeImportMedia({
    required StatusStoryType type,
    String? localMediaPath,
  }) async {
    if (type == StatusStoryType.text) {
      return null;
    }

    return _mediaStore.importMedia(
      localMediaPath ?? '',
      type: type,
    );
  }

  List<StatusStorySegment> _segmentsFor(StatusStory story) {
    if (story.segments.isNotEmpty) {
      return story.segments;
    }
    if (!story.hasSegments) {
      return const <StatusStorySegment>[];
    }

    return <StatusStorySegment>[
      StatusStorySegment(
        id: '${story.id}-legacy',
        type: story.type,
        previewText: story.previewText,
      ),
    ];
  }

  StatusStory _storyAfterSegmentRemoval(
    StatusStory story,
    List<StatusStorySegment> remainingSegments,
  ) {
    if (remainingSegments.isEmpty) {
      return story.copyWith(
        type: StatusStoryType.text,
        previewText: 'Tap to add a text, photo, or video update',
        timeLabel: 'Add now',
        totalSegments: 0,
        seenSegments: 0,
        segments: const <StatusStorySegment>[],
      );
    }

    final latestSegment = remainingSegments.last;
    return story.copyWith(
      type: latestSegment.type,
      previewText: latestSegment.previewText,
      timeLabel: 'Just now',
      totalSegments: remainingSegments.length,
      seenSegments: 0,
      segments: remainingSegments,
    );
  }

  Future<void> _deleteOrphanedMedia({
    required List<StatusStorySegment> removedSegments,
    required List<StatusStorySegment> remainingSegments,
  }) async {
    final remainingPaths = remainingSegments
        .map((segment) => segment.localMediaPath?.trim() ?? '')
        .where((path) => path.isNotEmpty)
        .toSet();
    final orphanedPaths = removedSegments
        .map((segment) => segment.localMediaPath?.trim() ?? '')
        .where((path) => path.isNotEmpty && !remainingPaths.contains(path))
        .toSet();
    if (orphanedPaths.isEmpty) {
      return;
    }

    await _mediaStore.deleteMedia(orphanedPaths);
  }

  Future<void> _hydratePersistedState() async {
    if (!persistStories || _didHydratePersistedState) {
      return;
    }

    _didHydratePersistedState = true;
    final preferences = await _preferencesInstance;
    final persistedStories =
        preferences.getStringList(_persistedStoriesKey) ?? const <String>[];
    if (persistedStories.isEmpty) {
      await _persistCurrentState();
      return;
    }

    final restoredStories = <StatusStory>[
      for (final entry in persistedStories)
        if (_decodeStory(entry) case final story?) story,
    ];
    if (restoredStories.isNotEmpty) {
      _stories = List<StatusStory>.unmodifiable(restoredStories);
    }
  }

  Future<void> _persistCurrentState() async {
    if (!persistStories) {
      return;
    }

    final preferences = await _preferencesInstance;
    await preferences.setStringList(
      _persistedStoriesKey,
      _stories.map(_encodeStory).toList(growable: false),
    );
  }

  Future<SharedPreferences> get _preferencesInstance async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  Future<void> _backfillSeededStoriesIfNeeded() async {
    var didChange = false;
    final nextStories = <StatusStory>[];

    for (final story in _stories) {
      final seededStory = DemoData.storyById(story.id);
      if (seededStory == null || story.isMine) {
        nextStories.add(story);
        continue;
      }

      final refreshedSeededStory = seededStory.copyWith(
        name: story.name,
        avatarLabel: story.avatarLabel,
        timeLabel: story.timeLabel,
        accentColor: story.accentColor,
        type: seededStory.type,
        totalSegments: seededStory.totalSegments,
        seenSegments:
            story.seenSegments.clamp(0, seededStory.totalSegments).toInt(),
        segments: seededStory.segments,
      );
      if (_encodeStory(story) == _encodeStory(refreshedSeededStory)) {
        nextStories.add(story);
        continue;
      }

      didChange = true;
      nextStories.add(
        refreshedSeededStory,
      );
    }

    if (!didChange) {
      return;
    }

    _stories = List<StatusStory>.unmodifiable(nextStories);
    await _persistCurrentState();
  }

  String _encodeStory(StatusStory story) => jsonEncode(story.toJson());

  StatusStory? _decodeStory(String serialized) {
    if (serialized.isEmpty) {
      return null;
    }

    try {
      return StatusStory.fromJson(jsonDecode(serialized));
    } catch (_) {
      return null;
    }
  }

  static List<StatusStory> _cloneStories(List<StatusStory> stories) {
    return List<StatusStory>.unmodifiable(
      stories.map((story) => story.copyWith()),
    );
  }

  static List<ChannelPreview> _cloneChannels(List<ChannelPreview> channels) {
    return List<ChannelPreview>.unmodifiable(
      channels.map((channel) => channel.copyWith()),
    );
  }
}
