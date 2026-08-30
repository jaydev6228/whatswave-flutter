import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared "liquid glass" surface decoration (blur + translucency + a thin
/// light-catching edge, in the style of iOS 26's system chrome), extracted
/// from what was previously three divergent one-off implementations
/// ([FloatingTabBar]'s pill, the in-call frosted panel, and the status
/// composer's "glass" button, which was actually just a flat tint with no
/// blur at all). Theme-aware so it looks correct in both light and dark.
///
/// Set [blurred] to false for controls that sit on a flat, single-color
/// surface (e.g. a Settings row) -- there's nothing behind them to blur, so
/// this renders the same tint/border/shadow without the (pointless)
/// [BackdropFilter], matching the surfaces that *can* blur without the
/// unnecessary compositing cost.
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
    this.blurred = true,
    this.blurSigma = 24,
    this.tintOpacityLight = 0.56,
    this.tintOpacityDark = 0.34,
    this.padding,
    this.color,
    this.borderColor,
    this.shadowColor,
    this.showShadow = true,
    super.key,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final bool blurred;
  final double blurSigma;
  final double tintOpacityLight;
  final double tintOpacityDark;
  final EdgeInsetsGeometry? padding;
  final bool showShadow;

  /// Explicit tint override, bypassing the automatic light/dark black-white
  /// pick. For chrome that intentionally stays visually fixed regardless of
  /// the app's theme -- e.g. in-call controls, which float over a dark
  /// video feed rather than the system surface, and must stay legible
  /// there no matter whether the rest of the app is in light or dark mode.
  final Color? color;
  final Color? borderColor;
  final Color? shadowColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ??
            (isDark ? Colors.black : Colors.white).withValues(
              alpha: isDark ? tintOpacityDark : tintOpacityLight,
            ),
        borderRadius: borderRadius,
        border: Border.all(
          color: borderColor ??
              Colors.white.withValues(alpha: isDark ? 0.10 : 0.68),
        ),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: shadowColor ??
                      theme.colorScheme.shadow.withValues(alpha: 0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (!blurred) {
      return ClipRRect(borderRadius: borderRadius, child: decorated);
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: decorated,
      ),
    );
  }
}

/// A circular icon button rendered as a [LiquidGlassSurface]. This is the
/// shared replacement for the app's several hand-rolled "translucent circle
/// with a border" buttons (in-call controls, the status composer's glass
/// button, etc).
class LiquidGlassIconButton extends StatelessWidget {
  const LiquidGlassIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 44,
    this.visualSize,
    this.iconSize,
    this.iconColor,
    this.blurred = true,
    this.selected = false,
    this.actionKey,
    this.color,
    this.borderColor,
    this.shadowColor,
    this.child,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;

  /// When set, the glass circle is drawn at this smaller size while the tap
  /// target -- and the minimum accessible touch area enforced by [size] --
  /// stays unchanged. For chrome that should look visually lighter without
  /// shrinking below the 44x44pt/48x48dp minimum tap target (see
  /// docs/ui_layout_guidelines.md rule 7). Defaults to null, i.e. the glass
  /// circle fills the whole tap target exactly as before.
  final double? visualSize;
  final double? iconSize;
  final Color? iconColor;
  final bool blurred;
  final bool selected;
  final Key? actionKey;

  /// Overrides the drawn [icon] with an arbitrary widget (e.g. a busy-state
  /// spinner) while keeping the same glass circle chrome. Falls back to
  /// [icon] when null.
  final Widget? child;

  /// See [LiquidGlassSurface.color] -- overrides the automatic theme-based
  /// tint for chrome that must stay visually fixed (e.g. in-call controls).
  final Color? color;
  final Color? borderColor;
  final Color? shadowColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedIconColor = iconColor ??
        (selected ? theme.colorScheme.primary : theme.colorScheme.onSurface);

    // Minimum 48x48dp tap target (docs/ui_layout_guidelines.md rule 7) even
    // when the drawn circle itself is smaller.
    final tapSize = size < 48 ? 48.0 : size;
    final drawnSize = visualSize ?? tapSize;

