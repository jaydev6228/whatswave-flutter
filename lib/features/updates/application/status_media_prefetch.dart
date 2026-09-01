import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:video_player/video_player.dart';

import '../../../core/models/status_story.dart';
import '../presentation/widgets/status_media_source.dart';

/// Warms the media caches for a just-posted segment right after
/// [UpdatesController.createStatus] succeeds, so the first time it's opened
/// -- including by the poster, seconds later -- doesn't cold-fetch over the
/// network. Firebase-backed status media is uploaded to Storage and its
/// `localMediaPath` field is repointed to the resulting `https://` URL (see
/// FirebaseStatusMediaStore), so status_media_source.dart resolves a fresh
/// NetworkImage/VideoPlayerController.networkUrl on every open with no
/// caching in between. A no-op for any local/asset path (the fake/demo
/// backend never produces a remote URL, so this never fires there).
///
/// Best-effort only: never throws, never blocks the caller. A missed
/// prefetch just means the viewer falls back to its normal cold-load
/// spinner, not a broken post.
Future<void> prefetchStatusMedia(StatusStorySegment? segment) async {
  // displayMediaPath: once the on-device original is remembered there is
  // nothing to warm, so posting no longer pulls its own upload back down.
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
        await _prefetchVideo(path);
      case StatusStoryType.text:
        break;
    }
  } catch (_) {
    // Best-effort -- the viewer's own cold-load path remains the fallback.
  }
}

Future<void> _prefetchPhoto(String path) {
  final imageProvider = imageProviderForStatusMediaPath(path);
  if (imageProvider == null) {
    return Future<void>.value();
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
  return completer.future;
}

Future<void> _prefetchVideo(String path) {
  return StatusVideoPreloadCache.instance.preload(path);
}

/// Holds at most one pre-initialized [VideoPlayerController] for a
/// just-posted remote video segment, so [StatusStoryViewerScreen]'s own
/// controller construction (in `_startCurrentSegmentPlayback`) can take an
/// already-initialized controller instead of building and initializing a
/// fresh one over the network. `video_player` has no persistent on-disk
/// byte cache the way `ImageCache` does for photos -- an initialized
/// controller IS the cache here.
///
/// Single-slot by design: a user only ever has one just-posted segment to
/// warm at a time, and holding more would mean juggling multiple live
/// platform video players for no benefit.
class StatusVideoPreloadCache {
  StatusVideoPreloadCache._();

  static final StatusVideoPreloadCache instance = StatusVideoPreloadCache._();

  String? _path;
  VideoPlayerController? _controller;
  Future<void>? _initialization;

  Future<void> preload(String path) async {
    if (_path == path) {
      final initialization = _initialization;
      if (initialization != null) {
        await initialization;
      }
      return;
    }

    await _disposeCurrent();

    final controller = await buildStatusMediaVideoControllerAsync(path);
    final initialization = controller.initialize();
    _path = path;
    _controller = controller;
    _initialization = initialization;

    try {
      await initialization;
    } catch (_) {
      // Leave the failed entry out of the cache -- the viewer's own
      // construction will retry and surface its usual error handling.
      await _disposeCurrent();
    }
  }

  /// Removes and returns the cached controller/initialization for [path] if
  /// present, transferring ownership (including disposal responsibility) to
  /// the caller. Returns null on a miss -- the caller should build its own
  /// controller as usual.
  ({VideoPlayerController controller, Future<void> initialization})? take(
    String path,
  ) {
    if (_path != path || _controller == null || _initialization == null) {
      return null;
    }
    final result = (controller: _controller!, initialization: _initialization!);
    _path = null;
    _controller = null;
    _initialization = null;
    return result;
  }

  Future<void> _disposeCurrent() async {
    final controller = _controller;
    _path = null;
    _controller = null;
    _initialization = null;
    if (controller != null) {
      await controller.dispose();
    }
  }
}
