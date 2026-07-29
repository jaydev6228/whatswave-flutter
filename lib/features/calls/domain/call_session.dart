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

  bool get isIncoming => direction == CallDirection.incoming;
  bool get isVideo => type == CallType.video;

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
    );
  }
}
