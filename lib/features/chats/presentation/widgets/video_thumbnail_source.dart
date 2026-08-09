import 'package:firebase_storage/firebase_storage.dart';

/// Caches resolved video-thumbnail download URLs in memory, keyed by the
/// video's own URL -- a chat bubble tile rebuilds often (typing
/// indicators, reactions on other messages, scroll-driven rebuilds), and
/// re-resolving with a real network round-trip on every one of those would
/// be wasteful and would flicker.
final Map<String, Future<String?>> _thumbnailUrlCache = {};

/// Looks up the download URL for a video attachment's server-generated
/// thumbnail (see functions/index.js's generateVideoThumbnail), which lives
/// at a deterministic sibling Storage path -- the video's own path with its
/// extension replaced by `_thumb.jpg`.
///
/// No client-side video-frame-extraction package here could be made to
/// compile on both iOS and Android (video_thumbnail's own Android build
/// depends on the long-dead jcenter() Maven repo), so thumbnail generation
/// happens server-side instead, asynchronously after upload -- this just
/// looks for the result.
///
/// Returns null if the thumbnail doesn't exist yet (the Cloud Function
/// hasn't finished, or never will for a corrupt/unsupported upload) or if
/// [videoUrl] isn't a real Storage download URL yet (a local file path
/// before upload finishes) -- callers fall back to a placeholder tile in
/// either case.
Future<String?> resolveVideoThumbnailUrl(String videoUrl) {
  return _thumbnailUrlCache.putIfAbsent(videoUrl, () => _resolve(videoUrl));
}

Future<String?> _resolve(String videoUrl) async {
  if (!videoUrl.startsWith('http://') && !videoUrl.startsWith('https://')) {
    return null;
  }
  try {
    final videoPath = FirebaseStorage.instance.refFromURL(videoUrl).fullPath;
    final lastDot = videoPath.lastIndexOf('.');
    if (lastDot <= 0) {
      return null;
    }
    final thumbnailPath = '${videoPath.substring(0, lastDot)}_thumb.jpg';
    return await FirebaseStorage.instance.ref(thumbnailPath).getDownloadURL();
  } catch (_) {
    return null;
  }
}
