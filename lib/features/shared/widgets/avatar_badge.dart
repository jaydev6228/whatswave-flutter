import 'package:flutter/material.dart';

class AvatarBadge extends StatelessWidget {
  const AvatarBadge({
    required this.label,
    required this.color,
    this.size = 52,
    super.key,
  });

  final String label;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = label.trim().isEmpty ? '?' : label.trim();
    final display = normalized.length <= 2
        ? normalized.toUpperCase()
        : normalized.substring(0, 2).toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        display,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
