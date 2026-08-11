import 'package:flutter/material.dart';

class CallContact {
  const CallContact({
    required this.id,
    required this.name,
    required this.avatarLabel,
    required this.accentColor,
    this.isGroup = false,
    this.photoAssetPath,
    this.uid,
    this.memberUids,
  });

  final String id;
  final String name;
  final String avatarLabel;
  final Color accentColor;
  final bool isGroup;
  final String? photoAssetPath;

  /// This contact's real Firebase uid, if known -- enables a real 1:1 call
  /// via [CallSignalingService]. Null for local/demo contacts and groups.
  final String? uid;

  /// Other group members to invite (excluding the caller) -- set for group
  /// threads so [CallsController] can start a real multi-party call.
  final List<String>? memberUids;

  CallContact copyWith({
    String? id,
    String? name,
    String? avatarLabel,
    Color? accentColor,
    bool? isGroup,
    String? photoAssetPath,
    String? uid,
    List<String>? memberUids,
  }) {
    return CallContact(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarLabel: avatarLabel ?? this.avatarLabel,
      accentColor: accentColor ?? this.accentColor,
      isGroup: isGroup ?? this.isGroup,
      photoAssetPath: photoAssetPath ?? this.photoAssetPath,
      uid: uid ?? this.uid,
      memberUids: memberUids ?? this.memberUids,
    );
  }
}
