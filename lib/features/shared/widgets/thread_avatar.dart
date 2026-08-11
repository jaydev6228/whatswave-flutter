import 'package:flutter/material.dart';

import '../../chats/domain/chat_thread.dart';
import 'avatar_badge.dart';
import 'composite_group_avatar.dart';

/// Resolves the right avatar for a chat thread: uploaded group icon,
/// member mosaic when the group has none, or a single badge for 1:1 chats.
class ThreadAvatar extends StatelessWidget {
  const ThreadAvatar({
    required this.thread,
    this.size = 52,
    super.key,
  });

  final ChatThread thread;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = thread.avatarUrl?.trim();
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return AvatarBadge(
        label: thread.avatarLabel,
        color: thread.accentColor,
        avatarUrl: avatarUrl,
        size: size,
      );
    }

    if (thread.isGroup &&
        thread.participants != null &&
        thread.participants!.isNotEmpty) {
      return CompositeGroupAvatar(
        participants: thread.participants!,
        fallbackLabel: thread.avatarLabel,
        fallbackColor: thread.accentColor,
        size: size,
      );
    }

    return AvatarBadge(
      label: thread.avatarLabel,
      color: thread.accentColor,
      size: size,
    );
  }
}
