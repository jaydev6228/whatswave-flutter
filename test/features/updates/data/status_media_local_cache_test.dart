import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/data/status_media_local_cache.dart';

void main() {
  late Directory tempDir;
  late File mediaFile;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('status_media_cache');
    mediaFile = File('${tempDir.path}/capture.jpg')
      ..writeAsBytesSync(<int>[1, 2, 3]);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<StatusMediaLocalCache> cache() async =>
      StatusMediaLocalCache(preferences: await SharedPreferences.getInstance());

  test('remembers a real file and hands it back', () async {
    final subject = await cache();
    await subject.remember('seg-1', mediaFile.path);

    expect(await subject.pathFor('seg-1'), mediaFile.path);
  });

  test('ignores a path that is not a real file on this device', () async {
    final subject = await cache();
    // An https URL or another device's path: nothing to render from disk.
    await subject.remember('seg-1', 'https://example.com/a.jpg');
    await subject.remember('seg-2', '/no/such/file.jpg');

    expect(await subject.pathFor('seg-1'), isNull);
    expect(await subject.pathFor('seg-2'), isNull);
  });

  test('forgets an entry once its file is deleted', () async {
    final subject = await cache();
    await subject.remember('seg-1', mediaFile.path);
    mediaFile.deleteSync();

    expect(await subject.pathFor('seg-1'), isNull);
    // Pruned, not just filtered out of this one read.
    expect(await subject.pathsFor(<String>['seg-1']), isEmpty);
  });

  test('resolves many segments at once, skipping unknown ids', () async {
    final subject = await cache();
    await subject.remember('seg-1', mediaFile.path);

    expect(
      await subject.pathsFor(<String>['seg-1', 'seg-missing']),
      <String, String>{'seg-1': mediaFile.path},
    );
  });

  test('retainOnly drops segments that have expired', () async {
    final subject = await cache();
    final second = File('${tempDir.path}/b.jpg')..writeAsBytesSync(<int>[9]);
    await subject.remember('seg-1', mediaFile.path);
    await subject.remember('seg-2', second.path);

    await subject.retainOnly(<String>{'seg-2'});

    expect(await subject.pathFor('seg-1'), isNull);
    expect(await subject.pathFor('seg-2'), second.path);
  });

  group('StatusStorySegment.displayMediaPath', () {
    StatusStorySegment segment({String? cached}) => StatusStorySegment(
          id: 'seg-1',
          type: StatusStoryType.photo,
          previewText: '',
          localMediaPath: 'https://storage.example.com/seg-1.jpg',
          cachedMediaPath: cached,
        );

    test('prefers the on-device original over the uploaded copy', () {
      expect(segment(cached: '/tmp/capture.jpg').displayMediaPath,
          '/tmp/capture.jpg');
    });

    test('falls back to the shared URL when there is no local original', () {
      expect(
        segment().displayMediaPath,
        'https://storage.example.com/seg-1.jpg',
      );
    });

    test('never enters the shared document', () {
      // A device path is meaningless on anyone else's phone, so it must not
      // round-trip through Firestore.
      final json = segment(cached: '/tmp/capture.jpg').toJson();
      expect(json.containsKey('cachedMediaPath'), isFalse);
      expect(json.values.contains('/tmp/capture.jpg'), isFalse);
    });

    test('decoding a document never yields a cached path', () {
      final decoded = StatusStorySegment.fromJson(
        segment(cached: '/tmp/capture.jpg').toJson(),
      );
      expect(decoded?.cachedMediaPath, isNull);
    });
  });
}
