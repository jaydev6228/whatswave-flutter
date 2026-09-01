import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file/local.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_media_source.dart';
import 'package:flutter/services.dart';

/// Records what was asked of it so the test can tell a cache hit (plays from
/// disk, downloads nothing) from a miss (streams now, warms in background).
class _FakeCacheManager implements BaseCacheManager {
  _FakeCacheManager({this.hit});

  final File? hit;
  final List<String> probed = <String>[];
  final List<String> downloaded = <String>[];

  @override
  Future<FileInfo?> getFileFromCache(String key,
      {bool ignoreMemCache = false}) async {
    probed.add(key);
    final file = hit;
    if (file == null) {
      return null;
    }
    return FileInfo(
      const LocalFileSystem().file(file.path),
      FileSource.Cache,
      DateTime.now().add(const Duration(days: 1)),
      key,
    );
  }

  @override
  Future<FileInfo> downloadFile(String url,
      {String? key,
      Map<String, String>? authHeaders,
      bool force = false}) async {
    downloaded.add(url);
    throw UnimplementedError('not needed: the warm is fire-and-forget');
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const remote = 'https://storage.example.com/clip.mp4';

  setUp(debugResetStatusMediaDiskCache);

  test(
      'a remote photo resolves to a disk-backed provider once the cache '
      'has proven itself', () async {
    // NetworkImage caches in memory only, so it re-downloads every cold
    // start -- the whole point of the swap.
    await ensureStatusMediaDiskCacheReady();
    final provider = imageProviderForStatusMediaPath(remote);
    expect(provider, isA<CachedNetworkImageProvider>());
  });

  test('an unusable disk cache falls back to plain network loading', () async {
    // The regression this guards: flutter_cache_manager sits on sqflite, and
    // in a build whose native plugins predate that dependency every lookup
    // throws MissingPluginException. The provider swallowed that as a load
    // that never finished and never errored -- a story stuck on its spinner
    // forever. A broken cache must cost a re-download, nothing more.
    debugStatusMediaCacheManager = _BrokenCacheManager();
    addTearDown(() => debugStatusMediaCacheManager = null);

    await ensureStatusMediaDiskCacheReady();
    expect(imageProviderForStatusMediaPath(remote), isA<NetworkImage>());
  });

  test('a local photo still resolves straight off disk', () async {
    final dir = await Directory.systemTemp.createTemp('media_cache');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/a.jpg')..writeAsBytesSync(<int>[1]);

    expect(imageProviderForStatusMediaPath(file.path), isA<FileImage>());
  });

  test('a local video never consults the cache at all', () async {
    final dir = await Directory.systemTemp.createTemp('media_cache');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/a.mp4')..writeAsBytesSync(<int>[1]);
    final manager = _FakeCacheManager();

    final controller = await buildStatusMediaVideoControllerAsync(
      file.path,
      cacheManager: manager,
    );

    expect(controller.dataSourceType, DataSourceType.file);
    expect(manager.probed, isEmpty);
    expect(manager.downloaded, isEmpty);
  });

  test('a remote video miss streams now and warms in the background', () async {
    final manager = _FakeCacheManager();

    final controller = await buildStatusMediaVideoControllerAsync(
      remote,
      cacheManager: manager,
    );

    // Streaming, so a first play never waits on a full download...
    expect(controller.dataSourceType, DataSourceType.network);
    expect(manager.probed, <String>[remote]);
    // ...but the file is pulled down for next time.
    expect(manager.downloaded, <String>[remote]);
  });

  test('a remote video hit plays off disk and downloads nothing', () async {
    final dir = await Directory.systemTemp.createTemp('media_cache');
    addTearDown(() => dir.deleteSync(recursive: true));
    final cached = File('${dir.path}/clip.mp4')..writeAsBytesSync(<int>[1]);
    final manager = _FakeCacheManager(hit: cached);

    final controller = await buildStatusMediaVideoControllerAsync(
      remote,
      cacheManager: manager,
    );

    // Off disk: instant, and it works with no connection at all.
    expect(controller.dataSourceType, DataSourceType.file);
    expect(manager.downloaded, isEmpty);
  });
}

/// Throws the way an unregistered sqflite plugin does.
class _BrokenCacheManager implements BaseCacheManager {
  @override
  Future<FileInfo?> getFileFromCache(String key,
      {bool ignoreMemCache = false}) async {
    throw MissingPluginException(
      'No implementation found for method getDatabasesPath '
      'on channel com.tekartik.sqflite',
    );
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
