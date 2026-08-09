import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_palette.dart';
import '../../shared/widgets/liquid_glass.dart';
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
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
          ),
          // Full-bleed, no side padding -- lets a real photo/video reach the
          // screen edges instead of sitting in a constrained card. Only the
          // placeholder canvas (file/location/voice, which has nothing real
          // to show full-bleed) still centers itself in a bounded card.
          Expanded(
            child: _AttachmentCanvas(attachment: attachment),
          ),
        ],
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
      // Full-bleed, no corner rounding, and pinch/double-tap-to-zoom via
      // InteractiveViewer -- matching a real photo viewer instead of the
      // constrained, rounded card every other (placeholder) attachment
      // type still uses below.
      return ColoredBox(
        color: Colors.black,
        child: attachment.type == ChatAttachmentType.photo
            ? _ZoomableImage(
                imageProvider: imageProviderForStatusMediaPath(localPath)!,
                errorBuilder: () =>
                    _AttachmentPlaceholderCanvas(attachment: attachment),
              )
            : _AttachmentVideoCanvas(localMediaPath: localPath),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AspectRatio(
          aspectRatio: attachment.aspectRatio,
          child: _AttachmentPlaceholderCanvas(attachment: attachment),
        ),
      ),
    );
  }
}

/// A photo that pans/zooms via pinch or double-tap, matching WhatsApp's own
/// attachment viewer -- InteractiveViewer handles both gestures natively.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    required this.imageProvider,
    required this.errorBuilder,
  });

  final ImageProvider imageProvider;
  final Widget Function() errorBuilder;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _hasError = false;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final isZoomedIn = _transformController.value != Matrix4.identity();
    if (isZoomedIn) {
      _transformController.value = Matrix4.identity();
      return;
    }
    final tapPosition = _doubleTapDetails?.localPosition ?? Offset.zero;
    _transformController.value = Matrix4.identity()
      ..translateByDouble(-tapPosition.dx * 2, -tapPosition.dy * 2, 0, 1)
      ..scaleByDouble(3.0, 3.0, 3.0, 1);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.errorBuilder();
    }

    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        transformationController: _transformController,
        child: Center(
          child: Image(
            image: widget.imageProvider,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _hasError = true);
              });
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
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
  double _volumeBeforeMute = 1;

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

  void _togglePlayback() {
    _controller.value.isPlaying ? _controller.pause() : _controller.play();
  }

  void _toggleMute() {
    if (_controller.value.volume > 0) {
      _volumeBeforeMute = _controller.value.volume;
      _controller.setVolume(0);
    } else {
      _controller.setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 1);
    }
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

        return InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: GestureDetector(
            onTap: _togglePlayback,
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _VideoControlBar(
                      controller: _controller,
                      onPlayPause: _togglePlayback,
                      onToggleMute: _toggleMute,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// WhatsApp-style controls floating over the video itself -- play/pause,
/// a seek bar with elapsed/total time, and mute/unmute. Rebuilds off
/// [controller] directly (it's a ValueListenable) so position/play-state
/// stay live without the parent needing setState on every frame.
class _VideoControlBar extends StatelessWidget {
  const _VideoControlBar({
    required this.controller,
    required this.onPlayPause,
    required this.onToggleMute,
  });

  final VideoPlayerController controller;
  final VoidCallback onPlayPause;
  final VoidCallback onToggleMute;

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final durationMs = value.duration.inMilliseconds;
        final positionMs = value.position.inMilliseconds
            .clamp(0, durationMs > 0 ? durationMs : 0)
            .toDouble();
        final isMuted = value.volume <= 0;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0),
                Colors.black.withValues(alpha: 0.55),
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.28),
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      key: const Key('attachment_video_seek_slider'),
                      min: 0,
                      max: durationMs > 0 ? durationMs.toDouble() : 1,
                      value: positionMs,
                      onChanged: durationMs > 0
                          ? (newValue) => controller.seekTo(
                                Duration(milliseconds: newValue.round()),
                              )
                          : null,
                    ),
                  ),
                  Row(
                    children: [
                      LiquidGlassIconButton(
                        actionKey:
                            const Key('attachment_video_play_pause_button'),
                        icon: value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onTap: onPlayPause,
                        size: 40,
                        blurred: false,
                        color: Colors.black.withValues(alpha: 0.42),
                        iconColor: Colors.white,
                        tooltip: value.isPlaying ? 'Pause' : 'Play',
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${_formatDuration(value.position)} / '
                        '${_formatDuration(value.duration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      LiquidGlassIconButton(
                        actionKey: const Key('attachment_video_mute_button'),
                        icon: isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        onTap: onToggleMute,
                        size: 40,
                        blurred: false,
                        color: Colors.black.withValues(alpha: 0.42),
                        iconColor: Colors.white,
                        tooltip: isMuted ? 'Unmute' : 'Mute',
                      ),
                    ],
                  ),
                ],
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
