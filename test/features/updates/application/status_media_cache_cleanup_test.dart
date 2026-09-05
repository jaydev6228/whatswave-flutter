import 'dart:io';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/application/status_media_cache_cleanup.dart';
import 'package:whatswave/features/updates/application/status_media_prefetch.dart';
import 'package:whatswave/features/updates/data/status_media_local_cache.dart';
import 'package:whatswave/features/updates/data/status_media_remote_cache_index.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_media_source.dart';

class _RecordingCacheManager implements BaseCacheManager {
  _RecordingCacheManager();

  final List<String> removed = <String>[];

  @override
  Future<void> removeFile(String key) async {
    removed.add(key);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

StatusStory _story({
  required String id,
  required List<StatusStorySegment> segments,
  bool isMine = false,
}) {
  return StatusStory(
    id: id,
    name: id,
    avatarLabel: id.substring(0, 1).toUpperCase(),
    accentColor: const Color(0xFF24D56E),
    previewText: 'preview',
    timeLabel: 'now',
    isMine: isMine,
    segments: segments,
    totalSegments: segments.length,
  );
}

StatusStorySegment _segment({
  required String id,
  required String remotePath,
}) {
  return StatusStorySegment(
    id: id,
    type: StatusStoryType.photo,
    previewText: 'preview',
    localMediaPath: remotePath,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugStatusMediaCacheManager = _RecordingCacheManager();
    StatusMediaPrefetchCoordinator.instance.clear();
  });

  tearDown(() {
    debugStatusMediaCacheManager = null;
  });

  test('remoteStoryMediaPaths collects live remote urls', () {
    final paths = remoteStoryMediaPaths([
      _story(
        id: 'a',
        segments: [
          _segment(
            id: 'seg-1',
            remotePath: 'https://cdn.example.com/a.jpg',
          ),
        ],
      ),
    ]);

    expect(paths, {'https://cdn.example.com/a.jpg'});
  });

  test('reconcile evicts indexed orphans on cold start', () async {
    final manager = debugStatusMediaCacheManager! as _RecordingCacheManager;
    final index = StatusMediaRemoteCacheIndex(
      preferences: await SharedPreferences.getInstance(),
    );
    await index.remember('https://cdn.example.com/deleted-while-killed.jpg');

    await reconcileStatusMediaCaches(liveStories: const <StatusStory>[]);

    expect(manager.removed, ['https://cdn.example.com/deleted-while-killed.jpg']);
    expect(await index.readAll(), isEmpty);
  });

  test('reconcile evicts stale remote paths from disk cache', () async {
    final manager = debugStatusMediaCacheManager! as _RecordingCacheManager;

    await reconcileStatusMediaCaches(
      liveStories: const <StatusStory>[],
      explicitlyEvictPaths: <String>['https://cdn.example.com/gone.jpg'],
    );

    expect(manager.removed, ['https://cdn.example.com/gone.jpg']);
  });

  test('reconcile retainOnly drops expired poster-local entries', () async {
    final dir = await Directory.systemTemp.createTemp('status_cache_cleanup');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/capture.jpg')..writeAsBytesSync(<int>[1]);

    final localCache = StatusMediaLocalCache(
      preferences: await SharedPreferences.getInstance(),
    );
    await localCache.remember('expired-seg', file.path);
    await localCache.remember('live-seg', file.path);

    await reconcileStatusMediaCaches(
      liveStories: [
        _story(
          id: 'live',
          segments: [
            _segment(
              id: 'live-seg',
              remotePath: 'https://cdn.example.com/live.jpg',
            ),
          ],
        ),
      ],
    );

    expect(await localCache.pathFor('expired-seg'), isNull);
    expect(await localCache.pathFor('live-seg'), file.path);
  });

  test('prefetch coordinator reconcile completes without throwing', () {
    final live = _story(
      id: 'live',
      segments: [
        _segment(
          id: 'live-seg',
          remotePath: 'https://cdn.example.com/live.jpg',
        ),
      ],
    );

    StatusMediaPrefetchCoordinator.instance.enqueue([
      _segment(
        id: 'deleted-seg',
        remotePath: 'https://cdn.example.com/deleted.jpg',
      ),
      live.segments.first,
    ]);

    expect(() => StatusMediaPrefetchCoordinator.instance.reconcile([live]),
        returnsNormally);
  });

  test('clearAllStatusMediaCaches completes without throwing', () async {
    StatusMediaPrefetchCoordinator.instance.enqueue([
      _segment(
        id: 'seg-1',
        remotePath: 'https://cdn.example.com/a.jpg',
      ),
    ]);

    await expectLater(clearAllStatusMediaCaches(), completes);
  });
}
