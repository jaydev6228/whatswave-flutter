import 'package:flutter/material.dart';

/// Distance a downward drag must cover before releasing dismisses.
const double kSwipeDismissDistance = 110;

/// Downward flick velocity that dismisses regardless of distance covered.
const double kSwipeDismissVelocity = 700;

/// Drags the child down with the finger and pops the route when the gesture
/// passes [kSwipeDismissDistance] or is flicked faster than
/// [kSwipeDismissVelocity]; otherwise springs it back.
///
/// Full-screen media presentations (a story, a photo/video attachment) are
/// dismissed this way in WhatsApp, Instagram and Photos, and the gesture is
/// the same in all of them -- so it lives here rather than being written
/// once per viewer.
///
/// Vertical-only: horizontal drags are left alone so a viewer that pages
/// sideways between items keeps working, and taps still reach the child
/// because a tap never wins the drag recognizer's arena.
class SwipeDownToDismiss extends StatefulWidget {
  const SwipeDownToDismiss({
    required this.child,
    this.enabled = true,
    this.onDismiss,
    super.key,
  });

  final Widget child;

  /// Set false while something else owns vertical drags (an expanded
  /// caption, a scrolling sheet), so the two never fight over the gesture.
  final bool enabled;

  /// Defaults to popping the enclosing route.
  final VoidCallback? onDismiss;

  @override
  State<SwipeDownToDismiss> createState() => _SwipeDownToDismissState();
}

class _SwipeDownToDismissState extends State<SwipeDownToDismiss> {
  double _offset = 0;

  void _reset() => setState(() => _offset = 0);

  void _handleUpdate(DragUpdateDetails details) {
    // Downward only. Upward drags stay at rest rather than lifting the
    // child off the top of the screen.
    setState(() => _offset = (_offset + details.delta.dy).clamp(0.0, 1e4));
  }

  void _handleEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (_offset >= kSwipeDismissDistance || velocity >= kSwipeDismissVelocity) {
      final onDismiss = widget.onDismiss;
      if (onDismiss != null) {
        onDismiss();
      } else {
        Navigator.of(context).maybePop();
      }
      return;
    }
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    // Fades toward the background as it travels, so the gesture reads as
    // "putting it back" rather than sliding a solid panel off-screen.
    final progress = (_offset / (kSwipeDismissDistance * 2)).clamp(0.0, 1.0);

    return GestureDetector(
      onVerticalDragUpdate: _handleUpdate,
      onVerticalDragEnd: _handleEnd,
      onVerticalDragCancel: _reset,
      child: Transform.translate(
        offset: Offset(0, _offset),
        child: Opacity(opacity: 1 - (progress * 0.6), child: widget.child),
      ),
    );
  }
}
