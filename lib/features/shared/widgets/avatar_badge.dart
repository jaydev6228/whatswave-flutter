import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';

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

    if (isRemote) {
      // CachedNetworkImage rather than Image(NetworkImage(..)): NetworkImage
      // caches only in Flutter's in-memory ImageCache, which is empty again
      // on every cold start, so every avatar in the chat list was
      // re-downloaded from Firebase Storage each time the app opened.
      //
      // The widget rather than CachedNetworkImageProvider, because the
      // provider does not surface a failed fetch through Image.errorBuilder
      // -- the image simply never arrives and the avatar stays blank
      // forever. errorWidget here is what keeps the initials fallback.
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => initialsBadge,
          errorWidget: (_, __, ___) => initialsBadge,
        ),
      );
    }

    return ClipOval(
      child: Image(
        image: FileImage(File(url)),
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
