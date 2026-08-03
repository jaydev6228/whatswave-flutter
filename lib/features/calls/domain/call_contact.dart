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
  });

  final String id;
  final String name;
  final String avatarLabel;
  final Color accentColor;
  final bool isGroup;
  final String? photoAssetPath;

  /// This contact's real Firebase uid, if known -- enables a real call via
  /// [CallSignalingService]. Null for local/demo contacts, which fall back
  /// to CallsController's simulated call flow.
  final String? uid;

  CallContact copyWith({
    String? id,
    String? name,
    String? avatarLabel,
    Color? accentColor,
    bool? isGroup,
    String? photoAssetPath,
    String? uid,
  }) {
    return CallContact(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarLabel: avatarLabel ?? this.avatarLabel,
      accentColor: accentColor ?? this.accentColor,
      isGroup: isGroup ?? this.isGroup,
      photoAssetPath: photoAssetPath ?? this.photoAssetPath,
      uid: uid ?? this.uid,
    );
  }
}
