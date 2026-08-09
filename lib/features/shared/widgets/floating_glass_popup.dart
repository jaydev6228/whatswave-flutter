import 'package:flutter/material.dart';

/// Shows a floating glass popup (attachment menu, reaction tray, etc)
/// anchored to some other widget's on-screen position.
///
/// [positionedChildBuilder] must return a [Positioned] using raw
/// screen-space coordinates (i.e. from `RenderBox.localToGlobal`) -- the
/// containing [Stack] here is deliberately NOT wrapped in [SafeArea]. A
/// SafeArea pads its child, which shifts where `Positioned`'s `top`/`left`
/// actually land; since the position was already computed in raw,
/// safe-area-agnostic screen space, wrapping in SafeArea double-shifts it
/// downward by the top inset and makes the popup render further down than
/// intended (this is what caused the attachment menu to visually sit on
/// top of the composer instead of above it).
///
/// Tapping outside the popup dismisses it (`barrierDismissible: true`) --
/// the caller doesn't need to add its own close button. The route below
/// (the composer, the message list) is a separate, inactive route while
/// this is open, so it can't be typed into or tapped through.
Future<T?> showFloatingGlassPopup<T>(
  BuildContext context, {
  required String barrierLabel,
  required Widget Function(BuildContext dialogContext) positionedChildBuilder,
  Alignment scaleAlignment = Alignment.center,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierLabel: barrierLabel,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (dialogContext, _, __) {
      return Stack(
        children: [positionedChildBuilder(dialogContext)],
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
          alignment: scaleAlignment,
          child: child,
        ),
      );
    },
  );
}
