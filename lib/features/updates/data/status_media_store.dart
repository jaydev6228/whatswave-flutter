import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/media/media_uploader.dart';
import '../../../core/models/status_story.dart';
import 'updates_repository.dart';

abstract class StatusMediaStore {
  const StatusMediaStore();

  Future<String> importMedia(
    String sourcePath, {
    required StatusStoryType type,
  });

  Future<void> deleteMedia(Iterable<String> mediaPaths);
}

class LocalStatusMediaStore implements StatusMediaStore {
  const LocalStatusMediaStore();

  @override
  Future<String> importMedia(
    String sourcePath, {
    required StatusStoryType type,
  }) async {
    final normalizedSourcePath = sourcePath.trim();
    if (normalizedSourcePath.isEmpty) {
      throw const UpdatesRepositoryException(
        'Pick a photo or video before sharing that status.',
      );
    }

    final sourceFile = File(normalizedSourcePath);
    if (!await sourceFile.exists()) {
      throw const UpdatesRepositoryException(
        'That media is no longer available on this device.',
      );
    }

    final directory = await _mediaDirectory;
    await directory.create(recursive: true);

    final suffix = switch (type) {
      StatusStoryType.text => 'text',
      StatusStoryType.photo => 'photo',
      StatusStoryType.video => 'video',
    };
    final extension = _normalizedExtensionForPath(
      normalizedSourcePath,
      fallback: switch (type) {
        StatusStoryType.text => '.txt',
        StatusStoryType.photo => '.jpg',
        StatusStoryType.video => '.mp4',
      },
    );
    final filename =
        'status_${DateTime.now().microsecondsSinceEpoch}_$suffix$extension';
    final copiedFile = await sourceFile.copy('${directory.path}/$filename');
    return copiedFile.path;
  }

  @override
  Future<void> deleteMedia(Iterable<String> mediaPaths) async {
    for (final path in mediaPaths) {
      final normalizedPath = path.trim();
      if (normalizedPath.isEmpty) {
        continue;
      }

      final file = File(normalizedPath);
      if (!await file.exists()) {
        continue;
      }

      try {
        await file.delete();
      } catch (_) {
        // Ignore local cleanup failures so status deletion still succeeds.
      }
    }
  }

  Future<Directory> get _mediaDirectory async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return Directory('${documentsDirectory.path}/status_media');
  }

  String _normalizedExtensionForPath(
    String path, {
    required String fallback,
  }) {
    final lastSlash = path.lastIndexOf('/');
    final lastBackslash = path.lastIndexOf(r'\');
    final lastSeparator = lastSlash > lastBackslash ? lastSlash : lastBackslash;
    final filename =
        lastSeparator == -1 ? path : path.substring(lastSeparator + 1);
    final lastDot = filename.lastIndexOf('.');
    if (lastDot <= 0 || lastDot == filename.length - 1) {
      return fallback;
    }

    return filename.substring(lastDot);
  }
}

/// Uploads status/story media to Firebase Storage so it's visible to anyone
/// who can see the story, not just the device that posted it -- the
/// counterpart to [LocalStatusMediaStore], which only ever copies the file
/// into this device's own sandbox. [importMedia] returns a download URL
/// (resolved for rendering by status_media_source.dart, same as a chat
/// attachment's uploaded `localMediaPath`) instead of a local file path.
class FirebaseStatusMediaStore implements StatusMediaStore {
  FirebaseStatusMediaStore({
    MediaUploader? uploader,
    fb_auth.FirebaseAuth? firebaseAuth,
    FirebaseStorage? storage,
    StatusMediaStore? localFallback,
  })  : _uploader = uploader ?? FirebaseMediaUploader(storage: storage),
        _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _localFallback = localFallback ?? const LocalStatusMediaStore();

  final MediaUploader _uploader;
  final fb_auth.FirebaseAuth _firebaseAuth;
  final FirebaseStorage _storage;

  /// Falls back to a plain on-device copy (same as this class's whole
  /// reason for existing not being available) when the Storage upload
  /// itself fails -- best-effort, matching FirestoreChatRepository's
  /// attachment upload: a status is still worth posting even if only the
  /// poster's own device can render its media, rather than blocking the
  /// entire post (including its caption) over a transient upload failure.
  final StatusMediaStore _localFallback;

  @override
  Future<String> importMedia(
    String sourcePath, {
    required StatusStoryType type,
  }) async {
    final normalizedSourcePath = sourcePath.trim();
    if (normalizedSourcePath.isEmpty) {
      throw const UpdatesRepositoryException(
        'Pick a photo or video before sharing that status.',
      );
    }

    final sourceFile = File(normalizedSourcePath);
    if (!await sourceFile.exists()) {
      throw const UpdatesRepositoryException(
        'That media is no longer available on this device.',
      );
    }

    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null) {
      throw const UpdatesRepositoryException(
        'Sign in again before sharing that status.',
      );
    }

    final extension = _normalizedExtensionForPath(
      normalizedSourcePath,
      fallback: type == StatusStoryType.video ? '.mp4' : '.jpg',
    );
    final filename = 'status_${DateTime.now().microsecondsSinceEpoch}$extension';

    try {
      return await _uploader.uploadFile(
        sourceFile,
        storagePath: 'statusMedia/$uid/$filename',
      );
    } catch (e) {
      debugPrint('Status media upload failed, falling back to local: $e');
      return _localFallback.importMedia(normalizedSourcePath, type: type);
    }
  }

  @override
  Future<void> deleteMedia(Iterable<String> mediaPaths) async {
    for (final path in mediaPaths) {
      final normalizedPath = path.trim();
      if (!normalizedPath.startsWith('http://') &&
          !normalizedPath.startsWith('https://')) {
        continue;
      }
      try {
        await _storage.refFromURL(normalizedPath).delete();
      } catch (_) {
        // Best-effort cleanup -- an orphaned Storage object doesn't block
        // the status deletion the caller actually asked for.
      }
    }
  }

  String _normalizedExtensionForPath(
    String path, {
    required String fallback,
  }) {
    final lastSlash = path.lastIndexOf('/');
    final lastBackslash = path.lastIndexOf(r'\');
    final lastSeparator = lastSlash > lastBackslash ? lastSlash : lastBackslash;
    final filename =
        lastSeparator == -1 ? path : path.substring(lastSeparator + 1);
    final lastDot = filename.lastIndexOf('.');
    if (lastDot <= 0 || lastDot == filename.length - 1) {
      return fallback;
    }

    return filename.substring(lastDot);
  }
}
