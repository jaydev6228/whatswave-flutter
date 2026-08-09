import 'dart:io';

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

    // Almost always a Firebase Storage download URL (FirebaseAuthRepository
    // .updateAvatar), but FakeAuthRepository's demo/test double stores the
    // picked file's own local path instead -- resolve either correctly
    // rather than assuming every avatarUrl is a real network URL.
    final isRemote = url.startsWith('http://') || url.startsWith('https://');
    final imageProvider =
        isRemote ? NetworkImage(url) : FileImage(File(url)) as ImageProvider;

    return ClipOval(
      child: Image(
        image: imageProvider,
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
