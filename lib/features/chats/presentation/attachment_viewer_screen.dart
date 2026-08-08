import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_palette.dart';
import '../../updates/presentation/widgets/status_media_source.dart';
import '../domain/chat_attachment.dart';

/// Shown as an in-place overlay over the current screen (see
/// [showAttachmentPreview]) rather than pushed as a separate route -- a
/// plain full-bleed canvas with a close button, no AppBar/back-chevron
/// chrome pretending it's a whole new screen.
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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('attachment_viewer_close_button'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Text(
                      threadName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
          ],
        ),
      ),
    );
  }
}

/// Presents [AttachmentViewerScreen] as a full-screen overlay (fade + scale)
/// on top of the current screen instead of navigating to a new route.
Future<void> showAttachmentPreview(
  BuildContext context, {
  required ChatAttachment attachment,
  required String threadName,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: attachment.title,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) {
      return Dialog.fullscreen(
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: AttachmentViewerScreen(
          attachment: attachment,
          threadName: threadName,
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _AttachmentCanvas extends StatelessWidget {
  const _AttachmentCanvas({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final localPath = attachment.localMediaPath;
    final hasRealMedia = localPath != null &&
        statusMediaSourceExists(localPath) &&
        (attachment.type == ChatAttachmentType.photo ||
            attachment.type == ChatAttachmentType.video);

    if (hasRealMedia) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: attachment.type == ChatAttachmentType.photo
            ? ColoredBox(
                color: Colors.black,
                child: Image(
                  image: imageProviderForStatusMediaPath(localPath)!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      _AttachmentPlaceholderCanvas(attachment: attachment),
                ),
              )
            : _AttachmentVideoCanvas(localMediaPath: localPath),
      );
    }

    return _AttachmentPlaceholderCanvas(attachment: attachment);
  }
}

class _AttachmentVideoCanvas extends StatefulWidget {
  const _AttachmentVideoCanvas({required this.localMediaPath});

  final String localMediaPath;

  @override
  State<_AttachmentVideoCanvas> createState() => _AttachmentVideoCanvasState();
}

class _AttachmentVideoCanvasState extends State<_AttachmentVideoCanvas> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _controller = buildStatusMediaVideoController(widget.localMediaPath);
    _initialization = _controller.initialize().then((_) {
      _controller
        ..setLooping(true)
        ..play();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !_controller.value.isInitialized) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        return GestureDetector(
          onTap: () {
            setState(() {
              _controller.value.isPlaying
                  ? _controller.pause()
                  : _controller.play();
            });
          },
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AttachmentPlaceholderCanvas extends StatelessWidget {
  const _AttachmentPlaceholderCanvas({required this.attachment});

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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
