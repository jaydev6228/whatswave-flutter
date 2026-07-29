import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../domain/chat_attachment.dart';

class AttachmentViewerScreen extends StatelessWidget {
  const AttachmentViewerScreen({
    required this.attachment,
    required this.threadName,
    super.key,
  });

  final ChatAttachment attachment;
  final String threadName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = switch (attachment.type) {
      ChatAttachmentType.photo => 'Full-size photo preview',
      ChatAttachmentType.video => 'Simulated video preview',
      ChatAttachmentType.file => 'Shared document preview',
      ChatAttachmentType.location => 'Pinned location preview',
      ChatAttachmentType.voiceNote => 'Voice note playback preview',
    };

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(attachment.title),
            Text(
              threadName,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: AspectRatio(
                      aspectRatio: attachment.aspectRatio,
                      child: _AttachmentCanvas(attachment: attachment),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        attachment.details,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentCanvas extends StatelessWidget {
  const _AttachmentCanvas({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          colors: [
            attachment.tintColor.withValues(alpha: 0.9),
            attachment.tintColor.withValues(alpha: 0.35),
            theme.colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -28,
            top: 24,
            child:
                _GlowOrb(color: attachment.tintColor.withValues(alpha: 0.28)),
          ),
          Positioned(
            right: -24,
            bottom: 24,
            child: _GlowOrb(
              color: AppPalette.cloud.withValues(alpha: 0.18),
              size: 118,
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  child: Icon(
                    _iconForType(attachment.type),
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    attachment.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    attachment.details,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForType(ChatAttachmentType type) {
    return switch (type) {
      ChatAttachmentType.photo => Icons.photo_outlined,
      ChatAttachmentType.video => Icons.videocam_outlined,
      ChatAttachmentType.file => Icons.insert_drive_file_outlined,
      ChatAttachmentType.location => Icons.location_on_outlined,
      ChatAttachmentType.voiceNote => Icons.graphic_eq_rounded,
    };
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.color,
    this.size = 88,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
