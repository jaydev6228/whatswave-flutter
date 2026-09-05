import 'dart:async';
import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:video_player/video_player.dart';

import '../../../core/models/status_story.dart';
import '../presentation/widgets/status_media_source.dart';
import '../data/status_media_remote_cache_index.dart';

/// Warms the media caches for a segment. Best-effort only.
Future<void> prefetchStatusMedia(StatusStorySegment? segment) async {
  final path = segment?.displayMediaPath?.trim();
  if (segment == null || path == null || path.isEmpty) {
    return;
  }
  if (!isRemoteStatusMediaPath(path)) {
    return;
  }

  try {
    switch (segment.type) {
      case StatusStoryType.photo:
        await _prefetchPhoto(path);
      case StatusStoryType.video:
        await StatusVideoPreloadCache.instance.preload(path);
      case StatusStoryType.text:
        break;
    }
  } catch (_) {
    // Best-effort -- the viewer's own cold-load path remains the fallback.
  }
}

/// Prefetches the first segment a user is likely to open for every live story.
void prefetchStoriesFeed(List<StatusStory> stories) {
  final segments = <StatusStorySegment>[];
  for (final story in stories) {
    if (!story.hasSegments) {
      continue;
    }
    if (story.isMine) {
      segments.addAll(story.segments);
      continue;
    }
    final index = story.clampedSeenSegments
        .clamp(0, story.segments.length - 1)
        .toInt();
    segments.add(story.segments[index]);
  }
  StatusMediaPrefetchCoordinator.instance.enqueue(segments);
}

/// Prefetches the next segment while the viewer is open.
void prefetchAdjacentStorySegments({
  required StatusStory story,
  required int currentSegmentIndex,
}) {
  if (!story.hasSegments || story.segments.isEmpty) {
    return;
  }
  final nextIndex = currentSegmentIndex + 1;
  if (nextIndex >= story.segments.length) {
    return;
  }
  unawaited(prefetchStatusMedia(story.segments[nextIndex]));
}

/// Serialises background story-media warming with a small concurrency budget.
class StatusMediaPrefetchCoordinator {
  StatusMediaPrefetchCoordinator._();

  static final StatusMediaPrefetchCoordinator instance =
      StatusMediaPrefetchCoordinator._();

  static const int _maxConcurrent = 2;

  final Queue<StatusStorySegment> _pending = Queue<StatusStorySegment>();
  final Set<String> _queuedOrActiveKeys = <String>{};
  int _inFlight = 0;

  void enqueue(Iterable<StatusStorySegment> segments) {
    for (final segment in segments) {
      final key = _segmentKey(segment);
      if (key == null || _queuedOrActiveKeys.contains(key)) {
        continue;
      }
      _queuedOrActiveKeys.add(key);
      _pending.addLast(segment);
    }
    _pump();
  }

  /// Drops queued work for segments that expired or were deleted.
  void reconcile(Iterable<StatusStory> liveStories) {
    final liveKeys = <String>{
      for (final story in liveStories)
        for (final segment in story.segments)
          if (_segmentKey(segment) case final key?) key,
    };
    _pending.removeWhere((segment) {
      final key = _segmentKey(segment);
      return key != null && !liveKeys.contains(key);
    });
    _queuedOrActiveKeys.removeWhere((key) => !liveKeys.contains(key));
  }

  void clear() {
    _pending.clear();
    _queuedOrActiveKeys.clear();
  }

  void _pump() {
    while (_inFlight < _maxConcurrent && _pending.isNotEmpty) {
      final segment = _pending.removeFirst();
      _inFlight++;
      unawaited(() async {
        try {
          await prefetchStatusMedia(segment);
        } finally {
          final key = _segmentKey(segment);
          if (key != null) {
            _queuedOrActiveKeys.remove(key);
          }
          _inFlight--;
          _pump();
        }
      }());
    }
  }

  String? _segmentKey(StatusStorySegment segment) {
    final path = segment.displayMediaPath?.trim();
    if (path == null || path.isEmpty) {
      return null;
    }
    return '${segment.id}|$path';
  }
}

Future<void> _prefetchPhoto(String path) async {
  try {
    await statusMediaCacheManager.downloadFile(path);
    await rememberRemoteStoryMediaCached(path);
  } catch (_) {
    // Fall through to provider resolve.
  }

  final imageProvider = imageProviderForStatusMediaPath(path);
  if (imageProvider == null) {
    return;
  }

  final completer = Completer<void>();
  late final ImageStreamListener listener;
  final stream = imageProvider.resolve(const ImageConfiguration());
  listener = ImageStreamListener(
    (image, synchronousCall) {
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
  );
  stream.addListener(listener);
  await completer.future;
}

/// Holds up to two pre-initialized [VideoPlayerController]s for warmed remote
/// video segments so the viewer can take an already-initialized controller.
class StatusVideoPreloadCache {
  StatusVideoPreloadCache._();

  static final StatusVideoPreloadCache instance = StatusVideoPreloadCache._();

  static const int _maxSlots = 2;

  final LinkedHashMap<String, _VideoPreloadEntry> _entries =
      LinkedHashMap<String, _VideoPreloadEntry>();

  Future<void> preload(String path) async {
    final existing = _entries[path];
    if (existing != null) {
      await existing.initialization;
      _entries.remove(path);
      _entries[path] = existing;
      return;
    }

    while (_entries.length >= _maxSlots) {
      final oldest = _entries.keys.first;
      await _disposeEntry(oldest);
    }

    final controller = await buildStatusMediaVideoControllerAsync(path);
    final initialization = controller.initialize();
    _entries[path] = _VideoPreloadEntry(
      controller: controller,
      initialization: initialization,
    );

    try {
      await initialization;
      await rememberRemoteStoryMediaCached(path);
    } catch (_) {
      await _disposeEntry(path);
    }
  }

  ({VideoPlayerController controller, Future<void> initialization})? take(
    String path,
  ) {
    final entry = _entries.remove(path);
    if (entry == null) {
      return null;
    }
    return (
      controller: entry.controller,
      initialization: entry.initialization,
    );
  }

  void evict(String path) {
    unawaited(_disposeEntry(path));
  }

  void evictExcept(Set<String> keepPaths) {
    final removable = _entries.keys.where((path) => !keepPaths.contains(path));
    for (final path in removable.toList(growable: false)) {
      unawaited(_disposeEntry(path));
    }
  }

  Future<void> disposeAll() async {
    final paths = _entries.keys.toList(growable: false);
    for (final path in paths) {
      await _disposeEntry(path);
    }
  }

  Future<void> _disposeEntry(String path) async {
    final entry = _entries.remove(path);
    if (entry != null) {
      await entry.controller.dispose();
    }
  }
}

class _VideoPreloadEntry {
  const _VideoPreloadEntry({
    required this.controller,
    required this.initialization,
  });

  final VideoPlayerController controller;
  final Future<void> initialization;
}
