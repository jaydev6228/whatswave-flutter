import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

const String kBundledStatusMediaPathPrefix = 'asset://';

bool isBundledStatusMediaPath(String mediaPath) {
  return mediaPath.trim().startsWith(kBundledStatusMediaPathPrefix);
}

/// True once a chat attachment/status segment has been uploaded to Firebase
/// Storage (see MediaUploader) -- its `localMediaPath`-shaped field then
/// holds a download URL instead of a device-local path, and every reader
/// (any device, not just the one that sent it) can resolve it the same way.
/// Device-local paths only ever make sense on the device that created them.
bool isRemoteStatusMediaPath(String mediaPath) {
  final normalizedPath = mediaPath.trim();
  return normalizedPath.startsWith('https://') ||
      normalizedPath.startsWith('http://');
}

String resolveBundledStatusMediaPath(String mediaPath) {
  final normalizedPath = mediaPath.trim();
  if (!isBundledStatusMediaPath(normalizedPath)) {
    return normalizedPath;
  }
  return normalizedPath.substring(kBundledStatusMediaPathPrefix.length);
}

bool statusMediaSourceExists(String mediaPath) {
  final normalizedPath = mediaPath.trim();
  if (normalizedPath.isEmpty) {
    return false;
  }
  if (isBundledStatusMediaPath(normalizedPath) ||
      isRemoteStatusMediaPath(normalizedPath)) {
    return true;
  }
  return File(normalizedPath).existsSync();
}

/// Overrides the cache used for remote media.
///
/// Set by `test/flutter_test_config.dart`. The real [DefaultCacheManager]
/// reaches for path_provider, sqflite and the network the moment a remote
/// URL is resolved -- in a widget test none of those answer, and the pending
/// image request keeps the frame dirty so `pumpAndSettle` spins until its
/// ten-minute timeout. Production never sets this.
@visibleForTesting
BaseCacheManager? debugStatusMediaCacheManager;

BaseCacheManager get _statusMediaCacheManager =>
    debugStatusMediaCacheManager ?? DefaultCacheManager();

/// Whether the disk cache has been *proven* to work on this device.
///
/// Starts false and is only turned on once a probe succeeds, so an
/// unavailable cache degrades to plain network loading instead of hanging.
/// The cache sits on sqflite, and a build whose native plugins predate that
/// dependency throws MissingPluginException on every lookup -- which the
/// image provider surfaced as a spinner that never resolved, with no error
/// for the widget's errorBuilder to catch.
bool _diskCacheProven = false;
Future<void>? _diskCacheProbe;

/// Resolves once the probe has run. Awaited by tests; fire-and-forget in
/// production, where the first frame or two simply use the network provider.
@visibleForTesting
Future<void> ensureStatusMediaDiskCacheReady() {
  return _diskCacheProbe ??= () async {
    try {
      await _statusMediaCacheManager
          .getFileFromCache('whatswave://disk-cache-probe');
      _diskCacheProven = true;
    } catch (_) {
      // Left off. Everything still loads, just without the disk cache.
      _diskCacheProven = false;
    }
  }();
}

/// Test seam: forget the probe result so each test starts from scratch.
@visibleForTesting
void debugResetStatusMediaDiskCache() {
  _diskCacheProven = false;
  _diskCacheProbe = null;
}

ImageProvider<Object>? imageProviderForStatusMediaPath(String mediaPath) {
  final normalizedPath = mediaPath.trim();
  if (normalizedPath.isEmpty) {
    return null;
  }
  if (isBundledStatusMediaPath(normalizedPath)) {
    return AssetImage(resolveBundledStatusMediaPath(normalizedPath));
  }
  if (isRemoteStatusMediaPath(normalizedPath)) {
    // Disk-backed, unlike NetworkImage, whose cache is memory-only and dies
    // with the process -- so a status or chat photo survives an app restart
    // instead of being re-downloaded on every cold open.
    //
    // Only once the cache has proven itself, though: a failing cache must
    // cost a re-download, never a photo that refuses to appear.
    unawaited(ensureStatusMediaDiskCacheReady());
    if (!_diskCacheProven) {
      return NetworkImage(normalizedPath);
    }
    return CachedNetworkImageProvider(
      normalizedPath,
      cacheManager: _statusMediaCacheManager,
    );
  }

  final mediaFile = File(normalizedPath);
  if (!mediaFile.existsSync()) {
    return null;
  }
  return FileImage(mediaFile);
}

VideoPlayerController buildStatusMediaVideoController(String mediaPath) {
  final normalizedPath = mediaPath.trim();
  if (isBundledStatusMediaPath(normalizedPath)) {
    return VideoPlayerController.asset(
      resolveBundledStatusMediaPath(normalizedPath),
    );
  }
  if (isRemoteStatusMediaPath(normalizedPath)) {
    return VideoPlayerController.networkUrl(Uri.parse(normalizedPath));
  }
  return VideoPlayerController.file(File(normalizedPath));
}

/// Video counterpart to [imageProviderForStatusMediaPath].
///
/// Plays a remote video from the disk cache when it is already there --
/// instant, and works offline. On a miss it streams straight away, so a
/// first play never waits for a full download, and pulls the file down in
/// the background so every later play is a cache hit.
///
/// Async only for the cache probe, which resolves in milliseconds; the
/// download itself is never awaited.
Future<VideoPlayerController> buildStatusMediaVideoControllerAsync(
  String mediaPath, {
  BaseCacheManager? cacheManager,
}) async {
  final normalizedPath = mediaPath.trim();
  if (!isRemoteStatusMediaPath(normalizedPath)) {
    return buildStatusMediaVideoController(normalizedPath);
  }

  final manager = cacheManager ?? _statusMediaCacheManager;
  try {
    final cached = await manager.getFileFromCache(normalizedPath);
    final cachedFile = cached?.file;
    if (cachedFile != null && cachedFile.existsSync()) {
      return VideoPlayerController.file(File(cachedFile.path));
    }
  } catch (_) {
    // A cache read must never be the reason a video refuses to play.
  }

  // Miss: stream now, warm for next time. A failed warm is irrelevant --
  // playback is already under way on the network controller returned below.
  unawaited(() async {
    try {
      await manager.downloadFile(normalizedPath);
    } catch (_) {}
  }());

  return VideoPlayerController.networkUrl(Uri.parse(normalizedPath));
}
