import 'package:flutter/material.dart';

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.dense = false,
    this.margin = const EdgeInsets.all(4),
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool dense;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = dense ? 20.0 : 24.0;
    final iconRadius = dense ? 22.0 : 24.0;
    final verticalGap = dense ? 12.0 : 16.0;
    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      fontSize: dense ? 15 : null,
      height: dense ? 1.32 : null,
    );

    return Card(
      margin: margin,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: iconRadius,
              backgroundColor:
                  theme.colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            SizedBox(height: verticalGap),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: dense ? 17 : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: subtitleStyle,
            ),
          ],
        ),
      ),
    );
  }
}
