import 'package:flutter/material.dart';

import '../../calls/domain/call_history_entry.dart';
import 'avatar_badge.dart';
import 'composite_group_avatar.dart';

/// Resolves the right avatar for a call-history row: uploaded group icon,
/// member mosaic for groups, or a single badge for 1:1 calls -- matching
/// [ThreadAvatar] on the chat list.
class CallHistoryAvatar extends StatelessWidget {
  const CallHistoryAvatar({
    required this.entry,
    this.size = 52,
    super.key,
  });

  final CallHistoryEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = entry.avatarUrl?.trim();
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return AvatarBadge(
        label: entry.avatarLabel,
        color: entry.accentColor,
        avatarUrl: avatarUrl,
        size: size,
      );
    }

    final participants = entry.participants;
    if (entry.isGroup && participants != null && participants.isNotEmpty) {
      return CompositeGroupAvatar(
        participants: participants,
        fallbackLabel: entry.avatarLabel,
        fallbackColor: entry.accentColor,
        size: size,
      );
    }

    return AvatarBadge(
      label: entry.avatarLabel,
      color: entry.accentColor,
      size: size,
    );
  }
}
