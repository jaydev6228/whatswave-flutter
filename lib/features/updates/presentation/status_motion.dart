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
      // Staggered, not overlapped: the outgoing chrome is gone before the
      // incoming chrome starts.
      //
      // These rows put round buttons in the same corners -- the crop tool's
      // tick sits exactly where the toolbar capsule's last tool does -- so
      // cross-fading them left two different controls superimposed for the
      // whole transition, which reads as a circle blooming over the capsule.
      //
      // One Interval does both halves. The incoming child's animation runs
      // 0 to 1 and so stays invisible until halfway; the outgoing child's
      // runs 1 to 0 through the same mapping and is therefore gone by
      // halfway.
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0.5, 1),
          ),
          child: child,
        );
      },
      // Outgoing chrome fades under the incoming one instead of the two
      // reflowing the layout while both are alive.
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: alignment,
          children: <Widget>[
            // Positioned, so the outgoing child cannot contribute to the
            // Stack's size -- a Stack measures itself against its
            // non-positioned children only. Left unpositioned, a taller
            // outgoing row (e.g. the text tool's) held this Stack 2pt taller
            // for the whole crossfade, pushing every sibling below it down
            // and then snapping them back up when the fade ended. Align
            // keeps the child at its own intrinsic size and in the same spot
            // it occupied before, so only its opacity changes as it leaves.
            for (final previousChild in previousChildren)
              Positioned.fill(
                child: OverflowBox(
                  alignment: alignment,
                  // Height only. Positioned.fill would otherwise squeeze the
                  // departing child into the incoming child's box, so a
                  // taller row visibly collapsed as it faded. Width stays
                  // inherited (null passes the parent's constraint straight
                  // through) because these rows are Rows of buttons, which
                  // cannot lay out unbounded horizontally.
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: previousChild,
                ),
              ),
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: child,
    );
  }
}
