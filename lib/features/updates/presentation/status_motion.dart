import 'package:flutter/material.dart';

/// Shared motion for the whole status/story feature.
///
/// Every tool in the composer used to swap its chrome in a single frame --
/// tapping crop, draw or blur snapped the toolbar, the trays and the frame
/// outline into place at once, which reads as a glitch rather than a mode
/// change. These constants keep all of it on one timing so the feature
/// moves as a single, calm surface instead of each control animating (or
/// not animating) to its own taste.
///
/// 300ms with an ease-out curve is the platform-standard feel both iOS and
/// WhatsApp use for this kind of in-place change: quick enough to stay
/// responsive, slow enough to be followed by eye.
const Duration kStatusMotionDuration = Duration(milliseconds: 300);

/// Slightly quicker, for small in-place swaps (an icon, a single control)
/// where the full duration would feel sluggish.
const Duration kStatusMotionFastDuration = Duration(milliseconds: 180);

/// Entering: decelerates into place, the way iOS presents.
const Curve kStatusMotionCurve = Curves.easeOutCubic;

/// Leaving: accelerates away, so a dismissal never feels like it lingers.
const Curve kStatusMotionReverseCurve = Curves.easeInCubic;

/// Cross-fades [child] against whatever it replaced, on the shared timing.
///
/// Used for chrome that swaps wholesale between tool modes; the [ValueKey]
/// the caller gives each variant is what tells the switcher a real change
/// happened rather than a rebuild of the same thing.
class StatusModeSwitcher extends StatelessWidget {
  const StatusModeSwitcher({
    required this.child,
    this.alignment = Alignment.center,
    super.key,
  });

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: kStatusMotionDuration,
      switchInCurve: kStatusMotionCurve,
      switchOutCurve: kStatusMotionReverseCurve,
      // Outgoing chrome fades under the incoming one instead of the two
      // reflowing the layout while both are alive.
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: alignment,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: child,
    );
  }
}

/// A modal route that rises from the bottom like an iOS sheet.
///
/// [MaterialPageRoute] with `fullscreenDialog` only does this on iOS; the
/// composers are presentations on every platform, so the transition is
/// defined here rather than left to the host platform's default.
Route<T> statusSheetRoute<T>({
  required WidgetBuilder builder,
  String? name,
}) {
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: name),
    fullscreenDialog: true,
    transitionDuration: kStatusMotionDuration,
    reverseTransitionDuration: kStatusMotionDuration,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final slide = Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: animation,
          curve: kStatusMotionCurve,
          reverseCurve: kStatusMotionReverseCurve,
        ),
      );
      return SlideTransition(
        position: slide,
        // A touch of fade alongside the slide keeps the black composer from
        // reading as a hard wipe over the list behind it.
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: kStatusMotionCurve,
          ),
          child: child,
        ),
      );
    },
  );
}
