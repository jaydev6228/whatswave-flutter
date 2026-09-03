import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import 'media_transfer.dart';

/// Uploads a device-local file to remote storage and returns a URL any
/// device can read it back from -- the single seam every media-producing
/// feature (chat attachments, status/story media, profile photos) goes
/// through, so none of them need to know Firebase Storage specifically.
abstract class MediaUploader {
  /// [transfer], when given, receives this file's byte progress under
  /// [transferSlot] and aborts the upload the moment it is cancelled --
  /// see [MediaTransfer]. Callers with nothing to show progress on leave
  /// it null and the upload behaves exactly as it always did.
  Future<String> uploadFile(
    File file, {
    required String storagePath,
    String? contentType,
    MediaTransfer? transfer,
    String transferSlot = 'file',
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
    MediaTransfer? transfer,
    String transferSlot = 'file',
  }) async {
    StreamSubscription<TaskSnapshot>? progressSubscription;
    void Function()? cancelListener;
    try {
      final ref = _storage.ref(storagePath);
      // Deliberately not awaited here: `putFile` hands back the UploadTask
      // itself, and that is the only handle that carries byte progress and
      // a real abort. Awaiting it inline (as this used to) throws both
      // away, which is why a cancel could previously only hide the ring
      // while the bytes kept going up.
      final task = ref.putFile(
        file,
        contentType == null ? null : SettableMetadata(contentType: contentType),
      );
      if (transfer != null) {
        progressSubscription = task.snapshotEvents.listen(
          (snapshot) => transfer.report(
            transferSlot,
            transferred: snapshot.bytesTransferred,
            total: snapshot.totalBytes,
          ),
          // The task's own failure surfaces on the awaited future below;
          // an unhandled error on this side stream would additionally
          // crash the zone.
          onError: (Object _) {},
        );
        cancelListener = () {
          if (transfer.isCancelled) {
            unawaited(task.cancel());
          }
        };
        transfer.addListener(cancelListener);
        // A cancel that landed before this listener was attached (a tap
        // during the file-exists check, say) would otherwise upload the
        // whole file anyway.
        cancelListener();
      }
      final snapshot = await task;
      return await snapshot.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      throw MediaUploadException(e.message ?? 'Could not upload that file.');
    } catch (e) {
      // Storage/platform-channel failures don't always surface as a
      // FirebaseException (e.g. a raw PlatformException) -- callers that
      // catch MediaUploadException specifically must still see one.
      throw MediaUploadException('Could not upload that file: $e');
    } finally {
      if (cancelListener != null) {
        transfer?.removeListener(cancelListener);
      }
      await progressSubscription?.cancel();
    }
  }
}
