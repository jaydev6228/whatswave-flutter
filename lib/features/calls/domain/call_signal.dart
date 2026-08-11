import 'call_history_entry.dart';

enum CallSignalStatus { ringing, accepted, declined, ended, active }

/// A single call's shared state between real users, synced through
/// Firestore (see FirestoreCallSignalingService). Distinct from
/// [CallSession], which is local-only UI state -- this is what actually
/// lets devices notify each other that a call is happening.
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
    this.isGroup = false,
    this.threadId,
    this.threadName,
    this.participantUids = const <String>[],
    this.participantDisplayNames = const <String, String>{},
  });

  final String id;
  final String callerUid;

  /// The 1:1 callee's uid. Empty for group calls -- use [participantUids].
  final String calleeUid;
  final CallType type;
  final String roomName;
  final CallSignalStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  final bool calleeRinging;
  final String? callerName;
  final String? callerAvatarLabel;
  final int? callerAccentColorArgb;

  /// True when this is a group call -- [participantUids] lists every
  /// invited member except the host ([callerUid]).
  final bool isGroup;
  final String? threadId;
  final String? threadName;
  final List<String> participantUids;
  final Map<String, String> participantDisplayNames;

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
      isGroup: isGroup,
      threadId: threadId,
      threadName: threadName,
      participantUids: participantUids,
      participantDisplayNames: participantDisplayNames,
    );
  }
}
