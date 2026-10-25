import 'package:flutter/material.dart';

abstract final class AppPalette {
  // Darkened from #128C7E, which failed WCAG AA as text: 3.84 against the
  // cloud scaffold background and 4.14 against white, where 4.5 is the
  // minimum for text under 18pt. Because emerald is colorScheme.primary and
  // textButtonTheme sets no foregroundColor, every TextButton in the app
  // inherited it, so this failed app-wide rather than on one screen.
  //
  // #0E7268 gives 5.38 on cloud and 5.79 on white. The nearer candidate
  // #0E7E6F cleared 4.5 by only 0.11, which any later tweak to a surface
  // colour would have undone.
  static const Color emerald = Color(0xFF0E7268);
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
