import 'dart:ui';

import 'package:flutter/material.dart';

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
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: (isDark ? Colors.black : Colors.white).withValues(
                alpha: isDark ? 0.34 : 0.56,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.68),
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / destinations.length;
                return SizedBox(
                  height: 48,
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        left: itemWidth * selectedIndex,
                        top: 0,
                        bottom: 0,
                        width: itemWidth,
                        child: Center(
                          // A capsule, not a circle, so the highlight's
                          // corners echo the outer pill's own StadiumBorder
                          // instead of clashing with it.
                          child: Container(
                            width: itemWidth - 12,
                            height: 44,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (var index = 0;
                              index < destinations.length;
                              index++)
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
                );
              },
            ),
          ),
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
    Widget icon = Icon(
      isSelected ? destination.selectedIcon : destination.icon,
      color: isSelected
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.onSurfaceVariant,
      size: 22,
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
          child: SizedBox(
            // Minimum 48x48dp tap target (docs/ui_layout_guidelines.md
            // rule 7) even though the filled circle drawn behind it is
            // visually smaller.
            width: 48,
            height: 48,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(
                  key: ValueKey(isSelected),
                  child: icon,
                ),
              ),
            ),
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
    return FloatingActionButton(
      tooltip: tooltip,
      onPressed: onPressed,
      child: Icon(icon),
    );
  }
}
