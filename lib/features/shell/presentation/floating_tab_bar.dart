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
/// margin on every side, instead of docking flush like Material's
/// NavigationBar. Pairs with [FloatingTabBarFab] for a compose-style action
/// that overlaps its trailing edge on whichever page wants one.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.trailingReservedWidth = 0,
    super.key,
  });

  final List<FloatingTabDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// Extra padding reserved on the trailing edge so the pill's own icons
  /// don't sit underneath an overlapping FAB (see [FloatingTabBarFab]).
  final double trailingReservedWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16 + trailingReservedWidth, 14),
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 6,
        shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.24),
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var index = 0; index < destinations.length; index++)
                _FloatingTabItem(
                  destination: destinations[index],
                  isSelected: index == selectedIndex,
                  onTap: () => onDestinationSelected(index),
                ),
            ],
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
    final icon = Icon(
      isSelected ? destination.selectedIcon : destination.icon,
      color: isSelected
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.onSurfaceVariant,
      size: 22,
    );

    return Tooltip(
      message: destination.tooltip,
      child: Material(
        color: isSelected ? theme.colorScheme.primary : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            // Minimum 48x48dp tap target (docs/ui_layout_guidelines.md
            // rule 7) even though the filled circle drawn inside is
            // visually smaller.
            width: 48,
            height: 48,
            child: Center(
              child: destination.badgeCount > 0
                  ? Badge.count(count: destination.badgeCount, child: icon)
                  : icon,
            ),
          ),
        ),
      ),
    );
  }
}

/// A compose-style FAB meant to sit at the bottom-right corner, overlapping
/// [FloatingTabBar]'s trailing edge (set that bar's trailingReservedWidth to
/// this widget's own footprint so its icons don't sit underneath it).
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
    return Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 14),
      child: FloatingActionButton(
        tooltip: tooltip,
        onPressed: onPressed,
        child: Icon(icon),
      ),
    );
  }
}
