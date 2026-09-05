import 'dart:async';

import 'package:flutter/painting.dart';

import '../../../core/models/status_story.dart';
import '../data/status_media_local_cache.dart';
import '../data/status_media_remote_cache_index.dart';
import '../presentation/widgets/status_media_source.dart';
import 'status_media_prefetch.dart';

Set<String> remoteStoryMediaPaths(Iterable<StatusStory> stories) {
  final paths = <String>{};
  for (final story in stories) {
    for (final segment in story.segments) {
      for (final candidate in <String?>[
        segment.displayMediaPath,
        segment.localMediaPath,
      ]) {
        final path = candidate?.trim();
        if (path != null &&
            path.isNotEmpty &&
            isRemoteStatusMediaPath(path)) {
          paths.add(path);
        }
      }
    }
  }
  return paths;
}

Set<String> liveStorySegmentIds(Iterable<StatusStory> stories) {
  return <String>{
    for (final story in stories)
      for (final segment in story.segments) segment.id,
  };
}

/// Drops disk, memory, preload, and poster-local entries for media that is
/// no longer part of the live story feed.
///
/// Reconciles twice:
/// 1. In-session diff ([explicitlyEvictPaths]) -- immediate cleanup when
///    Firestore live updates arrive while the app is open.
/// 2. Persistent index vs live feed -- cold-start cleanup when the owner
///    deleted/expired a story while our process was not running.
Future<void> reconcileStatusMediaCaches({
  required Iterable<StatusStory> liveStories,
  Iterable<String> explicitlyEvictPaths = const <String>[],
}) async {
  final livePaths = remoteStoryMediaPaths(liveStories);
  final liveSegmentIds = liveStorySegmentIds(liveStories);

  StatusMediaPrefetchCoordinator.instance.reconcile(liveStories);
  StatusVideoPreloadCache.instance.evictExcept(livePaths);

  Set<String> indexedPaths = const <String>{};
  try {
    indexedPaths = await StatusMediaRemoteCacheIndex().readAll();
  } catch (_) {
    // Best-effort -- preferences may be unavailable in tests.
  }

  final stalePaths = explicitlyEvictPaths
      .map((path) => path.trim())
      .where((path) => path.isNotEmpty)
      .where(isRemoteStatusMediaPath)
      .toSet()
    ..addAll(indexedPaths.difference(livePaths));

  for (final path in stalePaths) {
    await evictStatusMediaPath(path);
  }

  try {
    await StatusMediaRemoteCacheIndex().retainOnly(livePaths);
  } catch (_) {
    // Best-effort only.
  }

  try {
    await StatusMediaLocalCache().retainOnly(liveSegmentIds);
  } catch (_) {
    // Best-effort -- preferences may be unavailable in tests.
  }
}

/// Evicts one remote story media URL from every local cache layer.
Future<void> evictStatusMediaPath(String mediaPath) async {
  final path = mediaPath.trim();
  if (path.isEmpty || !isRemoteStatusMediaPath(path)) {
    return;
  }

  StatusVideoPreloadCache.instance.evict(path);

  final provider = imageProviderForStatusMediaPath(path);
  if (provider != null) {
    PaintingBinding.instance.imageCache.evict(provider);
  }

  try {
    await statusMediaCacheManager.removeFile(path);
  } catch (_) {
    // Best-effort only.
  }

  try {
    await StatusMediaRemoteCacheIndex().forget(path);
  } catch (_) {
    // Best-effort only.
  }
}

/// Clears all warmed story media on sign-out / controller teardown.
Future<void> clearAllStatusMediaCaches() async {
  StatusMediaPrefetchCoordinator.instance.clear();
  await StatusVideoPreloadCache.instance.disposeAll();
  try {
    await StatusMediaRemoteCacheIndex().clear();
  } catch (_) {
    // Best-effort only.
  }
}
