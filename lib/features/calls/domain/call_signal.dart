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
    this.callerName,
    this.callerAvatarLabel,
    this.callerAccentColorArgb,
    this.calleeRinging = false,
  });

  final String id;
  final String callerUid;
  final String calleeUid;
  final CallType type;
  final String roomName;
  final CallSignalStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set once the callee's device has actually surfaced the incoming-call
  /// UI and started ringing -- distinct from [status] staying `ringing`
  /// the whole time the call is outstanding. Lets the caller's screen show
  /// "Ringing..." instead of "Calling..." once it's true. A separate field
  /// rather than a new [CallSignalStatus] value on purpose: watchIncomingCall
  /// filters on `status == ringing`, so folding this into status would make
  /// the callee's own incoming-call query stop matching the instant they
  /// marked themselves as ringing.
  final bool calleeRinging;

  /// The caller's own identity, stamped onto the call doc at placeCall()
  /// time (see FirestoreCallSignalingService) so the callee's incoming-call
  /// UI can show a real name/avatar without a live lookup. Null for local
  /// signaling, older-shaped call docs, or a caller with no published
  /// profile -- callers should fall back to a placeholder identity in that
  /// case (see CallsController._handleIncomingSignal).
  final String? callerName;
  final String? callerAvatarLabel;
  final int? callerAccentColorArgb;

  CallSignal copyWith({
    CallSignalStatus? status,
    DateTime? updatedAt,
    bool? calleeRinging,
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
      callerName: callerName,
      callerAvatarLabel: callerAvatarLabel,
      callerAccentColorArgb: callerAccentColorArgb,
      calleeRinging: calleeRinging ?? this.calleeRinging,
    );
  }
}
