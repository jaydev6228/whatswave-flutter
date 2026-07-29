import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
