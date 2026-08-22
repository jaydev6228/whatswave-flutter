import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/application/status_media_prefetch.dart';

/// Fails every request immediately instead of attempting a real network
/// call -- tests run without network access, and a real NetworkImage/
/// VideoPlayerController.networkUrl request would otherwise hang waiting on
/// a response that never arrives. Matches the pattern already used in
/// avatar_badge_test.dart for the same reason.
class _ThrowingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    throw const SocketException('No network in tests.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

StatusStorySegment _segment({
  required StatusStoryType type,
  String? localMediaPath,
}) {
  return StatusStorySegment(
    id: 'segment-1',
    type: type,
    previewText: 'preview',
    localMediaPath: localMediaPath,
  );
}

void main() {
  group('prefetchStatusMedia', () {
    test('is a no-op for a null segment', () async {
      await expectLater(prefetchStatusMedia(null), completes);
    });

    test('is a no-op for a segment with no media path', () async {
      final segment = _segment(type: StatusStoryType.photo);
      await expectLater(prefetchStatusMedia(segment), completes);
    });

    test('is a no-op for a device-local photo path', () async {
      // The fake/demo backend (LocalStatusMediaStore) only ever produces
      // paths like this -- this guard is what keeps the demo backend from
      // ever attempting a network prefetch at all.
      final segment = _segment(
        type: StatusStoryType.photo,
        localMediaPath: '/local/photo.jpg',
      );
      await expectLater(prefetchStatusMedia(segment), completes);
    });

    test('is a no-op for a text status (no media to prefetch)', () async {
      final segment = _segment(
        type: StatusStoryType.text,
        localMediaPath: 'https://example.com/should-be-ignored.jpg',
      );
      await expectLater(prefetchStatusMedia(segment), completes);
    });

    testWidgets(
        'completes without throwing for a remote photo path, even when the '
        'underlying request fails -- this must never surface as a broken '
        'post', (tester) async {
      await HttpOverrides.runZoned(() async {
        final segment = _segment(
          type: StatusStoryType.photo,
          localMediaPath: 'https://example.com/status-photo.jpg',
        );

        await expectLater(prefetchStatusMedia(segment), completes);
      }, createHttpClient: (context) => _ThrowingHttpClient());
    });
  });
}
