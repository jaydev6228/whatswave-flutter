import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_media_source.dart';

/// Records the seeding call so the test can tell "filed under its new URL"
/// from "quietly did nothing".
class _RecordingCacheManager implements BaseCacheManager {
  final List<(String, int)> put = <(String, int)>[];

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async =>
      null;

  @override
  Future<File> putFile(
    String url,
    Uint8List fileBytes, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) async {
    put.add((url, fileBytes.length));
    return const LocalFileSystem().file('/cached/${put.length}.$fileExtension');
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late io.Directory tempDir;
  late io.File sent;
  late _RecordingCacheManager cache;

  setUp(() {
    tempDir = io.Directory.systemTemp.createTempSync('cache_uploaded_test_');
    sent = io.File('${tempDir.path}/sent.jpg')
      ..writeAsBytesSync(List<int>.filled(2048, 7));
    cache = _RecordingCacheManager();
    debugStatusMediaCacheManager = cache;
    debugResetStatusMediaDiskCache();
  });

  tearDown(() {
    debugStatusMediaCacheManager = null;
    debugResetStatusMediaDiskCache();
    tempDir.deleteSync(recursive: true);
  });

  test('a just-uploaded file is filed under the URL it now lives at',
      () async {
    // Media you just sent is already on this device. Until it is in the
    // cache under its new URL, every "do we have this?" check says no --
    // which is what put a download button over a photo this device had
    // just uploaded.
    await cacheUploadedMedia(
      remoteUrl: 'https://example.com/chatMedia/sent.jpg',
      localFile: sent,
    );

    expect(cache.put, hasLength(1));
    expect(cache.put.single.$1, 'https://example.com/chatMedia/sent.jpg');
    expect(cache.put.single.$2, 2048);
  });

  test('a device-local path is not a URL and is left alone', () async {
    await cacheUploadedMedia(remoteUrl: sent.path, localFile: sent);
    expect(cache.put, isEmpty);
  });

  test('a file that has gone missing costs nothing', () async {
    // Best-effort by design: a cache that cannot be written must cost a
    // re-download, never a failed send.
    await cacheUploadedMedia(
      remoteUrl: 'https://example.com/gone.jpg',
      localFile: io.File('${tempDir.path}/gone.jpg'),
    );
    expect(cache.put, isEmpty);
  });
}
