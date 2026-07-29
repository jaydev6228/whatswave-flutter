import 'package:flutter/material.dart';

class AppUser {
  const AppUser({
    required this.name,
    required this.phoneNumber,
    required this.about,
    required this.avatarLabel,
    required this.accentColor,
  });

  final String name;
  final String phoneNumber;
  final String about;
  final String avatarLabel;
  final Color accentColor;

  AppUser copyWith({
    String? name,
    String? phoneNumber,
    String? about,
    String? avatarLabel,
    Color? accentColor,
  }) {
    return AppUser(
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      about: about ?? this.about,
      avatarLabel: avatarLabel ?? this.avatarLabel,
      accentColor: accentColor ?? this.accentColor,
    );
  }
}
