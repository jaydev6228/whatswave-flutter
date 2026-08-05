import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/utils/user_profile_lookup.dart';
import '../domain/call_history_entry.dart';
import '../domain/call_signal.dart';
import 'call_signaling_service.dart';

/// Real cross-device call signaling via a `calls/{callId}` Firestore
/// collection. The room name is just the document id -- LiveKit doesn't
/// need it to mean anything else. See firestore.rules for the matching
/// security rules (only the two participants can read/write a call doc,
/// and identity fields -- including callerName/callerAvatarLabel/
/// callerAccentColorArgb -- can't be changed after creation).
class FirestoreCallSignalingService implements CallSignalingService {
  FirestoreCallSignalingService({
    FirebaseFirestore? firestore,
    fb_auth.FirebaseAuth? firebaseAuth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final fb_auth.FirebaseAuth _firebaseAuth;

  CollectionReference<Map<String, dynamic>> get _calls =>
      _firestore.collection('calls');

  @override
  Future<CallSignal> placeCall({
    required String calleeUid,
    required CallType type,
  }) async {
    final callerUid = _firebaseAuth.currentUser?.uid;
    if (callerUid == null) {
      throw StateError('Must be signed in to place a call.');
    }

    final identity = await _callerIdentity(callerUid);

    final docRef = _calls.doc();
    final now = DateTime.now();
    await docRef.set(<String, Object?>{
      'callerUid': callerUid,
      'calleeUid': calleeUid,
      'roomName': docRef.id,
      'type': type.name,
      'status': CallSignalStatus.ringing.name,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
      'callerName': identity.name,
      'callerAvatarLabel': identity.avatarLabel,
      'callerAccentColorArgb': identity.accentColorArgb,
      'calleeRinging': false,
    });

    return CallSignal(
      id: docRef.id,
      callerUid: callerUid,
      calleeUid: calleeUid,
      roomName: docRef.id,
      type: type,
      status: CallSignalStatus.ringing,
      createdAt: now,
      updatedAt: now,
      callerName: identity.name,
      callerAvatarLabel: identity.avatarLabel,
      callerAccentColorArgb: identity.accentColorArgb,
    );
  }

  /// Resolves the caller's own identity to stamp onto the call doc so the
  /// callee can show a real name/avatar without a live lookup on their
  /// side. Prefers the userProfiles registry -- the same source every
  /// other feature already resolves identity from (see
  /// FirebaseAuthRepository, which keeps it fresh on every sign-in, and
  /// FirestoreChatRepository._threadFromDoc, which reads it the same way).
  /// Falls back to deriving directly from the local Firebase Auth
  /// displayName only if that doc isn't there yet (e.g. a call placed in
  /// the brief window right after signup, before the fire-and-forget
  /// profile publish lands) -- best-effort, never blocks placing the call.
  Future<_CallerIdentity> _callerIdentity(String callerUid) async {
    final profile =
        await UserProfileLookup(firestore: _firestore).fetch(callerUid);
    if (profile != null) {
      return _CallerIdentity(
        name: profile.name,
        avatarLabel: profile.avatarLabel,
        accentColorArgb: profile.accentColorArgb,
      );
    }

    final displayName = _firebaseAuth.currentUser?.displayName?.trim() ?? '';
    if (displayName.isEmpty) {
      return const _CallerIdentity();
    }
    return _CallerIdentity(
      name: displayName,
      avatarLabel: _avatarLabelForName(displayName),
      accentColorArgb: _accentColorForName(displayName).toARGB32(),
    );
  }

  // Same deterministic avatar/color derivation as FirebaseAuthRepository
  // and FakeAuthRepository, so a caller's stamped identity here looks
  // visually consistent with how they appear everywhere else in the app.
  String _avatarLabelForName(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'WW';
    }
    if (parts.length == 1) {
      final clean = parts.first.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      return clean.isEmpty
          ? 'WW'
          : clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Color _accentColorForName(String name) {
    const palette = <Color>[
      AppPalette.emerald,
      AppPalette.green,
      AppPalette.sky,
      AppPalette.purple,
      AppPalette.amber,
    ];
    final hash = name.codeUnits.fold<int>(0, (value, unit) => value + unit);
    return palette[hash % palette.length];
  }

  @override
  Stream<CallSignal?> watchIncomingCall(String myUid) {
    return _calls
        .where('calleeUid', isEqualTo: myUid)
        .where('status', isEqualTo: CallSignalStatus.ringing.name)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return null;
      }
      return _fromDoc(snapshot.docs.first);
    });
  }

  @override
  Stream<CallSignal?> watchCall(String callId) {
    return _calls.doc(callId).snapshots().map((doc) {
      if (!doc.exists) {
        return null;
      }
      return _fromDoc(doc);
    });
  }

  @override
  Future<void> updateStatus(String callId, CallSignalStatus status) async {
    await _calls.doc(callId).update(<String, Object?>{
      'status': status.name,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  @override
  Future<void> markCalleeRinging(String callId) async {
    await _calls.doc(callId).update(<String, Object?>{
      'calleeRinging': true,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  CallSignal _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return CallSignal(
      id: doc.id,
      callerUid: data['callerUid'] as String,
      calleeUid: data['calleeUid'] as String,
      roomName: data['roomName'] as String,
      type: CallType.values.byName(data['type'] as String),
      status: CallSignalStatus.values.byName(data['status'] as String),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      // Nullable on purpose -- an older-shaped call doc (written before
      // this identity-stamping existed) simply won't have these fields,
      // and that must not break watchCall()/watchIncomingCall() for a
      // call already in flight.
      callerName: data['callerName'] as String?,
      callerAvatarLabel: data['callerAvatarLabel'] as String?,
      callerAccentColorArgb: data['callerAccentColorArgb'] as int?,
      calleeRinging: data['calleeRinging'] as bool? ?? false,
    );
  }
}

class _CallerIdentity {
  const _CallerIdentity({
    this.name,
    this.avatarLabel,
    this.accentColorArgb,
  });

  final String? name;
  final String? avatarLabel;
  final int? accentColorArgb;
}