    final glass = LiquidGlassSurface(
      blurred: blurred,
      tintOpacityLight: selected ? 0.78 : 0.56,
      tintOpacityDark: selected ? 0.5 : 0.34,
      color: color,
      borderColor: borderColor,
      shadowColor: shadowColor,
      child: SizedBox(
        width: drawnSize,
        height: drawnSize,
        child: Center(
          child: child ??
              Icon(icon,
                  size: iconSize ?? drawnSize * 0.44, color: resolvedIconColor),
        ),
      ),
    );

    final button = SizedBox(
      // The tap target is always this SizedBox's full size -- the glass
      // circle inside it may be drawn smaller (see [visualSize]) but never
      // shrinks the actual hit region.
      width: tapSize,
      height: tapSize,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          key: actionKey,
          customBorder: const CircleBorder(),
          onTap: onTap,
          // Material's ink-response widgets request keyboard focus on tap
          // by default (so external-keyboard/switch-control users land on
          // whatever was just activated) -- but every use of this button is
          // a momentary icon action, never something meant to hold focus,
          // and several sit right next to a TextField (e.g. the composer's
          // attachment button). Left at its default, tapping one silently
          // steals focus from that TextField and dismisses the keyboard,
          // which is what made the attachment popup's position -- anchored
          // to the composer's keyboard-open location -- go stale the moment
          // the keyboard closed underneath it. Buttons stay fully usable by
          // touch and screen readers either way; only keyboard/switch-
          // control tab traversal skips them, an acceptable tradeoff for an
          // icon-only action button.
          canRequestFocus: false,
          child: Center(child: glass),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// A capsule filter chip rendered with the same border/tint language as
/// [LiquidGlassSurface], replacing the app's two byte-for-byte-identical
/// `_ChatFilterChip`/`_CompactCommunitiesChip` implementations.
class LiquidGlassChip extends StatelessWidget {
  const LiquidGlassChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.blurred = false,
    super.key,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool blurred;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.14)
              : (isDark ? Colors.white : Colors.black).withValues(
                  alpha: isDark ? 0.06 : 0.035,
                ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.32)
                : colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(alpha: 0.64),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// A frosted liquid-glass popup anchored right next to the button that
/// opened it -- a "tooltip bubble" in place of Material's [showMenu] or a
/// full-height modal sheet, for any picker/menu that should feel like it
/// belongs to the app's own floating glass chrome. Pass the tapped
/// button's own [BuildContext] (e.g. via a [Builder] wrapping just that
/// button) as [anchorContext] so the bubble lands precisely at it rather
/// than the whole enclosing widget.
Future<T?> showLiquidGlassBubbleMenu<T>({
  required BuildContext anchorContext,
  required List<Widget> Function(BuildContext context) itemBuilder,

  /// True opens the bubble growing downward from the button's bottom edge
  /// (for a button near the top of the screen); false (the default) grows
  /// upward from the button's top edge (for a button near the bottom).
  bool openBelow = false,
}) {
  final anchorBox = anchorContext.findRenderObject()! as RenderBox;
  final overlayBox =
      Overlay.of(anchorContext).context.findRenderObject()! as RenderBox;
  final anchorTopLeft =
      anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
  final anchorSize = anchorBox.size;
  final screenSize = overlayBox.size;

  // Anchoring purely from the right edge (as if every button lived in the
  // bottom-right) starved the bubble of width whenever the real button sat
  // near the left instead -- the padding meant to clear the button ate
  // almost the whole screen, squeezing the content into a sliver. Anchor
  // from whichever horizontal edge is actually closer to the button.
  final anchorsLeftHalf =
      (anchorTopLeft.dx + anchorSize.width / 2) < screenSize.width / 2;
  final leftInset = anchorTopLeft.dx.clamp(12.0, screenSize.width - 12);
  final rightInset = (screenSize.width - anchorTopLeft.dx - anchorSize.width)
      .clamp(12.0, screenSize.width - 12);
  final alignment = Alignment(
    anchorsLeftHalf ? -1 : 1,
    openBelow ? -1 : 1,
  );
  final verticalInset = openBelow
      ? (anchorTopLeft.dy + anchorSize.height + 10)
          .clamp(12.0, screenSize.height - 12)
      : (screenSize.height - anchorTopLeft.dy + 10)
          .clamp(12.0, screenSize.height - 12);
  final padding = EdgeInsets.only(
    left: anchorsLeftHalf ? leftInset : 0,
    right: anchorsLeftHalf ? 0 : rightInset,
    top: openBelow ? verticalInset : 0,
    bottom: openBelow ? 0 : verticalInset,
  );

  return showGeneralDialog<T>(
    context: anchorContext,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Align(
        alignment: alignment,
        child: Padding(
          padding: padding,
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
              alignment: alignment,
              child: LiquidGlassSurface(
                borderRadius: BorderRadius.circular(18),
                blurSigma: 22,
                color: Colors.black.withValues(alpha: 0.5),
                borderColor: Colors.white.withValues(alpha: 0.16),
                child: Material(
                  type: MaterialType.transparency,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxHeight: 320, minWidth: 168),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      // Shrink-wraps the bubble to its widest item's own
                      // natural width -- without this, the Column below
                      // (needed so each item's Row can *stretch* to match
                      // it, instead of centering under it) would otherwise
                      // just take all the width this unbounded-ish parent
                      // is willing to hand out, ballooning out toward the
                      // screen edge instead of hugging the label text.
                      child: IntrinsicWidth(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: itemBuilder(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// One selectable row inside a [showLiquidGlassBubbleMenu] popup.
class LiquidGlassBubbleItem extends StatelessWidget {
  const LiquidGlassBubbleItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        // Fills the row the stretched Column gave it (not just its own
        // content width) so the icon+label always start flush against the
        // left edge, and the trailing checkmark (when selected) still
        // pins to the right instead of hugging the label.
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
            if (selected) ...[
              const Spacer(),
              const Icon(Icons.check_rounded, color: Colors.white, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/// The app's dialog, on the same glass as its sheets.
///
/// A drop-in for [AlertDialog]'s `title`/`content`/`actions` -- every
/// dialog in this app uses exactly those three, so converting is a rename.
///
/// [DialogTheme] can carry the shape, the border and the elevation, but it
/// cannot add a [BackdropFilter], so a themed [AlertDialog] stays an opaque
/// panel. This is the piece the theme could not express.
///
/// Tinted lightly enough that the blur actually reads. At sheet weight
/// (0.86) the fill was so close to opaque that the glass was invisible --
/// it looked like a flat panel with rounded corners. The blur is what
/// keeps the text legible at this opacity.
class LiquidGlassDialog extends StatelessWidget {
  const LiquidGlassDialog({
    this.title,
    this.content,
    this.actions,
    super.key,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogActions = actions;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      // Matches AlertDialog's own inset so converted dialogs keep their
      // position and width on every screen size.
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: LiquidGlassSurface(
        borderRadius: const BorderRadius.all(Radius.circular(28)),
        blurSigma: 30,
        tintOpacityDark: 0.62,
        tintOpacityLight: 0.78,
        showShadow: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                DefaultTextStyle(
                  style: theme.textTheme.headlineSmall!.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                  child: title!,
                ),
              if (title != null && content != null) const SizedBox(height: 14),
              if (content != null)
                Flexible(
                  // Long copy scrolls rather than pushing the actions off
                  // the screen -- AlertDialog's own `scrollable` behaviour.
                  child: SingleChildScrollView(
                    child: DefaultTextStyle(
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      child: content!,
                    ),
                  ),
                ),
              if (dialogActions != null && dialogActions.isNotEmpty) ...[
                const SizedBox(height: 10),
                // Wrap, not Row: at large text scales a pair of buttons can
                // outgrow the dialog's width (docs/ui_layout_guidelines.md
                // rule 6).
                Align(
                  alignment: Alignment.centerRight,
                  // Themed for this subtree rather than per action, so the
                  // dozen-odd dialogs keep their plain TextButton and
                  // FilledButton children and still get capsules.
                  child: TextButtonTheme(
                    data: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        shape: const StadiumBorder(),
                        backgroundColor:
                            theme.colorScheme.onSurface.withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                    child: FilledButtonTheme(
                      data: FilledButtonThemeData(
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 4,
                        children: dialogActions,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
