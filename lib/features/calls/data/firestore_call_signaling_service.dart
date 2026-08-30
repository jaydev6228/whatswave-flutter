import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/utils/user_profile_lookup.dart';
import '../domain/call_history_entry.dart';
import '../domain/call_signal.dart';
import 'call_signaling_service.dart';

/// Real cross-device call signaling via a `calls/{callId}` Firestore
/// collection. Group calls reuse the same shape as 1:1: one call doc per
/// invitee with [CallSignal.calleeUid] set, plus a host doc keyed by the
/// shared LiveKit [CallSignal.roomName].
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

  String _groupInviteCallId({
    required String roomName,
    required String inviteeUid,
  }) =>
      '${roomName}_$inviteeUid';

  @override
  Future<CallSignal> placeCall({
    required String calleeUid,
    required CallType type,
  }) async {
    final callerUid = _requireCallerUid;
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
      if (identity.avatarUrl != null) 'callerAvatarUrl': identity.avatarUrl,
      'callerAccentColorArgb': identity.accentColorArgb,
      'calleeRinging': false,
      'isGroup': false,
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
      callerAvatarUrl: identity.avatarUrl,
      callerAccentColorArgb: identity.accentColorArgb,
    );
  }

  @override
  Future<CallSignal> placeGroupCall({
    required String threadId,
    required String threadName,
    required List<String> participantUids,
    required CallType type,
    Map<String, String>? participantDisplayNames,
    Map<String, String>? participantAvatarUrls,
  }) async {
    final callerUid = _requireCallerUid;
    if (participantUids.isEmpty) {
      throw StateError('A group call needs at least one other member.');
    }

    final identity = await _callerIdentity(callerUid);
    final resolvedDisplayNames = <String, String>{
      ...?participantDisplayNames,
    };
    final resolvedAvatarUrls = <String, String>{
      ...?participantAvatarUrls,
    };
    final hostName = identity.name?.trim();
    if (hostName != null && hostName.isNotEmpty) {
      resolvedDisplayNames[callerUid] = hostName;
    }
    final hostAvatar = identity.avatarUrl?.trim();
    if (hostAvatar != null && hostAvatar.isNotEmpty) {
      resolvedAvatarUrls[callerUid] = hostAvatar;
    }
    final hostRef = _calls.doc();
    final roomName = hostRef.id;
    final now = DateTime.now();
    final sharedFields = <String, Object?>{
      'callerUid': callerUid,
      'roomName': roomName,
      'type': type.name,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
      'callerName': identity.name,
      'callerAvatarLabel': identity.avatarLabel,
      if (identity.avatarUrl != null) 'callerAvatarUrl': identity.avatarUrl,
      'callerAccentColorArgb': identity.accentColorArgb,
      'calleeRinging': false,
      'isGroup': true,
      'threadId': threadId,
      'threadName': threadName,
      'participantUids': participantUids,
      if (resolvedDisplayNames.isNotEmpty)
        'participantDisplayNames': resolvedDisplayNames,
      if (resolvedAvatarUrls.isNotEmpty)
        'participantAvatarUrls': resolvedAvatarUrls,
    };

    // Host session doc -- watched by the caller for end/cancel.
    await hostRef.set(<String, Object?>{
      ...sharedFields,
      'calleeUid': '',
      'status': CallSignalStatus.active.name,
    });

    // One ringing call doc per invitee -- same query path as 1:1 incoming.
    final batch = _firestore.batch();
    for (final inviteeUid in participantUids) {
      final inviteRef = _calls.doc(
        _groupInviteCallId(roomName: roomName, inviteeUid: inviteeUid),
      );
      batch.set(inviteRef, <String, Object?>{
        ...sharedFields,
        'calleeUid': inviteeUid,
        'status': CallSignalStatus.ringing.name,
      });
    }
    await batch.commit();

    return CallSignal(
      id: roomName,
      callerUid: callerUid,
      calleeUid: '',
      roomName: roomName,
      type: type,
      status: CallSignalStatus.active,
      createdAt: now,
      updatedAt: now,
      callerName: identity.name,
      callerAvatarLabel: identity.avatarLabel,
      callerAvatarUrl: identity.avatarUrl,
      callerAccentColorArgb: identity.accentColorArgb,
      isGroup: true,
      threadId: threadId,
      threadName: threadName,
      participantUids: participantUids,
      participantDisplayNames: resolvedDisplayNames,
      participantAvatarUrls: resolvedAvatarUrls,
    );
  }

  String get _requireCallerUid {
    final callerUid = _firebaseAuth.currentUser?.uid;
    if (callerUid == null) {
      throw StateError('Must be signed in to place a call.');
    }
    return callerUid;
  }

  Future<_CallerIdentity> _callerIdentity(String callerUid) async {
    final profile =
        await UserProfileLookup(firestore: _firestore).fetch(callerUid);
    if (profile != null) {
      return _CallerIdentity(
        name: profile.name,
        avatarLabel: profile.avatarLabel,
        avatarUrl: profile.avatarUrl,
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
    if (status == CallSignalStatus.ended) {
      await _endGroupInviteCallsForHost(callId);
    }
  }

  Future<void> _endGroupInviteCallsForHost(String hostCallId) async {
    final hostDoc = await _calls.doc(hostCallId).get();
    if (!hostDoc.exists) {
      return;
    }
    final data = hostDoc.data();
    if (data == null || data['isGroup'] != true) {
      return;
    }

    final roomName = data['roomName'] as String? ?? hostCallId;
    final participantUids = (data['participantUids'] as List<dynamic>?)
            ?.map((entry) => entry.toString())
            .toList(growable: false) ??
        const <String>[];
    if (participantUids.isEmpty) {
      return;
    }

    final now = Timestamp.fromDate(DateTime.now());
    final batch = _firestore.batch();
    for (final inviteeUid in participantUids) {
      final inviteRef = _calls
          .doc(_groupInviteCallId(roomName: roomName, inviteeUid: inviteeUid));
      batch.update(inviteRef, <String, Object?>{
        'status': CallSignalStatus.ended.name,
        'updatedAt': now,
      });
    }
    await batch.commit();
  }

  @override
  Stream<Map<String, CallSignalStatus>> watchGroupInviteStatuses({
    required String roomName,
    required List<String> participantUids,
  }) {
    final controller =
        StreamController<Map<String, CallSignalStatus>>.broadcast();
    final statuses = <String, CallSignalStatus>{};
    final subscriptions =
        <StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>[];

    void emit() {
      if (controller.isClosed) {
        return;
      }
      controller.add(Map<String, CallSignalStatus>.unmodifiable(statuses));
    }

    for (final inviteeUid in participantUids) {
      final subscription = _calls
          .doc(_groupInviteCallId(roomName: roomName, inviteeUid: inviteeUid))
          .snapshots()
          .listen(
        (snapshot) {
          if (!snapshot.exists) {
            statuses.remove(inviteeUid);
          } else {
            final data = snapshot.data()!;
            statuses[inviteeUid] =
                CallSignalStatus.values.byName(data['status'] as String);
          }
          emit();
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Group invite watch failed for $inviteeUid: $error');
        },
      );
      subscriptions.add(subscription);
    }

    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };

    return controller.stream;
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
    final participantUids = (data['participantUids'] as List<dynamic>?)
            ?.map((entry) => entry.toString())
            .toList(growable: false) ??
        const <String>[];
    final participantDisplayNames =
        (data['participantDisplayNames'] as Map<String, dynamic>?)?.map(
              (key, value) => MapEntry(key, value.toString()),
            ) ??
            const <String, String>{};
    final participantAvatarUrls =
        (data['participantAvatarUrls'] as Map<String, dynamic>?)?.map(
              (key, value) => MapEntry(key, value.toString()),
            ) ??
            const <String, String>{};
    return CallSignal(
      id: doc.id,
      callerUid: data['callerUid'] as String,
      calleeUid: data['calleeUid'] as String? ?? '',
      roomName: data['roomName'] as String,
      type: CallType.values.byName(data['type'] as String),
      status: CallSignalStatus.values.byName(data['status'] as String),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      callerName: data['callerName'] as String?,
      callerAvatarLabel: data['callerAvatarLabel'] as String?,
      callerAvatarUrl: data['callerAvatarUrl'] as String?,
      callerAccentColorArgb: data['callerAccentColorArgb'] as int?,
      calleeRinging: data['calleeRinging'] as bool? ?? false,
      isGroup: data['isGroup'] as bool? ?? false,
      threadId: data['threadId'] as String?,
      threadName: data['threadName'] as String?,
      participantUids: participantUids,
      participantDisplayNames: participantDisplayNames,
      participantAvatarUrls: participantAvatarUrls,
    );
  }
}

class _CallerIdentity {
  const _CallerIdentity({
    this.name,
    this.avatarLabel,
    this.avatarUrl,
    this.accentColorArgb,
  });

  final String? name;
  final String? avatarLabel;
  final String? avatarUrl;
  final int? accentColorArgb;
}
