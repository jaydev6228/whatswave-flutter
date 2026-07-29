import 'package:flutter/material.dart';

class CallContact {
  const CallContact({
    required this.id,
    required this.name,
    required this.avatarLabel,
    required this.accentColor,
    this.isGroup = false,
    this.photoAssetPath,
  });

  final String id;
  final String name;
  final String avatarLabel;
  final Color accentColor;
  final bool isGroup;
  final String? photoAssetPath;

  CallContact copyWith({
    String? id,
    String? name,
    String? avatarLabel,
    Color? accentColor,
    bool? isGroup,
    String? photoAssetPath,
  }) {
    return CallContact(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarLabel: avatarLabel ?? this.avatarLabel,
      accentColor: accentColor ?? this.accentColor,
      isGroup: isGroup ?? this.isGroup,
      photoAssetPath: photoAssetPath ?? this.photoAssetPath,
    );
  }
}
