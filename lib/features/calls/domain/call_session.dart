import 'call_contact.dart';
import 'call_history_entry.dart';

enum CallSessionPhase { incoming, ringing, connecting, connected }

class CallSession {
  const CallSession({
    required this.id,
    required this.contact,
    required this.type,
    required this.direction,
    required this.phase,
    required this.createdAt,
    this.connectedAt,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isLocalVideoEnabled = false,
    this.isFrontCamera = true,
    this.callId,
    this.roomName,
    this.isRemoteRinging = false,
  });

  final String id;
  final CallContact contact;
  final CallType type;
  final CallDirection direction;
  final CallSessionPhase phase;
  final DateTime createdAt;
  final DateTime? connectedAt;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isLocalVideoEnabled;
  final bool isFrontCamera;

  /// True once the callee's device has confirmed it's actually ringing --
  /// only ever meaningful for an outgoing call still in
  /// [CallSessionPhase.ringing] (see CallsController._handleSignalUpdate).
  /// Lets the caller's screen show "Ringing..." instead of "Calling..."
  /// once the other side's phone is really alerting them, not just the
  /// instant the call was placed.
  final bool isRemoteRinging;

  /// The backing CallSignal's id when this is a real call (see
  /// CallSignalingService), null for the local/simulated call flow.
  final String? callId;

  /// LiveKit room to join -- copied from the signal at session start so
  /// group invitees can connect without flipping the whole call doc to
  /// `accepted` (which would cancel everyone else's ringing invite).
  final String? roomName;

  bool get isIncoming => direction == CallDirection.incoming;
  bool get isVideo => type == CallType.video;
  bool get isReal => callId != null;

  int elapsedSeconds(DateTime now) {
    if (connectedAt == null) {
      return 0;
    }
    final seconds = now.difference(connectedAt!).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  CallSession copyWith({
    String? id,
    CallContact? contact,
    CallType? type,
    CallDirection? direction,
    CallSessionPhase? phase,
    DateTime? createdAt,
    DateTime? connectedAt,
    bool setConnectedAt = false,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isLocalVideoEnabled,
    bool? isFrontCamera,
    String? callId,
    String? roomName,
    bool? isRemoteRinging,
  }) {
    return CallSession(
      id: id ?? this.id,
      contact: contact ?? this.contact,
      type: type ?? this.type,
      direction: direction ?? this.direction,
      phase: phase ?? this.phase,
      createdAt: createdAt ?? this.createdAt,
      connectedAt:
          setConnectedAt ? connectedAt : (connectedAt ?? this.connectedAt),
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isLocalVideoEnabled: isLocalVideoEnabled ?? this.isLocalVideoEnabled,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      callId: callId ?? this.callId,
      roomName: roomName ?? this.roomName,
      isRemoteRinging: isRemoteRinging ?? this.isRemoteRinging,
    );
  }
}
