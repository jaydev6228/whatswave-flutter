import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/utils/user_profile_lookup.dart';
import '../domain/call_contact.dart';
import '../domain/call_history_entry.dart';
import 'calls_overview.dart';
import 'calls_repository.dart';

/// Firestore-backed [CallsRepository] -- persists real call history so it
/// survives app restarts instead of resetting to demo data every launch.
///
/// Each call produces one history entry PER SIDE: CallsController's
/// _finishSession already runs independently on both the caller's and the
/// callee's own devices (each reacting to the same calls/{callId} status
/// change via its own watchCall subscription) and calls saveHistoryEntry()
/// with its own locally-known direction/contact. So a flat collection with
/// an `ownerUid` field naturally gives each person their own
/// correctly-directioned call log with no extra fan-out logic needed here.
///
/// Favorites are intentionally NOT read from Firestore here -- see
/// CallsController, which derives them from the already-loaded,
/// already-live-synced ChatsController.threads instead of a second,
/// independent read of the same chatThreads collection with its own
/// duplicated identity-resolution logic.
class FirestoreCallsRepository implements CallsRepository {
  FirestoreCallsRepository({
    FirebaseFirestore? firestore,
    fb_auth.FirebaseAuth? firebaseAuth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final fb_auth.FirebaseAuth _firebaseAuth;

  CollectionReference<Map<String, dynamic>> get _historyRef =>
      _firestore.collection('callHistory');

  String get _requireCurrentUid {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null) {
      throw const CallsRepositoryException(
        'Sign in again to load your calls.',
      );
    }
    return uid;
  }

  @override
  Future<CallsOverview> fetchOverview() async {
    return CallsOverview(
      favorites: const <CallContact>[],
      history: await _fetchHistory(),
    );
  }

  // No orderBy here on purpose, matching FirestoreChatRepository's
  // fetchThreads() -- combining where(ownerUid) with orderBy(startedAt)
  // would need a composite index deployed ahead of time. Sorting the
  // (expected to be small, personal) history client-side avoids that.
  Future<List<CallHistoryEntry>> _fetchHistory() async {
    final uid = _requireCurrentUid;
    try {
      final snapshot =
          await _historyRef.where('ownerUid', isEqualTo: uid).get();
      final entries = await Future.wait(snapshot.docs.map(_entryFromDoc));
      entries.sort(
        (left, right) => right.startedAt.compareTo(left.startedAt),
      );
      return List<CallHistoryEntry>.unmodifiable(entries);
    } on FirebaseException catch (e) {
      throw CallsRepositoryException(
        e.message ?? 'Could not load your recent calls.',
      );
    }
  }

  @override
  Future<List<CallHistoryEntry>> saveHistoryEntry(
    CallHistoryEntry entry,
  ) async {
    final uid = _requireCurrentUid;
    try {
      await _historyRef.doc(entry.id).set(<String, Object?>{
        'ownerUid': uid,
        'contactId': entry.contactId,
        'name': entry.name,
        'avatarLabel': entry.avatarLabel,
        'accentColorArgb': entry.accentColor.toARGB32(),
        'startedAt': Timestamp.fromDate(entry.startedAt),
        'type': entry.type.name,
        'direction': entry.direction.name,
        'status': entry.status.name,
        'durationSeconds': entry.durationSeconds,
        'isGroup': entry.isGroup,
        'uid': entry.uid,
      });
    } on FirebaseException catch (e) {
      throw CallsRepositoryException(
        e.message ?? 'We could not update recent calls right now.',
      );
    }
    return _fetchHistory();
  }

  @override
  Future<List<CallHistoryEntry>> deleteHistoryEntry(String entryId) async {
    try {
      await _historyRef.doc(entryId).delete();
    } on FirebaseException catch (e) {
      throw CallsRepositoryException(
        e.message ?? 'We could not delete that call right now.',
      );
    }
    return _fetchHistory();
  }

  @override
  Future<List<CallHistoryEntry>> clearHistory() async {
    final uid = _requireCurrentUid;
    try {
      final snapshot =
          await _historyRef.where('ownerUid', isEqualTo: uid).get();
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      throw CallsRepositoryException(
        e.message ?? 'We could not clear recent calls right now.',
      );
    }
    return const <CallHistoryEntry>[];
  }

  // The name/avatar/color stored on a callHistory doc are a snapshot from
  // whenever that call happened -- if the other party has since renamed
  // themselves in WhatsWave, prefer their current userProfiles identity
  // (keyed by the entry's own uid field) over that frozen snapshot, same
  // as every other feature that shows someone else's identity.
  Future<CallHistoryEntry> _entryFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final uid = data['uid'] as String?;
    final profile = uid == null
        ? null
        : await UserProfileLookup(firestore: _firestore).fetch(uid);
    return CallHistoryEntry(
      id: doc.id,
      contactId: (data['contactId'] as String?) ?? doc.id,
      name: profile?.name ?? (data['name'] as String?) ?? 'WhatsWave user',
      avatarLabel: profile?.avatarLabel ??
          (data['avatarLabel'] as String?) ??
          '?',
      accentColor: Color(
        profile?.accentColorArgb ??
            (data['accentColorArgb'] as int?) ??
            AppPalette.slate.toARGB32(),
      ),
      startedAt: (data['startedAt'] as Timestamp).toDate(),
      type: CallType.values.byName(data['type'] as String),
      direction: CallDirection.values.byName(data['direction'] as String),
      status: CallHistoryStatus.values.byName(data['status'] as String),
      durationSeconds: (data['durationSeconds'] as int?) ?? 0,
      isGroup: (data['isGroup'] as bool?) ?? false,
      avatarUrl: profile?.avatarUrl,
      uid: uid,
    );
  }
}
