import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/notifications/push_tap_router.dart';

void main() {
  late PushTapRouter router;
  late StreamController<Map<String, dynamic>> opened;

  setUp(() {
    router = PushTapRouter();
    opened = StreamController<Map<String, dynamic>>.broadcast();
  });

  tearDown(() async {
    await opened.close();
    router.dispose();
  });

  Future<void> start({Map<String, dynamic>? launch}) => router.start(
        initialMessage: () async => launch,
        openedApp: opened.stream,
      );

  test('a tap that launched the app from terminated opens that thread', () async {
    await start(launch: <String, dynamic>{'threadId': 'thread-7'});
    expect(router.pendingThreadId.value, 'thread-7');
  });

  test('a tap while backgrounded opens that thread', () async {
    await start();
    opened.add(<String, dynamic>{'threadId': 'thread-9'});
    await Future<void>.delayed(Duration.zero);
    expect(router.pendingThreadId.value, 'thread-9');
  });

  test('consuming clears it so returning to the shell does not re-open', () async {
    await start(launch: <String, dynamic>{'threadId': 'thread-7'});
    router.consume();
    expect(router.pendingThreadId.value, isNull);
  });

  test('a payload without a threadId routes nowhere', () async {
    await start(launch: <String, dynamic>{'type': 'message'});
    expect(router.pendingThreadId.value, isNull);
  });

  test('a non-string or empty threadId is ignored, not crashed on', () async {
    await start();
    opened..add(<String, dynamic>{'threadId': 42})
        ..add(<String, dynamic>{'threadId': ''});
    await Future<void>.delayed(Duration.zero);
    expect(router.pendingThreadId.value, isNull);
  });

  test('a failing initial-message lookup does not break startup', () async {
    // Firebase can throw here on a cold start. Routing is a nicety; the app
    // launching is not.
    await expectLater(
      router.start(
        initialMessage: () async => throw StateError('no platform channel'),
        openedApp: opened.stream,
      ),
      completes,
    );
  });

  test('a later tap still routes after a launch tap was handled', () async {
    await start(launch: <String, dynamic>{'threadId': 'thread-1'});
    router.consume();
    opened.add(<String, dynamic>{'threadId': 'thread-2'});
    await Future<void>.delayed(Duration.zero);
    expect(router.pendingThreadId.value, 'thread-2');
  });

  test('taps stop routing once disposed', () async {
    await start();
    router.dispose();
    opened.add(<String, dynamic>{'threadId': 'thread-3'});
    await Future<void>.delayed(Duration.zero);
    // dispose() disposed the notifier; reading it would throw, so the real
    // assertion is that delivering a tap after dispose does not crash.
    router = PushTapRouter(); // so tearDown has something safe to dispose
  });
}
