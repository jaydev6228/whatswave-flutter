import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/chats/presentation/widgets/video_thumbnail_source.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_media_source.dart';

class _RecordingCacheManager implements BaseCacheManager {
  _RecordingCacheManager(this.cacheDir);

  final io.Directory cacheDir;
  final Map<String, Uint8List> files = <String, Uint8List>{};
  final List<String> downloadCalls = <String>[];
  final LocalFileSystem fs = const LocalFileSystem();

  File _fileFor(String key) => fs.file('${cacheDir.path}/${key.hashCode}.jpg');

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    final bytes = files[key];
    if (bytes == null) {
      return null;
    }
    final file = _fileFor(key);
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsBytes(bytes);
    return FileInfo(
      file,
      FileSource.Cache,
      DateTime.now(),
      key,
    );
  }

  @override
  Future<File> putFile(
    String url,
    Uint8List fileBytes, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) async {
    files[url] = fileBytes;
    return const LocalFileSystem().file('/cached/$url.$fileExtension');
  }

  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async {
    downloadCalls.add(url);
    final file = fs.file('${cacheDir.path}/video-${url.hashCode}.mp4');
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsBytes(const <int>[1, 2, 3]);
    return FileInfo(
      file,
      FileSource.Online,
      DateTime.now(),
      url,
    );
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late io.Directory tempDir;
  late _RecordingCacheManager cache;

  setUp(() {
    tempDir = io.Directory.systemTemp.createTempSync('video_thumb_test_');
    cache = _RecordingCacheManager(tempDir);
    debugStatusMediaCacheManager = cache;
    debugResetStatusMediaDiskCache();
    debugResetVideoThumbnailCache();
  });

  tearDown(() {
    debugStatusMediaCacheManager = null;
    debugResetStatusMediaDiskCache();
    debugResetVideoThumbnailCache();
    tempDir.deleteSync(recursive: true);
  });

  test('videoThumbnailDiskCacheKey is separate from the video URL', () {
    const url = 'https://example.com/chat/video.mp4';
    expect(
      videoThumbnailDiskCacheKey(url),
      isNot(equals(url)),
    );
    expect(
      videoThumbnailDiskCacheKey(url),
      'video-thumb-v2:$url',
    );
  });

  test('thumbnail candidates skip the opening black stretch of a clip', () {
    expect(
      videoThumbnailCandidateTimeMs(10000),
      [2200, 3600, 5000, 6400, 7800],
    );
    expect(videoThumbnailCandidateTimeMs(400), [500, 1500, 2500]);
  });

  test('a cached JPEG is read back without downloading the video again',
      () async {
    const url = 'https://example.com/chat/video.mp4';
    final thumbKey = videoThumbnailDiskCacheKey(url);
    cache.files[thumbKey] = Uint8List.fromList(const <int>[9, 8, 7]);

    // Without a real video file the generator would fail; a disk hit must
    // short-circuit before that.
    final bytes = await videoThumbnailFor(url);
    expect(bytes, Uint8List.fromList(const <int>[9, 8, 7]));
    expect(cache.downloadCalls, isEmpty);
  });
}
