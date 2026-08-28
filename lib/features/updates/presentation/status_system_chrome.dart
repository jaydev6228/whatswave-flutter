import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared system-bar handling for the story surfaces.
///
/// Both composers and the viewer are edge-to-edge -- deliberately, because a
/// posted story is edge-to-edge and the composers are previews of it. That
/// puts the OS clock, signal and battery directly on top of whatever the
/// user chose as a background, and nothing in the app used to say how those
/// icons should be drawn, so they inherited the platform default and washed
/// out against mid-tone backgrounds.
///
/// Two things have to hold for them to stay readable on every device:
///
///  1. The icons must be light. `statusBarBrightness` (iOS) and
///     `statusBarIconBrightness` (Android) mean *opposite* things -- iOS
///     describes the background behind the icons, Android describes the
///     icons themselves -- so "light icons" is `Brightness.dark` on iOS and
///     `Brightness.light` on Android. Both live here, set once, because
///     getting one backwards is invisible until somebody runs the other
///     platform.
///  2. Something dark must sit behind them. Light icons are not enough on
///     their own: a text status can be a near-white custom colour and a
///     photo status can be a snow shot. [StatusStoryEdgeScrim] guarantees
///     the contrast rather than hoping the background is dark.
const SystemUiOverlayStyle kStatusStorySystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  // iOS: "the background behind me is dark", which yields white glyphs.
  statusBarBrightness: Brightness.dark,
  // Android: "draw the icons light". Inverted from the line above by design.
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  // Android 10+ paints its own translucent scrim behind transparent system
  // bars unless contrast enforcement is off. Left on, it lays a grey band
  // across the top and bottom of the story.
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: false,
);

/// Applies [kStatusStorySystemUiStyle] for as long as [child] is on screen.
///
/// Declarative on purpose: `SystemChrome.setSystemUIOverlayStyle` is global
/// and imperative, so it survives the pop and leaves the rest of the app
/// with story styling until something else overwrites it. An
/// [AnnotatedRegion] is scoped to the route and reverts on its own.
class StatusStorySystemChrome extends StatelessWidget {
  const StatusStorySystemChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusStorySystemUiStyle,
      child: child,
    );
  }
}

/// A short gradient behind the status bar so the OS icons keep their
/// contrast over any background.
///
/// Sized from the device's own top inset rather than a hardcoded number, so
/// it covers a Dynamic Island, a notch, an Android punch-hole or a tablet's
/// thin bar without a per-device special case, and never darkens more of
/// the story than it has to.
class StatusStoryEdgeScrim extends StatelessWidget {
  const StatusStoryEdgeScrim({super.key});

  /// How far past the status bar the scrim keeps fading, so it reads as a
  /// gradient rather than a band with a visible edge.
  static const double _fadeTail = 44;

  /// Floor for devices that report no top inset at all (some Android
  /// configurations, and landscape on several phones).
  static const double _minimumHeight = 44;

  /// The height this scrim occupies given [context]'s device insets.
  static double heightFor(BuildContext context) {
    // viewPadding, not padding: an open keyboard can zero out `padding`,
    // and the status bar does not move when the keyboard opens.
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return math.max(topInset + _fadeTail, _minimumHeight);
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final height = heightFor(context);
    // Hold most of the darkness across the icons themselves, then release
    // it over the tail.
    final insetStop = (topInset / height).clamp(0.0, 1.0);
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const <Color>[
                Color(0x8A000000),
                Color(0x59000000),
                Color(0x00000000),
              ],
              stops: <double>[0, insetStop, 1],
            ),
          ),
        ),
      ),
    );
  }
}
