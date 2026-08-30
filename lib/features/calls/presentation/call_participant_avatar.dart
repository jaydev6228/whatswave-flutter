import 'dart:io';

import 'package:flutter/material.dart';

/// Circular call avatar that prefers a profile photo and falls back to
/// initials, matching [AvatarBadge] resolution rules.
class CallParticipantAvatar extends StatelessWidget {
  const CallParticipantAvatar({
    required this.label,
    required this.size,
    this.avatarUrl,
    this.photoAssetPath,
    this.backgroundColor,
    this.foregroundColor,
    super.key,
  });

  final String label;
  final double size;
  final String? avatarUrl;
  final String? photoAssetPath;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = label.trim().isEmpty ? '?' : label.trim();
    final display = normalized.length <= 2
        ? normalized.toUpperCase()
        : normalized.substring(0, 2).toUpperCase();

    final initials = Container(
      width: size,
      height: size,
      color:
          backgroundColor ?? theme.colorScheme.surface.withValues(alpha: 0.24),
      alignment: Alignment.center,
      child: Text(
        display,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge?.copyWith(
          color: foregroundColor ?? theme.colorScheme.onSurface,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.32,
        ),
      ),
    );

    final assetPath = photoAssetPath?.trim();
    if (assetPath != null && assetPath.isNotEmpty) {
      return ClipOval(
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => initials,
        ),
      );
    }

    final url = avatarUrl?.trim();
    if (url == null || url.isEmpty) {
      return initials;
    }

    final isRemote = url.startsWith('http://') || url.startsWith('https://');
    final imageProvider =
        isRemote ? NetworkImage(url) : FileImage(File(url)) as ImageProvider;

    return ClipOval(
      child: Image(
        image: imageProvider,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => initials,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : initials,
      ),
    );
  }
}
