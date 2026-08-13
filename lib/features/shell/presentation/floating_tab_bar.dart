import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../shared/widgets/liquid_glass.dart';
import 'shell_tab_motion.dart';

/// One icon-only destination on [FloatingTabBar]. No text label by design --
/// unlike Material's NavigationDestination, this sidesteps the whole class
/// of "label wraps to 2 lines under a large accessibility text scale"
/// problem this app has had to work around elsewhere (see
/// docs/ui_layout_guidelines.md rule 4) rather than fighting it with a
/// clamp. The semantic label still exists for screen readers via
/// [tooltip].
class FloatingTabDestination {
  const FloatingTabDestination({
    required this.icon,
    required this.selectedIcon,
    required this.tooltip,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String tooltip;
  final int badgeCount;
}

/// A pill-shaped bottom navigation bar that floats above page content with
/// margin on every side, using a frosted "liquid glass" surface (blur +
/// translucency + a thin light-catching edge) in the style of iOS 26's
/// system chrome. The selected destination is shown by a pill-shaped
/// highlight that slides smoothly between items instead of snapping.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final List<FloatingTabDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectionDuration = ShellTabMotion.durationFor(
      context,
      ShellTabMotion.selectionDuration,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LiquidGlassSurface(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / destinations.length;
            final highlightWidth = (itemWidth - 8).clamp(40.0, itemWidth);

            return ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 48,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    AnimatedPositioned(
                      duration: selectionDuration,
                      curve: ShellTabMotion.selectionCurve,
                      left: itemWidth * selectedIndex,
                      top: 0,
                      bottom: 0,
                      width: itemWidth,
                      child: Center(
                        child: Container(
                          width: highlightWidth,
                          height: 40,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var index = 0; index < destinations.length; index++)
                          SizedBox(
                            width: itemWidth,
                            child: _FloatingTabItem(
                              destination: destinations[index],
                              isSelected: index == selectedIndex,
                              onTap: () => onDestinationSelected(index),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FloatingTabItem extends StatelessWidget {
  const _FloatingTabItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final FloatingTabDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = ShellTabMotion.durationFor(
      context,
      ShellTabMotion.iconCrossfadeDuration,
    );
    final selectedColor = theme.colorScheme.onPrimary;
    final unselectedColor = theme.colorScheme.onSurfaceVariant;

    Widget icon = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: isSelected ? 1 : 0),
      duration: duration,
      curve: ShellTabMotion.contentCurve,
      builder: (context, value, _) {
        final iconData =
            value >= 0.5 ? destination.selectedIcon : destination.icon;
        return Transform.scale(
          scale: lerpDouble(0.96, 1, value) ?? 1,
          child: Icon(
            iconData,
            color: Color.lerp(unselectedColor, selectedColor, value),
            size: 22,
          ),
        );
      },
    );
    if (destination.badgeCount > 0) {
      icon = Badge.count(count: destination.badgeCount, child: icon);
    }

    return Tooltip(
      message: destination.tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          splashColor: theme.colorScheme.primary.withValues(alpha: 0.08),
          highlightColor: theme.colorScheme.primary.withValues(alpha: 0.04),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

/// A compose-style FAB meant to float directly above [FloatingTabBar] with
/// standard spacing, right-aligned to match its margin -- the common FAB
/// placement pattern, rather than overlapping the tab bar's own edge.
class FloatingTabBarFab extends StatelessWidget {
  const FloatingTabBarFab({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LiquidGlassIconButton(
      icon: icon,
      tooltip: tooltip,
      onTap: onPressed,
      size: 56,
      iconColor: theme.colorScheme.primary,
    );
  }
}

/// Soft materialisation for the compose FAB when entering/leaving the Chats
/// tab, matching the tab bar's liquid-glass motion language.
class FloatingTabBarFabTransition extends StatelessWidget {
  const FloatingTabBarFabTransition({
    required this.visible,
    required this.child,
    super.key,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = ShellTabMotion.durationFor(
      context,
      ShellTabMotion.fabTransitionDuration,
    );

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      child: visible
          ? KeyedSubtree(
              key: const ValueKey('compose-fab-visible'),
              child: child,
            )
          : const SizedBox.shrink(key: ValueKey('compose-fab-hidden')),
    );
  }
}
