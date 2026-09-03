import 'package:flutter/material.dart';

import '../swipe_down_to_dismiss.dart';
import 'liquid_glass.dart';

/// Opens a profile or group icon full screen, with the same chrome the
/// chat's media viewer uses -- a floating close button over a dark canvas,
/// and swipe-down to dismiss.
///
/// Takes a builder rather than an image URL because a group's icon is not
/// an image at all: when no photo is set it is composed on the fly from up
/// to four members' avatars (see CompositeGroupAvatar). Handing the builder
/// a size lets the caller render whatever that thread's icon actually is at
/// whatever size fits, so photos, initials badges and composites all work
/// through one path.
Future<void> showAvatarPreview(
  BuildContext context, {
  required String label,
  required Widget Function(double size) builder,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: label,
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) {
      final media = MediaQuery.sizeOf(context);
      // Square, and bounded by whichever axis runs out first, so a landscape
      // phone does not crop the icon off the top and bottom.
      final size = (media.shortestSide - 64).clamp(120.0, media.height * 0.62);
      return Semantics(
        label: label,
        container: true,
        child: SwipeDownToDismiss(
          key: const Key('avatar_preview_swipe_dismiss'),
          child: Material(
            color: Colors.transparent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: SizedBox.square(
                    dimension: size,
                    child: builder(size),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: LiquidGlassIconButton(
                          key: const Key('avatar_preview_close_button'),
                          icon: Icons.close_rounded,
                          tooltip: 'Close',
                          // A fixed dark glass regardless of app theme --
                          // this floats over the avatar on a near-black
                          // canvas, not over the app's own surface.
                          color: Colors.black.withValues(alpha: 0.42),
                          iconColor: Colors.white,
                          visualSize: 32,
                          iconSize: 18,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
