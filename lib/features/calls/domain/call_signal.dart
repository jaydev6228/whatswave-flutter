import 'call_history_entry.dart';

enum CallSignalStatus { ringing, accepted, declined, ended }

/// A single call's shared state between two real users, synced through
/// Firestore (see FirestoreCallSignalingService). Distinct from
/// [CallSession], which is local-only UI state -- this is what actually
/// lets one device notify another that a call is happening.
class CallSignal {
  const CallSignal({
    required this.id,
    required this.callerUid,
    required this.calleeUid,
    required this.roomName,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String callerUid;
  final String calleeUid;
  final CallType type;
  final String roomName;
  final CallSignalStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  CallSignal copyWith({
    CallSignalStatus? status,
    DateTime? updatedAt,
  }) {
    return CallSignal(
      id: id,
      callerUid: callerUid,
      calleeUid: calleeUid,
      roomName: roomName,
      type: type,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
