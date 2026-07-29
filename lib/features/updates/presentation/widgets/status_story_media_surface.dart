import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/models/status_story.dart';
import 'status_media_source.dart';

Size statusStoryFrameSizeFor(Size canvasSize, double? aspectRatio) {
  if (aspectRatio == null || !aspectRatio.isFinite || aspectRatio <= 0) {
    return canvasSize;
  }

  var width = canvasSize.width;
  var height = width / aspectRatio;

  if (height > canvasSize.height) {
    height = canvasSize.height;
    width = height * aspectRatio;
  }

  return Size(width, height);
}

class StatusStoryMediaSurface extends StatefulWidget {
  const StatusStoryMediaSurface({
    required this.type,
    required this.localMediaPath,
    this.mediaTransform = const StatusMediaTransform(),
    this.videoController,
    this.videoInitialization,
    this.backgroundColor = Colors.black,
    this.showFrameOutline = false,
    this.unavailableMessage,
    this.onSourceSizeResolved,
    this.onTap,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    super.key,
  });

  final StatusStoryType type;
  final String localMediaPath;
  final StatusMediaTransform mediaTransform;
  final VideoPlayerController? videoController;
  final Future<void>? videoInitialization;
  final Color backgroundColor;
  final bool showFrameOutline;
  final String? unavailableMessage;
  final ValueChanged<Size>? onSourceSizeResolved;
  final VoidCallback? onTap;
  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;

  @override
  State<StatusStoryMediaSurface> createState() =>
      _StatusStoryMediaSurfaceState();
}

