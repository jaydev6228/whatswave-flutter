import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';

/// Whether what the user is looking at is coming from Firestore's local
/// cache rather than the server -- this app's definition of "offline".
///
/// Deliberately derived from Firestore's own snapshot metadata rather than a
/// network-interface plugin. An interface check reports "online" on a
/// captive portal, a DNS failure, an expired auth token or a Firestore
/// outage -- which are precisely the situations where the user is staring at
/// stale data and most needs telling. `isFromCache` answers the question the
/// UI is actually asking: is this current? It also needs no native plugin.
class BackendReachability extends ChangeNotifier {
  BackendReachability({
    Stream<bool>? servedFromCache,
    this.offlineGracePeriod = const Duration(seconds: 2),
  }) {
    if (servedFromCache != null) {
      _subscription = servedFromCache.listen(
        _handleServedFromCache,
        // A failed listener (rules, auth) is not evidence of being offline,
        // and must never take down the app.
        onError: (Object _) {},
      );
    }
  }

  /// Firestore answers a new listener from cache first and from the server a
  /// moment later, so reacting to the first event would flash an offline
  /// banner on every cold start. Going offline waits this out; coming back
  /// online is applied immediately, because a stale "offline" badge on a
  /// working app is the more annoying error.
  final Duration offlineGracePeriod;

  StreamSubscription<bool>? _subscription;
  Timer? _offlineTimer;
  bool _isOffline = false;

  bool get isOffline => _isOffline;

  void _handleServedFromCache(bool fromCache) {
    if (!fromCache) {
      _offlineTimer?.cancel();
      _offlineTimer = null;
      _setOffline(false);
      return;
    }
    if (_isOffline || _offlineTimer != null) {
      return;
    }
    _offlineTimer = Timer(offlineGracePeriod, () {
      _offlineTimer = null;
      _setOffline(true);
    });
  }

  void _setOffline(bool value) {
    if (_isOffline == value) {
      return;
    }
    _isOffline = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _offlineTimer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

/// The stream [BackendReachability] watches in a Firebase-backed build.
///
/// Follows the signed-in user rather than capturing a uid once: the app
/// builds its shell before auth has necessarily settled, and `asyncExpand`
/// drops the previous listener when the account changes. The watched
/// document does not need to exist -- Firestore reports cache-vs-server
/// metadata for a miss just as it does for a hit.
Stream<bool> firestoreServedFromCache({
  FirebaseFirestore? firestore,
  fb_auth.FirebaseAuth? firebaseAuth,
}) {
  final db = firestore ?? FirebaseFirestore.instance;
  final auth = firebaseAuth ?? fb_auth.FirebaseAuth.instance;
  return auth.authStateChanges().asyncExpand((user) {
    if (user == null) {
      return Stream<bool>.value(false);
    }
    return db
        .collection('userProfiles')
        .doc(user.uid)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) => snapshot.metadata.isFromCache);
  });
}
