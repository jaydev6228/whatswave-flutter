import 'dart:io';

import 'package:flutter/widgets.dart';
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

ImageProvider<Object>? imageProviderForStatusMediaPath(String mediaPath) {
  final normalizedPath = mediaPath.trim();
  if (normalizedPath.isEmpty) {
    return null;
  }
  if (isBundledStatusMediaPath(normalizedPath)) {
    return AssetImage(resolveBundledStatusMediaPath(normalizedPath));
  }
  if (isRemoteStatusMediaPath(normalizedPath)) {
    return NetworkImage(normalizedPath);
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
