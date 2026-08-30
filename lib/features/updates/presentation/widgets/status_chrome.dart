import 'package:flutter/material.dart';

import '../../../shared/widgets/liquid_glass.dart';

/// The floating chrome button both status composers use.
///
/// Extracted from the media composer so the text composer cannot drift from
/// it: the two screens sit side by side in the same flow, and the text one
/// used plain [IconButton]s, which put bare glyphs straight onto the
/// background with nothing behind them.
///
/// The look is a fixed dark glass circle regardless of app theme -- this
/// floats over the story canvas, not over the system surface, so it has to
/// stay legible whether the rest of the app is light or dark and whatever
/// background or photo the user picked.
class StatusComposerGlassButton extends StatelessWidget {
  const StatusComposerGlassButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.showBorder = true,
    super.key,
  });

  final String tooltip;
  final IconData icon;

  /// Null disables the button, matching [LiquidGlassIconButton].
  final VoidCallback? onTap;

  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassIconButton(
      icon: icon,
      tooltip: tooltip,
      onTap: onTap,
      // 42, matching what the media composer has always used. The tap
      // target still measures 48x48 -- Material expands it -- so this
      // clears the platform minimum (docs/ui_layout_guidelines.md rule 7)
      // without the circle growing.
      size: 42,
      iconSize: 20,
      iconColor: Colors.white,
      color: Colors.black.withValues(alpha: 0.28),
      borderColor: showBorder
          ? Colors.white.withValues(alpha: 0.18)
          : Colors.transparent,
    );
  }
}
