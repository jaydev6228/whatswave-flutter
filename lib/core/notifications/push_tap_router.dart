import 'dart:async';

import 'package:flutter/foundation.dart';

/// Turns a tapped push notification into "open this thread".
///
/// Deliberately knows nothing about FirebaseMessaging: it consumes plain
/// payload maps, so the whole routing rule is unit-testable without platform
/// channels. [attachFirebaseMessaging] does the adapting.
///
/// There are three ways a notification reaches the app and they are easy to
/// confuse:
///
///  * tapped while the app was **terminated** -- the payload is waiting in
///    `getInitialMessage()` and is delivered exactly once, so missing it
///    means the tap is lost entirely;
///  * tapped while the app was **backgrounded** -- arrives on a stream;
///  * arrived while the app was **foregrounded** -- no tap happened, so
///    there is nothing to route. The user is already looking at the app.
class PushTapRouter {
  PushTapRouter();

  /// The thread a tap asked for, or null. The shell watches this and
  /// navigates, then calls [consume].
  final ValueNotifier<String?> pendingThreadId = ValueNotifier<String?>(null);

  final List<StreamSubscription<Map<String, dynamic>>> _subscriptions =
      <StreamSubscription<Map<String, dynamic>>>[];
  bool _disposed = false;

  /// [initialMessage] is the terminated-launch payload; [openedApp] fires for
  /// every later tap while the process stays alive.
  Future<void> start({
    required Future<Map<String, dynamic>?> Function() initialMessage,
    required Stream<Map<String, dynamic>> openedApp,
  }) async {
    _subscriptions.add(openedApp.listen(_handle));

    // After the subscription, not before: a tap that arrives while this
    // await is in flight would otherwise be dropped.
    try {
      final launch = await initialMessage();
      if (launch != null) {
        _handle(launch);
      }
    } catch (_) {
      // A launch payload we cannot read is not worth failing startup for.
    }
  }

  void _handle(Map<String, dynamic> data) {
    if (_disposed) return;
    final threadId = data['threadId'];
    if (threadId is! String || threadId.isEmpty) {
      // Some other notification type, or a malformed payload. Routing
      // nowhere is correct; the notification still showed.
      return;
    }
    pendingThreadId.value = threadId;
  }

  /// Adds [listener], and calls it straight away if a tap is already
  /// waiting.
  ///
  /// Use this rather than `pendingThreadId.addListener`. A plain
  /// `addListener` fires only on *later* changes, and the
  /// terminated-launch payload is read in main() before any widget exists
  /// -- so attaching a listener from initState silently drops the exact
  /// case this class was written for, and the notification tap lands on
  /// whatever screen the app opens to.
  void addTapListener(VoidCallback listener) {
    pendingThreadId.addListener(listener);
    if (pendingThreadId.value != null) {
      listener();
    }
  }

  void removeTapListener(VoidCallback listener) {
    pendingThreadId.removeListener(listener);
  }

  /// Call once the navigation has happened, so returning to the shell does
  /// not re-open the same thread.
  void consume() {
    pendingThreadId.value = null;
  }

  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    pendingThreadId.dispose();
  }
}

/// Wires a live [FirebaseMessaging] to [router].
///
/// Kept apart from [PushTapRouter] so the routing rules stay testable without
/// platform channels. Call once, after Firebase is initialised and only in a
/// Firebase-backed build.
Future<void> attachFirebaseMessaging(
  PushTapRouter router,
  FirebaseMessagingPushBindings bindings,
) {
  return router.start(
    initialMessage: bindings.getInitialMessage,
    openedApp: bindings.onMessageOpenedApp,
  );
}

/// The two FirebaseMessaging entry points [PushTapRouter] needs, narrowed to
/// plain maps so neither this file nor the tests import firebase_messaging.
class FirebaseMessagingPushBindings {
  const FirebaseMessagingPushBindings({
    required this.getInitialMessage,
    required this.onMessageOpenedApp,
  });

  final Future<Map<String, dynamic>?> Function() getInitialMessage;
  final Stream<Map<String, dynamic>> onMessageOpenedApp;
}
