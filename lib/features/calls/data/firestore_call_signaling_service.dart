import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import '../domain/call_history_entry.dart';
import '../domain/call_signal.dart';
import 'call_signaling_service.dart';

/// Real cross-device call signaling via a `calls/{callId}` Firestore
/// collection. The room name is just the document id -- LiveKit doesn't
/// need it to mean anything else. See firestore.rules for the matching
/// security rules (only the two participants can read/write a call doc,
/// and identity fields can't be changed after creation).
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
    );
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
    );
  }
}
