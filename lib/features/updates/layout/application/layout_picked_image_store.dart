import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Copies gallery picks into app-owned temp files so iOS cannot delete the
/// picker sandbox path while [Image.file] is still decoding it.
class LayoutPickedImageStore {
  const LayoutPickedImageStore();

  /// Returns a stable on-disk path for [sourcePath]. Never throws.
  Future<String> persist(String sourcePath) async {
    final normalized = sourcePath.trim();
    if (normalized.isEmpty) {
      return sourcePath;
    }

    final source = File(normalized);
    if (!source.existsSync()) {
      // Widget tests use fake paths that never exist on disk.
      return normalized;
    }

    try {
      final directory = await getTemporaryDirectory();
      await directory.create(recursive: true);
      final destination = File(
        '${directory.path}/layout_slot_${DateTime.now().microsecondsSinceEpoch}${_extensionFor(normalized)}',
      );
      await source.copy(destination.path);
      return destination.path;
    } catch (_) {
      // If copying fails, still try the picker path rather than aborting.
      return normalized;
    }
  }

  String _extensionFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return '.png';
    }
    if (lower.endsWith('.webp')) {
      return '.webp';
    }
    if (lower.endsWith('.heic')) {
      return '.heic';
    }
    if (lower.endsWith('.heif')) {
      return '.heif';
    }
    return '.jpg';
  }
}
