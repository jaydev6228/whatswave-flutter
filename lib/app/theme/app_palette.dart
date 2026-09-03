import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const Color emerald = Color(0xFF128C7E);
  static const Color green = Color(0xFF25D366);
  static const Color ink = Color(0xFF111B21);
  static const Color deepOcean = Color(0xFF0B141A);
  static const Color cloud = Color(0xFFF5F7F6);
  static const Color mist = Color(0xFFE8F1EE);
  static const Color slate = Color(0xFF667781);
  static const Color sand = Color(0xFFF8F3E8);
  static const Color rose = Color(0xFFE55B5B);
  static const Color amber = Color(0xFFFFC857);
  static const Color sky = Color(0xFF58A6FF);

  /// The blue a read receipt turns.
  ///
  /// Its own colour rather than the app's green: on a sent bubble -- which is
  /// green -- green ticks read as delivered-but-unseen, so "they've seen it"
  /// had no distinct signal at all.
  static const Color readReceipt = Color(0xFF53BDEB);
  static const Color purple = Color(0xFF8C6BFF);

  static const LinearGradient storyGradient = LinearGradient(
    colors: [
      Color(0xFF18A85B),
      Color(0xFF25D366),
      Color(0xFF6DDBB8),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
