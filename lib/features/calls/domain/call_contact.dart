import 'package:flutter/material.dart';

class CallContact {
  const CallContact({
    required this.id,
    required this.name,
    required this.avatarLabel,
    required this.accentColor,
    this.isGroup = false,
    this.photoAssetPath,
    this.avatarUrl,
    this.uid,
    this.memberUids,
    this.memberDisplayNames,
    this.memberAvatarUrls,
  });

  final String id;
  final String name;
  final String avatarLabel;
  final Color accentColor;
  final bool isGroup;
  final String? photoAssetPath;

  /// Uploaded profile photo for a 1:1 contact, when known.
  final String? avatarUrl;

  /// This contact's real Firebase uid, if known -- enables a real 1:1 call
  /// via [CallSignalingService]. Null for local/demo contacts and groups.
  final String? uid;

  /// Other group members to invite (excluding the caller) -- set for group
  /// threads so [CallsController] can start a real multi-party call.
  final List<String>? memberUids;

  /// Optional uid -> display name map for [memberUids] and the host, used by
  /// the in-call participant list during group calls.
  final Map<String, String>? memberDisplayNames;

  /// Optional uid -> profile photo map for group in-call avatars.
  final Map<String, String>? memberAvatarUrls;

  CallContact copyWith({
    String? id,
    String? name,
    String? avatarLabel,
    Color? accentColor,
    bool? isGroup,
    String? photoAssetPath,
    String? avatarUrl,
    String? uid,
    List<String>? memberUids,
    Map<String, String>? memberDisplayNames,
    Map<String, String>? memberAvatarUrls,
  }) {
    return CallContact(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarLabel: avatarLabel ?? this.avatarLabel,
      accentColor: accentColor ?? this.accentColor,
      isGroup: isGroup ?? this.isGroup,
      photoAssetPath: photoAssetPath ?? this.photoAssetPath,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      uid: uid ?? this.uid,
      memberUids: memberUids ?? this.memberUids,
      memberDisplayNames: memberDisplayNames ?? this.memberDisplayNames,
      memberAvatarUrls: memberAvatarUrls ?? this.memberAvatarUrls,
    );
  }
}
