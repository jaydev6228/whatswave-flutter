import 'package:flutter/foundation.dart';
import 'package:get_video_thumbnail/get_video_thumbnail.dart';
import 'package:get_video_thumbnail/index.dart' show ImageFormat;

import '../../../updates/presentation/widgets/status_media_source.dart';

/// Caches generated video-attachment thumbnails in memory, keyed by the
/// video's path -- a chat bubble tile rebuilds often (typing indicators,
/// reactions on other messages, scroll-driven rebuilds), and regenerating
/// the thumbnail on every one of those would be wasteful and would flicker.
final Map<String, Future<Uint8List?>> _videoThumbnailCache = {};

/// A real thumbnail image for a video attachment, generated on-device --
/// works for both a local (not-yet-uploaded) file and a remote Storage
/// download URL, so it's available immediately rather than waiting on any
/// upload/server round-trip. Returns null if generation fails (a bundled
/// demo asset, an unreadable/missing file, an unsupported codec) --
/// callers fall back to a placeholder tile in that case.
///
/// Uses get_video_thumbnail (a maintained fork of the original
/// video_thumbnail package): the original's Android build depends on the
/// long-dead jcenter() Maven repo and fails to compile on any current
/// Android Gradle setup, which is also why an earlier, server-side
/// (Cloud Function) version of this feature was replaced with this
/// on-device approach.
Future<Uint8List?> videoThumbnailFor(String videoPath) {
  return _videoThumbnailCache.putIfAbsent(videoPath, () => _generate(videoPath));
}

Future<Uint8List?> _generate(String videoPath) async {
  if (isBundledStatusMediaPath(videoPath)) {
    // A packaged Flutter asset path (asset://...), not a real
    // filesystem/network path -- the plugin can't read it directly.
    return null;
  }
  try {
    return await VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 480,
      quality: 65,
    );
  } catch (_) {
    return null;
  }
}
