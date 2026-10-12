import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/session/backend_reachability.dart';

void main() {
  late StreamController<bool> servedFromCache;
  late BackendReachability reachability;

  setUp(() {
    servedFromCache = StreamController<bool>();
    reachability = BackendReachability(
      servedFromCache: servedFromCache.stream,
      offlineGracePeriod: const Duration(milliseconds: 20),
    );
    addTearDown(() {
      reachability.dispose();
      servedFromCache.close();
    });
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

  test('starts online rather than accusing the network before it knows',
      () async {
    expect(reachability.isOffline, isFalse);
  });

  test('a cached read does not flag offline immediately', () async {
    // Firestore answers every new listener from cache first, so reacting to
    // the first event would flash the banner on every cold start.
    servedFromCache.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(reachability.isOffline, isFalse);
  });

  test('flags offline once the cached reads persist', () async {
    servedFromCache.add(true);
    await settle();
    expect(reachability.isOffline, isTrue);
  });

  test('a server read inside the grace period cancels the warning', () async {
    servedFromCache.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    servedFromCache.add(false);
    await settle();
    expect(reachability.isOffline, isFalse);
  });

  test('coming back online is applied immediately', () async {
    servedFromCache.add(true);
    await settle();
    expect(reachability.isOffline, isTrue);

    servedFromCache.add(false);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(
      reachability.isOffline,
      isFalse,
      reason: 'a stale offline badge on a working app is the worse error',
    );
  });

  test('notifies only on a real change', () async {
    var notifications = 0;
    reachability.addListener(() => notifications++);

    servedFromCache.add(true);
    await settle();
    servedFromCache.add(true);
    await settle();

    expect(notifications, 1);
  });

  test('a listener error is not treated as being offline', () async {
    // A rules or auth failure on the watched document says nothing about
    // reachability, and must not take the app down either.
    servedFromCache.addError(Exception('permission-denied'));
    await settle();
    expect(reachability.isOffline, isFalse);
  });

  test('dispose stops a pending offline timer from firing', () async {
    // Its own instance: the shared one is disposed by tearDown, and
    // disposing a ChangeNotifier twice throws.
    final controller = StreamController<bool>();
    addTearDown(controller.close);
    final subject = BackendReachability(
      servedFromCache: controller.stream,
      offlineGracePeriod: const Duration(milliseconds: 20),
    );

    controller.add(true);
    subject.dispose();
    await settle();

    // Reaching here at all is the assertion: a surviving Timer would have
    // fired notifyListeners() on a disposed notifier and thrown.
    expect(subject.isOffline, isFalse);
  });
}
