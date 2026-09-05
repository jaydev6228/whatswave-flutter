import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

import '../../data/status_media_remote_cache_index.dart';

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

/// The same disk cache every remote image/video here resolves through.
///
/// Exposed so a chat bubble can tell "already on this device" from "still
/// only a URL", which is the whole basis of WhatsApp's explicit download
/// affordance -- and so tapping it fills the very cache the image provider
/// then reads back from, rather than a second one of its own.
BaseCacheManager get statusMediaCacheManager => _statusMediaCacheManager;

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

/// [maxDecodeWidth] caps the decoded bitmap, in raw pixels, for a provider
/// that only ever paints a thumbnail.
///
/// Without it a phone-camera JPEG decodes at its full ~12 megapixels into
/// a 125pt bubble tile -- roughly 48MB of ARGB for one thumbnail. A chat
/// scrolled to a couple of albums did that a dozen times over, and the
/// decode work froze the UI thread long enough that the bubbles sat empty
/// and drags on the message list did nothing at all for several seconds
/// after opening the thread.
///
/// Pass null (the default) where the full image is genuinely shown -- the
/// full-screen viewer, the status canvas -- so nothing downsamples an image
/// the reader is actually looking at.
/// Files the freshly-uploaded copy of [localFile] into the shared disk
/// cache under the [remoteUrl] it now lives at.
///
/// Media you just sent is already on this device, so re-fetching it from
/// storage to look at it is pure waste -- and until it is fetched, every
/// "do we have this?" check says no. That is what made a just-uploaded
/// photo render as a placeholder behind a download button.
///
/// Best-effort by design: a cache that cannot be written must cost a
/// re-download, never a failed send.
Future<void> cacheUploadedMedia({
  required String remoteUrl,
  required File localFile,
}) async {
  if (!isRemoteStatusMediaPath(remoteUrl)) {
    return;
  }
  try {
    await ensureStatusMediaDiskCacheReady();
    if (!_diskCacheProven) {
      return;
    }
    await _statusMediaCacheManager.putFile(
      remoteUrl,
      await localFile.readAsBytes(),
      fileExtension: _cacheFileExtension(localFile.path),
    );
    unawaited(rememberRemoteStoryMediaCached(remoteUrl));
  } catch (_) {
    // Deliberately swallowed -- see the doc comment.
  }
}

String _cacheFileExtension(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) {
    return 'file';
  }
  return path.substring(dot + 1);
}

/// The real pixel aspect ratio (width / height) of an encoded image file,
/// or null if it cannot be read.
///
/// Header-only: [ui.ImageDescriptor.encoded] parses the dimensions out of
/// the file's header without decoding a single pixel, so this costs almost
/// nothing even across a sixteen-photo pick.
///
/// Worth doing at pick time because ChatAttachment.aspectRatio otherwise
/// keeps its 1.25 default for every photo ever picked -- so a portrait
/// photo was laid out in a landscape slot and cropped to it, and an album
/// had no way to know whether its photos were tall or wide.
Future<double?> encodedImageAspectRatio(String path) async {
  // Cheaper than letting the engine fail, and load-bearing: an engine call
  // for a file that isn't there is still an engine call, and one made for
  // a path that will never resolve leaves the caller awaiting forever.
  if (path.trim().isEmpty || !File(path).existsSync()) {
    return null;
  }
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromFilePath(path);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final aspect = descriptor.width / descriptor.height;
    return aspect.isFinite && aspect > 0 ? aspect : null;
  } catch (_) {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

ImageProvider<Object>? imageProviderForStatusMediaPath(
  String mediaPath, {
  int? maxDecodeWidth,
}) {
  final provider = _rawImageProviderForStatusMediaPath(mediaPath);
  if (provider == null || maxDecodeWidth == null) {
    return provider;
  }
  // allowUpscaling: false -- a photo already smaller than the budget is
  // left exactly as it is rather than being blown up to meet it.
  return ResizeImage(
    provider,
    width: maxDecodeWidth,
    allowUpscaling: false,
  );
}

ImageProvider<Object>? _rawImageProviderForStatusMediaPath(String mediaPath) {
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
