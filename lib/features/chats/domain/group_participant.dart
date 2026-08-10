import 'package:flutter/material.dart';

/// One member of a group [ChatThread] -- only ever populated for
/// [ChatThread.isGroup] threads (null/empty for 1:1 chats).
class GroupParticipant {
  const GroupParticipant({
    required this.uid,
    required this.name,
    required this.avatarLabel,
    required this.accentColor,
    this.avatarUrl,
    this.isAdmin = false,
    this.isSelf = false,
  });

  final String uid;
  final String name;
  final String avatarLabel;
  final Color accentColor;
  final String? avatarUrl;
  final bool isAdmin;

  /// True when this participant is whoever is currently viewing the
  /// thread -- resolved identity-relative by the repository (the same
  /// pattern as [ChatMessage.isFromCurrentUser]), so UI never needs its
  /// own notion of "my uid" to know which row is "You" or to gate
  /// admin-only actions against acting on yourself.
  final bool isSelf;

  GroupParticipant copyWith({
    String? name,
    String? avatarLabel,
    Color? accentColor,
    String? avatarUrl,
    bool? isAdmin,
    bool? isSelf,
  }) {
    return GroupParticipant(
      uid: uid,
      name: name ?? this.name,
      avatarLabel: avatarLabel ?? this.avatarLabel,
      accentColor: accentColor ?? this.accentColor,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isAdmin: isAdmin ?? this.isAdmin,
      isSelf: isSelf ?? this.isSelf,
    );
  }
}
