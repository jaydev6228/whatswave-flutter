import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_media_source.dart';

/// Runs around every test in this suite.
///
/// Media now resolves through a disk cache (see status_media_source.dart),
/// and that cache reaches for `path_provider` and `sqflite` the moment it
/// touches a remote URL. Neither plugin exists in a widget test, so without
/// these stubs any screen showing a remote photo or video blocks on a
/// platform channel that will never answer -- which is what turned a 37s
/// suite into a ten-minute one.
///
/// Stubbing them here rather than per-file means a test never has to know
/// whether the widget it pumps happens to load media.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cacheRoot = Directory.systemTemp.createTempSync('whatswave_test_cache');
  PathProviderPlatform.instance = _TestPathProvider(cacheRoot.path);

  // flutter_cache_manager keeps its index in sqflite. An empty in-memory
  // stand-in is enough: tests assert on which paths are *asked* for, never
  // on cache contents surviving anything.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.tekartik.sqflite'),
    (call) async => switch (call.method) {
      'getDatabasesPath' => cacheRoot.path,
      'openDatabase' => <String, Object?>{'id': 1},
      'query' => <Map<String, Object?>>[],
      _ => null,
    },
  );

  // Every remote image/video resolves through this instead of the real
  // DefaultCacheManager, so nothing in a test ever waits on a download.
  debugStatusMediaCacheManager = _InertCacheManager();

  try {
    await testMain();
  } finally {
    if (cacheRoot.existsSync()) {
      cacheRoot.deleteSync(recursive: true);
    }
  }
}

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;
}

/// Always a miss, never a download.
///
/// A test asserting on caching injects its own manager per call; this one
/// exists so that every *other* test -- which only happens to render a
/// remote avatar or photo -- resolves instantly instead of hanging.
class _InertCacheManager implements BaseCacheManager {
  @override
  Future<FileInfo?> getFileFromCache(String key,
          {bool ignoreMemCache = false}) async =>
      null;

  @override
  Future<FileInfo?> getFileFromMemory(String key) async => null;

  @override
  Stream<FileResponse> getFileStream(String url,
      {String? key, Map<String, String>? headers, bool? withProgress}) {
    // Errors rather than completing empty. An empty stream leaves the image
    // provider waiting on bytes that never arrive and an error that never
    // comes, so the frame stays dirty and pumpAndSettle spins to its
    // ten-minute timeout -- the exact hang this file exists to prevent.
    return Stream<FileResponse>.error(
      HttpExceptionWithStatus(404, 'no network in tests', uri: Uri.parse(url)),
    );
  }

  @override
  Future<void> emptyCache() async {}

  @override
  Future<void> removeFile(String key) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
