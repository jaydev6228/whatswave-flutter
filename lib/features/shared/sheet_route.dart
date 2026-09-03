import 'package:flutter/material.dart';

import 'widgets/status_motion.dart';

/// A modal route that rises from the bottom like an iOS sheet.
///
/// [MaterialPageRoute] with `fullscreenDialog` only does this on iOS, and
/// pushes sideways everywhere else. Anything the app presents rather than
/// navigates to -- the composers, new chat, a full-screen media viewer --
/// should rise from the bottom on every platform, so that transition lives
/// here instead of being left to the host platform's default.
Route<T> appSheetRoute<T>({
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
