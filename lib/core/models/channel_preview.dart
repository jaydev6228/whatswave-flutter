import 'package:flutter/material.dart';

class ChannelPreview {
  const ChannelPreview({
    required this.id,
    required this.name,
    required this.category,
    required this.followersLabel,
    required this.description,
    required this.avatarLabel,
    required this.accentColor,
    this.isVerified = false,
  });

  final String id;
  final String name;
  final String category;
  final String followersLabel;
  final String description;
  final String avatarLabel;
  final Color accentColor;
  final bool isVerified;

  ChannelPreview copyWith({
    String? id,
    String? name,
    String? category,
    String? followersLabel,
    String? description,
    String? avatarLabel,
    Color? accentColor,
    bool? isVerified,
  }) {
    return ChannelPreview(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      followersLabel: followersLabel ?? this.followersLabel,
      description: description ?? this.description,
      avatarLabel: avatarLabel ?? this.avatarLabel,
      accentColor: accentColor ?? this.accentColor,
      isVerified: isVerified ?? this.isVerified,
    );
  }
}
