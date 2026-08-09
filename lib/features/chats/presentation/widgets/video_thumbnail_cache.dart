import 'dart:typed_data';

import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../../../updates/presentation/widgets/status_media_source.dart';

/// Caches generated video-attachment thumbnails in memory, keyed by the
/// video's path -- a chat bubble tile rebuilds often (typing indicators,
/// scroll-driven rebuilds, reactions on other messages), and regenerating
/// the thumbnail on every one of those would be wasteful and would flicker.
final Map<String, Future<Uint8List?>> _videoThumbnailCache = {};

/// A real first-frame-ish thumbnail for a video attachment, or null if one
/// couldn't be generated (a bundled demo asset, an unreadable/missing file,
/// or a native decode failure) -- callers fall back to a placeholder tile
/// in that case, same as a photo attachment with no real file.
Future<Uint8List?> videoThumbnailFor(String videoPath) {
  return _videoThumbnailCache.putIfAbsent(videoPath, () => _generate(videoPath));
}

Future<Uint8List?> _generate(String videoPath) async {
  if (isBundledStatusMediaPath(videoPath)) {
    // A packaged Flutter asset path (asset://...), not a real
    // filesystem/network path -- video_thumbnail can't read it directly.
    return null;
  }
  try {
    return await vt.VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: vt.ImageFormat.JPEG,
      maxWidth: 480,
      quality: 65,
    );
  } catch (_) {
    return null;
  }
}
