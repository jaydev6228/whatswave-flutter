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

    final button = LiquidGlassSurface(
      blurred: blurred,
      tintOpacityLight: selected ? 0.78 : 0.56,
      tintOpacityDark: selected ? 0.5 : 0.34,
      color: color,
      borderColor: borderColor,
      shadowColor: shadowColor,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          key: actionKey,
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            // Minimum 48x48dp tap target (docs/ui_layout_guidelines.md
            // rule 7) even when the drawn circle itself is smaller.
            width: size < 48 ? 48 : size,
            height: size < 48 ? 48 : size,
            child: Center(
              child: child ??
                  Icon(icon, size: iconSize ?? size * 0.44, color: resolvedIconColor),
            ),
          ),
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
