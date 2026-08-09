import 'package:flutter/material.dart';

class AvatarBadge extends StatelessWidget {
  const AvatarBadge({
    required this.label,
    required this.color,
    this.size = 52,
    this.avatarUrl,
    super.key,
  });

  final String label;
  final Color color;
  final double size;

  /// A photo to show instead of the initials badge, when set (e.g. a
  /// user's uploaded profile photo). Falls back to the initials badge if
  /// null, empty, or the image fails to load.
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = label.trim().isEmpty ? '?' : label.trim();
    final display = normalized.length <= 2
        ? normalized.toUpperCase()
        : normalized.substring(0, 2).toUpperCase();

    final initialsBadge = Container(
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

    final url = avatarUrl?.trim();
    if (url == null || url.isEmpty) {
      return initialsBadge;
    }

    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => initialsBadge,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : initialsBadge,
      ),
    );
  }
}
