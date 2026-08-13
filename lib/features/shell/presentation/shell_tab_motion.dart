import 'package:flutter/material.dart';

/// Shared motion tokens for the floating tab bar and tab content transitions.
///
/// Timings are tuned to feel closer to iOS liquid-glass tab chrome — a soft
/// crossfade between sections and a slightly eased slide for the selection
/// capsule — while using only Flutter primitives so Android gets the same
/// behavior.
abstract final class ShellTabMotion {
  static const selectionDuration = Duration(milliseconds: 340);
  static const iconCrossfadeDuration = Duration(milliseconds: 200);
  static const contentCrossfadeDuration = Duration(milliseconds: 220);
  static const fabTransitionDuration = Duration(milliseconds: 240);

  static const selectionCurve = Curves.easeInOutCubic;
  static const contentCurve = Curves.easeInOut;

  static Duration durationFor(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }
}
