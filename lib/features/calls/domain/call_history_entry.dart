import 'package:flutter/material.dart';

enum CallType { audio, video }

extension CallTypeX on CallType {
  String get label => switch (this) {
        CallType.audio => 'Audio',
        CallType.video => 'Video',
      };

  IconData get icon => switch (this) {
        CallType.audio => Icons.call_rounded,
        CallType.video => Icons.videocam_rounded,
      };
}

enum CallDirection { incoming, outgoing }

enum CallHistoryStatus { completed, missed, declined, canceled, failed }

extension CallHistoryStatusX on CallHistoryStatus {
  String get label => switch (this) {
        CallHistoryStatus.completed => 'Completed',
        CallHistoryStatus.missed => 'Missed',
        CallHistoryStatus.declined => 'Declined',
        CallHistoryStatus.canceled => 'Canceled',
        CallHistoryStatus.failed => 'Failed',
      };

  bool get isAttentionWorthy => switch (this) {
        CallHistoryStatus.missed => true,
        CallHistoryStatus.failed => true,
        _ => false,
      };
}

class CallHistoryEntry {
  const CallHistoryEntry({
    required this.id,
    required this.contactId,
    required this.name,
    required this.avatarLabel,
    required this.accentColor,
    required this.startedAt,
    required this.type,
    required this.direction,
    required this.status,
    this.durationSeconds = 0,
    this.isGroup = false,
    this.uid,
  });

  final String id;
  final String contactId;
  final String name;
  final String avatarLabel;
  final Color accentColor;
  final DateTime startedAt;
  final CallType type;
  final CallDirection direction;
  final CallHistoryStatus status;
  final int durationSeconds;
  final bool isGroup;

  /// The other party's real Firebase uid, if known -- lets redialing from
  /// history (see CallsScreen's recent-calls tap handler) place a real call
  /// instead of silently falling back to the local simulated flow.
  final String? uid;

  CallHistoryEntry copyWith({
    String? id,
    String? contactId,
    String? name,
    String? avatarLabel,
    Color? accentColor,
    DateTime? startedAt,
    CallType? type,
    CallDirection? direction,
    CallHistoryStatus? status,
    int? durationSeconds,
    bool? isGroup,
    String? uid,
  }) {
    return CallHistoryEntry(
      id: id ?? this.id,
      contactId: contactId ?? this.contactId,
      name: name ?? this.name,
      avatarLabel: avatarLabel ?? this.avatarLabel,
      accentColor: accentColor ?? this.accentColor,
      startedAt: startedAt ?? this.startedAt,
      type: type ?? this.type,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isGroup: isGroup ?? this.isGroup,
      uid: uid ?? this.uid,
    );
  }
}
