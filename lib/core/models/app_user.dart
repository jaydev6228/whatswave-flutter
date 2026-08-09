import 'package:flutter/material.dart';

class AppUser {
  const AppUser({
    required this.name,
    required this.phoneNumber,
    required this.about,
    required this.avatarLabel,
    required this.accentColor,
    this.avatarUrl,
  });

  final String name;
  final String phoneNumber;
  final String about;
  final String avatarLabel;
  final Color accentColor;

  /// A Firebase Storage download URL for this user's uploaded profile
  /// photo, if they've set one -- null falls back to [avatarLabel]/
  /// [accentColor]'s initials badge everywhere an avatar is shown.
  final String? avatarUrl;

  AppUser copyWith({
    String? name,
    String? phoneNumber,
    String? about,
    String? avatarLabel,
    Color? accentColor,
    String? avatarUrl,
  }) {
    return AppUser(
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      about: about ?? this.about,
      avatarLabel: avatarLabel ?? this.avatarLabel,
      accentColor: accentColor ?? this.accentColor,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
