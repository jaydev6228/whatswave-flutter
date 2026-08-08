import 'package:flutter/material.dart';

/// The colored icon+label backdrop revealed behind a swiped [Dismissible]
/// row (delete, archive, etc). Shared across chats/calls list rows instead
/// of duplicating this per screen.
class SwipeActionBackground extends StatelessWidget {
  const SwipeActionBackground({
    required this.alignment,
    required this.icon,
    required this.label,
    this.color,
    this.foregroundColor,
    super.key,
  });

  final Alignment alignment;
  final IconData icon;
  final String label;
  final Color? color;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = alignment == Alignment.centerLeft
        ? const EdgeInsets.only(left: 22)
        : const EdgeInsets.only(right: 22);
    final resolvedForeground =
        foregroundColor ?? theme.colorScheme.onPrimaryContainer;

    return Container(
      color: (color ?? theme.colorScheme.primaryContainer)
          .withValues(alpha: 0.78),
      alignment: alignment,
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alignment == Alignment.centerRight) ...[
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: resolvedForeground,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Icon(
            icon,
            color: resolvedForeground,
          ),
          if (alignment == Alignment.centerLeft) ...[
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: resolvedForeground,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