class _StatusStoryMediaSurfaceState extends State<StatusStoryMediaSurface> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  Size? _photoIntrinsicSize;

  @override
  void initState() {
    super.initState();
    _resolvePhotoIntrinsicSize();
  }

  @override
  void didUpdateWidget(covariant StatusStoryMediaSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type ||
        oldWidget.localMediaPath != widget.localMediaPath) {
      _resolvePhotoIntrinsicSize();
    }
  }

  @override
  void dispose() {
    _detachImageStream();
    super.dispose();
  }

  void _resolvePhotoIntrinsicSize() {
    _detachImageStream();
    if (widget.type != StatusStoryType.photo) {
      setState(() {
        _photoIntrinsicSize = null;
      });
      return;
    }

    final imageProvider = imageProviderForStatusMediaPath(widget.localMediaPath);
    if (imageProvider == null) {
      setState(() {
        _photoIntrinsicSize = null;
      });
      return;
    }
    final imageStream = imageProvider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (imageInfo, _) {
        if (!mounted) {
          return;
        }
        final nextSize = Size(
          imageInfo.image.width.toDouble(),
          imageInfo.image.height.toDouble(),
        );
        if (_photoIntrinsicSize == nextSize) {
          return;
        }
        setState(() {
          _photoIntrinsicSize = nextSize;
        });
        widget.onSourceSizeResolved?.call(nextSize);
      },
      onError: (_, __) {
        if (!mounted) {
          return;
        }
        setState(() {
          _photoIntrinsicSize = null;
        });
      },
    );

    _imageStream = imageStream;
    _imageStreamListener = listener;
    imageStream.addListener(listener);
  }

  void _detachImageStream() {
    final imageStream = _imageStream;
    final listener = _imageStreamListener;
    if (imageStream != null && listener != null) {
      imageStream.removeListener(listener);
    }
    _imageStream = null;
    _imageStreamListener = null;
  }

  @override
  Widget build(BuildContext context) {
    final mediaPath = widget.localMediaPath.trim();
    final hasMediaSource = statusMediaSourceExists(mediaPath);

    final surface = LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = constraints.biggest;
        final frameSize = statusStoryFrameSizeFor(
          canvasSize,
          widget.mediaTransform.frameAspectRatio,
        );

        if (frameSize.width <= 0 || frameSize.height <= 0) {
          return const SizedBox.expand();
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: widget.backgroundColor),
            Center(
              child: SizedBox(
                key: const Key('updates_media_story_frame'),
                width: frameSize.width,
                height: frameSize.height,
                child: ClipRect(
                  child: ColoredBox(
                    color: widget.backgroundColor,
                    child: hasMediaSource
                        ? _buildTransformedMedia(
                            mediaPath: mediaPath,
                            frameSize: frameSize,
                          )
                        : _StatusMediaUnavailableState(
                            message: widget.unavailableMessage ??
                                'This media is no longer available on this device.',
                          ),
                  ),
                ),
              ),
            ),
            if (widget.showFrameOutline &&
                widget.mediaTransform.frameAspectRatio != null)
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: frameSize.width,
                    height: frameSize.height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.78),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );

    if (widget.onTap == null &&
        widget.onScaleStart == null &&
        widget.onScaleUpdate == null &&
        widget.onScaleEnd == null) {
      return surface;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onScaleStart: widget.onScaleStart,
      onScaleUpdate: widget.onScaleUpdate,
      onScaleEnd: widget.onScaleEnd,
      child: surface,
    );
  }

  Widget _buildTransformedMedia({
    required String mediaPath,
    required Size frameSize,
  }) {
    final quarterTurns = _normalizedQuarterTurns(
      widget.mediaTransform.rotationQuarterTurns,
    );
    final sourceSize = switch (widget.type) {
      StatusStoryType.photo => _photoIntrinsicSize ??
          Size(
            frameSize.width.clamp(1, double.infinity),
            frameSize.height.clamp(1, double.infinity),
          ),
      StatusStoryType.video => _videoSourceSize(frameSize),
      StatusStoryType.text => frameSize,
    };
    final renderedSourceSize = quarterTurns.isOdd
        ? Size(sourceSize.height, sourceSize.width)
        : sourceSize;
    final translation = Offset(
      widget.mediaTransform.offsetDx * frameSize.width,
      widget.mediaTransform.offsetDy * frameSize.height,
    );

    final media = FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: renderedSourceSize.width,
        height: renderedSourceSize.height,
        child: Transform.rotate(
          angle: quarterTurns * (math.pi / 2),
          child: SizedBox(
            width: sourceSize.width,
            height: sourceSize.height,
            child: _buildSourceWidget(
              mediaPath: mediaPath,
              sourceSize: sourceSize,
            ),
          ),
        ),
      ),
    );

    return Transform.translate(
      offset: translation,
      child: Transform.scale(
        scale: widget.mediaTransform.scale,
        child: media,
      ),
    );
  }

  Size _videoSourceSize(Size fallbackSize) {
    final controller = widget.videoController;
    if (controller == null || !controller.value.isInitialized) {
      return fallbackSize;
    }

    final size = controller.value.size;
    final width = size.width <= 0 ? fallbackSize.width : size.width;
    final height = size.height <= 0 ? fallbackSize.height : size.height;
    return Size(width, height);
  }

  Widget _buildSourceWidget({
    required String mediaPath,
    required Size sourceSize,
  }) {
    if (widget.type == StatusStoryType.photo) {
      final imageProvider = imageProviderForStatusMediaPath(mediaPath);
      if (imageProvider == null) {
        return _StatusMediaUnavailableState(
          message: widget.unavailableMessage ??
              'This photo could not be opened on this device.',
        );
      }
      return Image(
        image: imageProvider,
        key: const Key('updates_story_media_photo'),
        width: sourceSize.width,
        height: sourceSize.height,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (_, __, ___) {
          return _StatusMediaUnavailableState(
            message: widget.unavailableMessage ??
                'This photo could not be opened on this device.',
          );
        },
      );
    }

    final controller = widget.videoController;
    final initialization = widget.videoInitialization;
    if (controller == null || initialization == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return FutureBuilder<void>(
      future: initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        return SizedBox(
          key: const Key('updates_story_media_video'),
          width: sourceSize.width,
          height: sourceSize.height,
          child: VideoPlayer(controller),
        );
      },
    );
  }

  static int _normalizedQuarterTurns(int quarterTurns) {
    final normalized = quarterTurns % 4;
    return normalized < 0 ? normalized + 4 : normalized;
  }
}

class _StatusMediaUnavailableState extends StatelessWidget {
  const _StatusMediaUnavailableState({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            AppPalette.deepOcean,
            AppPalette.slate,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.perm_media_outlined,
                color: Colors.white,
                size: 34,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.86),
                  height: 1.38,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
