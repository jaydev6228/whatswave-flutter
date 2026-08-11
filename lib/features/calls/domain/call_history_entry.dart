import 'package:flutter/material.dart';

import '../../chats/domain/group_participant.dart';

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

/// WhatsApp-style call log row: incoming, outgoing, or missed only.
enum CallLogDisplayKind { incoming, outgoing, missed }

extension CallHistoryEntryLogDisplay on CallHistoryEntry {
  CallLogDisplayKind get logDisplayKind {
    if (direction == CallDirection.incoming) {
      return switch (status) {
        CallHistoryStatus.missed || CallHistoryStatus.failed =>
          CallLogDisplayKind.missed,
        _ => CallLogDisplayKind.incoming,
      };
    }
    return CallLogDisplayKind.outgoing;
  }

  IconData get logDirectionIcon => switch (logDisplayKind) {
        CallLogDisplayKind.outgoing => Icons.north_east_rounded,
        CallLogDisplayKind.incoming => Icons.south_west_rounded,
        CallLogDisplayKind.missed => Icons.call_missed_outgoing_rounded,
      };
}

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
    this.avatarUrl,
    this.participants,
  });

  final String id;
  final String contactId;
  final String name;
  final String avatarLabel;
  final Color accentColor;

  /// The other party's uploaded profile photo (see
  /// FirebaseAuthRepository.updateAvatar), resolved the same way as their
  /// live name/avatarLabel/accentColor -- see FirestoreCallsRepository.
  final String? avatarUrl;
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

  /// Member snapshots for group calls, used to render the same mosaic avatar
  /// as group threads on the chat list.
  final List<GroupParticipant>? participants;

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
    String? avatarUrl,
    List<GroupParticipant>? participants,
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
      avatarUrl: avatarUrl ?? this.avatarUrl,
      participants: participants ?? this.participants,
    );
  }
}
