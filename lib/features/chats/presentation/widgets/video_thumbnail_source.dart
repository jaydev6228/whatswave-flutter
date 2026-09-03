import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:get_video_thumbnail/get_video_thumbnail.dart';
import 'package:get_video_thumbnail/index.dart' show ImageFormat;
import 'package:video_player/video_player.dart';

import '../../../updates/presentation/widgets/status_media_source.dart';

/// Caches generated video-attachment thumbnails in memory, keyed by the
/// video's path -- a chat bubble tile rebuilds often (typing indicators,
/// reactions on other messages, scroll-driven rebuilds), and regenerating
/// the thumbnail on every one of those would be wasteful and would flicker.
final Map<String, Future<Uint8List?>> _videoThumbnailCache = {};

const _kThumbnailCacheVersion = 'v2';

/// Disk cache key for a generated video-frame JPEG. Separate from the
/// video file itself so a thumb lookup never collides with playback cache.
/// Versioned so an older black first-frame thumb is never reused.
String videoThumbnailDiskCacheKey(String videoPath) {
  return 'video-thumb-$_kThumbnailCacheVersion:${videoPath.trim()}';
}

@visibleForTesting
void debugResetVideoThumbnailCache() {
  _videoThumbnailCache.clear();
}

/// Timestamps to sample when picking a chat/shared-media video thumbnail.
/// Skips the opening stretch where phone recordings are often black while
/// the sensor adjusts, and spreads samples through the middle of the clip.
@visibleForTesting
List<int> videoThumbnailCandidateTimeMs(int? durationMs) {
  if (durationMs == null || durationMs < 800) {
    return const [500, 1500, 2500];
  }
  const sampleCount = 5;
  return List.generate(sampleCount, (index) {
    final fraction = 0.15 + (0.70 * (index + 0.5) / sampleCount);
    return (durationMs * fraction).round().clamp(0, durationMs - 1);
  });
}

/// Average luma of a JPEG thumbnail -- higher means a more visible frame.
@visibleForTesting
Future<double> videoThumbnailLuminanceScore(Uint8List jpegBytes) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(
      jpegBytes,
      targetWidth: 48,
      targetHeight: 48,
    );
    final frame = await codec.getNextFrame();
    image = frame.image;
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      return 0;
    }
    final data = byteData.buffer.asUint8List();
    var sum = 0.0;
    var count = 0;
    for (var i = 0; i + 2 < data.length; i += 4) {
      final r = data[i];
      final g = data[i + 1];
      final b = data[i + 2];
      sum += 0.299 * r + 0.587 * g + 0.114 * b;
      count++;
    }
    return count == 0 ? 0 : sum / count;
  } catch (_) {
    return 0;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

/// A real thumbnail image for a video attachment, generated on-device --
/// works for both a local (not-yet-uploaded) file and a remote Storage
/// download URL, so it's available immediately rather than waiting on any
/// upload/server round-trip. Returns null if generation fails (a bundled
/// demo asset, an unreadable/missing file, an unsupported codec) --
/// callers fall back to a placeholder tile in that case.
///
/// Memory and disk caches are shared by conversation bubbles and the
/// shared-media grid, so one generated frame is never extracted twice.
Future<Uint8List?> videoThumbnailFor(String videoPath) {
  final normalized = videoPath.trim();
  return _videoThumbnailCache.putIfAbsent(
    normalized,
    () => _loadOrGenerate(normalized),
  );
}

Future<Uint8List?> _loadOrGenerate(String videoPath) async {
  if (isBundledStatusMediaPath(videoPath)) {
    // A packaged Flutter asset path (asset://...), not a real
    // filesystem/network path -- the plugin can't read it directly.
    return null;
  }

  final diskKey = videoThumbnailDiskCacheKey(videoPath);
  try {
    await ensureStatusMediaDiskCacheReady();
    final cached = await statusMediaCacheManager.getFileFromCache(diskKey);
    final cachedFile = cached?.file;
    if (cachedFile != null && cachedFile.existsSync()) {
      return cachedFile.readAsBytes();
    }
  } catch (_) {
    // Generation below is the fallback.
  }

  final resolvedPath = await _resolveVideoPathForThumbnail(videoPath);
  if (resolvedPath == null) {
    return null;
  }

  final bytes = await _generateBestThumbnail(resolvedPath);
  if (bytes == null || bytes.isEmpty) {
    return null;
  }

  try {
    await ensureStatusMediaDiskCacheReady();
    await statusMediaCacheManager.putFile(
      diskKey,
      bytes,
      fileExtension: 'jpg',
    );
  } catch (_) {
    // Best-effort -- a missing disk write must cost a re-generate, never
    // a tile that refuses to appear.
  }

  return bytes;
}

Future<Uint8List?> _generateBestThumbnail(String localVideoPath) async {
  final durationMs = await _videoDurationMs(localVideoPath);
  final candidateTimes = videoThumbnailCandidateTimeMs(durationMs);

  final candidates = await Future.wait(
    candidateTimes.map((timeMs) async {
      try {
        final bytes = await VideoThumbnail.thumbnailData(
          video: localVideoPath,
          imageFormat: ImageFormat.JPEG,
          timeMs: timeMs,
          maxWidth: 480,
          quality: 65,
        );
        return bytes;
      } catch (_) {
        return null;
      }
    }),
  );

  Uint8List? bestBytes;
  var bestScore = -1.0;
  for (final bytes in candidates) {
    if (bytes == null || bytes.isEmpty) {
      continue;
    }
    final score = await videoThumbnailLuminanceScore(bytes);
    if (score > bestScore) {
      bestScore = score;
      bestBytes = bytes;
    }
  }
  return bestBytes;
}

Future<int?> _videoDurationMs(String localVideoPath) async {
  VideoPlayerController? controller;
  try {
    controller = VideoPlayerController.file(File(localVideoPath));
    await controller.initialize();
    final durationMs = controller.value.duration.inMilliseconds;
    return durationMs > 0 ? durationMs : null;
  } catch (_) {
    return null;
  } finally {
    await controller?.dispose();
  }
}

/// Local filesystem path the thumbnail plugin can read. Remote URLs reuse
/// the same [statusMediaCacheManager] entry playback uses -- no second
/// copy of the video bytes on disk.
Future<String?> _resolveVideoPathForThumbnail(String videoPath) async {
  if (isRemoteStatusMediaPath(videoPath)) {
    try {
      await ensureStatusMediaDiskCacheReady();
      final cached = await statusMediaCacheManager.getFileFromCache(videoPath);
      final cachedFile = cached?.file;
      if (cachedFile != null && cachedFile.existsSync()) {
        return cachedFile.path;
      }
      final downloaded = await statusMediaCacheManager.downloadFile(videoPath);
      return downloaded.file.path;
    } catch (_) {
      // Some platforms accept the URL directly; others need the catch above.
      return videoPath;
    }
  }

  if (File(videoPath).existsSync()) {
    return videoPath;
  }
  return null;
}
