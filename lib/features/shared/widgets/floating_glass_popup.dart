import 'dart:async';

import 'package:flutter/material.dart';

/// Shows a floating glass popup (attachment menu, reaction tray, etc)
/// anchored to some other widget's on-screen position.
///
/// Built on [Overlay] rather than [showGeneralDialog]/[Navigator] --
/// pushing a new route (even a barrier-only dialog with no TextField of
/// its own) shifts the app's primary [FocusScope] to that route, and
/// losing primary focus is exactly what makes the on-screen keyboard
/// dismiss itself. That closed the keyboard the instant this popup opened
/// whenever the composer's TextField had focus, independent of anything
/// else stealing focus explicitly (see LiquidGlassIconButton's
/// canRequestFocus fix for the other, sibling cause of the same
/// symptom). An [OverlayEntry] has no route/focus-scope of its own, so it
/// can render on top of everything without touching who currently holds
/// keyboard focus.
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
/// [close] is handed to the builder so a selection (or a Cancel button)
/// can dismiss the popup and hand back a value -- there's no
/// Navigator route to pop. Tapping the barrier also dismisses it (calling
/// [close] with no value), matching the previous `barrierDismissible`
/// dialog's behavior.
Future<T?> showFloatingGlassPopup<T>(
  BuildContext context, {
  required String barrierLabel,
  required Widget Function(
    BuildContext overlayContext,
    void Function([T? result]) close,
  ) positionedChildBuilder,
  Alignment scaleAlignment = Alignment.center,
}) {
  final overlayState = Overlay.of(context);
  final completer = Completer<T?>();
  final controller = AnimationController(
    vsync: overlayState,
    duration: const Duration(milliseconds: 200),
    reverseDuration: const Duration(milliseconds: 150),
  );
  final curved = CurvedAnimation(parent: controller, curve: Curves.easeOutCubic);

  late OverlayEntry entry;
  var isClosing = false;

  void close([T? result]) {
    if (isClosing) return;
    isClosing = true;
    controller.reverse().whenCompleteOrCancel(() {
      entry.remove();
      controller.dispose();
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    });
  }

  entry = OverlayEntry(
    builder: (overlayContext) {
      return Semantics(
        label: barrierLabel,
        container: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: close,
                child: FadeTransition(
                  opacity: curved,
                  child: Container(color: Colors.black54),
                ),
              ),
            ),
            FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
                alignment: scaleAlignment,
                child: Stack(
                  children: [positionedChildBuilder(overlayContext, close)],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  overlayState.insert(entry);
  controller.forward();

  return completer.future;
}
