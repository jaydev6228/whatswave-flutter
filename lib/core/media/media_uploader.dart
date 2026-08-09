import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

/// Uploads a device-local file to remote storage and returns a URL any
/// device can read it back from -- the single seam every media-producing
/// feature (chat attachments, status/story media, profile photos) goes
/// through, so none of them need to know Firebase Storage specifically.
abstract class MediaUploader {
  Future<String> uploadFile(
    File file, {
    required String storagePath,
    String? contentType,
  });
}

class MediaUploadException implements Exception {
  const MediaUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FirebaseMediaUploader implements MediaUploader {
  FirebaseMediaUploader({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  @override
  Future<String> uploadFile(
    File file, {
    required String storagePath,
    String? contentType,
  }) async {
    try {
      final ref = _storage.ref(storagePath);
      final task = await ref.putFile(
        file,
        contentType == null ? null : SettableMetadata(contentType: contentType),
      );
      return await task.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      throw MediaUploadException(e.message ?? 'Could not upload that file.');
    } catch (e) {
      // Storage/platform-channel failures don't always surface as a
      // FirebaseException (e.g. a raw PlatformException) -- callers that
      // catch MediaUploadException specifically must still see one.
      throw MediaUploadException('Could not upload that file: $e');
    }
  }
}
