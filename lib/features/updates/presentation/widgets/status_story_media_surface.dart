import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/models/status_story.dart';
import 'status_media_source.dart';
import '../status_motion.dart';

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

/// The aspect ratio the crop window actually takes for a given
/// [StatusMediaTransform.frameAspectRatio].
///
/// A null frame ratio ("Fit to screen", and "Original" while the source
/// size is still unresolved) is not "no crop" -- the final, posted render
/// cover-fits the media into the whole canvas, so it crops to the
/// *canvas's* own shape. Resolving null to the canvas ratio here is what
/// lets crop mode preview exactly what gets posted.
double statusCropRatioFor(Size canvasSize, double? frameAspectRatio) {
  if (frameAspectRatio != null &&
      frameAspectRatio.isFinite &&
      frameAspectRatio > 0) {
    return frameAspectRatio;
  }
  if (canvasSize.height <= 0 || !canvasSize.height.isFinite) {
    return 1;
  }
  return canvasSize.width / canvasSize.height;
}

/// Where the media actually paints inside [canvasSize] during crop mode --
/// the media is contain-fit there (see the isCropPreview branch), so it
/// occupies the largest box of its own [mediaAspectRatio] that fits, with
/// letterbox bars on the remaining two sides. The crop window is confined
/// to this rect rather than the whole canvas, since dragging the window
/// out over a letterbox bar would select empty space, not media.
Rect statusMediaBoundsFor(Size canvasSize, double? mediaAspectRatio) {
  final size = statusStoryFrameSizeFor(canvasSize, mediaAspectRatio);
  return Rect.fromCenter(
    center: Offset(canvasSize.width / 2, canvasSize.height / 2),
    width: size.width,
    height: size.height,
  );
}

/// The crop selection window's position and size within the media's own
/// painted bounds (see [statusMediaBoundsFor]) -- the free-form box the
/// crop tool lets you drag and resize (via corner handles) around a fully
/// visible, never-moving photo/video, matching WhatsApp's own crop tool
/// (the media itself never pans or scales on screen; only this window
/// does, to choose which part of the media ends up in the final crop).
///
/// With no [ratio] picked, the window is exactly the media's bounds --
/// nothing is cropped until the user shrinks or moves it, matching
/// WhatsApp's crop tool opening on the full, uncropped frame.
///
/// [scale] is [StatusMediaTransform.scale] -- it shrinks the window below
/// the largest box of [ratio] that fits [mediaBounds] (a smaller window
/// means "zoomed in more" in the final crop, exactly mirroring how the
/// same field zooms the media in the final, non-crop-mode rendering).
///
/// [offsetDx]/[offsetDy] follow the same sign convention as
/// [StatusMediaTransform.offsetDx]/[offsetDy] -- the offset that, applied
/// to the media itself in the *final* (non-crop-mode) clipped rendering,
/// lands on exactly the same region this window shows. Shifting the media
/// right by X is equivalent to shifting this window left by X, hence the
/// negation below.
Rect cropWindowRectFor(
  Rect mediaBounds,
  double? ratio,
  double scale,
  double offsetDx,
  double offsetDy,
) {
  if (ratio == null || !ratio.isFinite || ratio <= 0) {
    return mediaBounds;
  }
  final fitSize = statusStoryFrameSizeFor(mediaBounds.size, ratio);
  final effectiveScale = (scale.isFinite && scale > 0) ? scale : 1.0;
  final windowSize = Size(
    fitSize.width / effectiveScale,
    fitSize.height / effectiveScale,
  );
  final rawCenter = Offset(
    mediaBounds.center.dx - offsetDx * windowSize.width,
    mediaBounds.center.dy - offsetDy * windowSize.height,
  );
  final minCenterX = mediaBounds.left + windowSize.width / 2;
  final maxCenterX =
      math.max(mediaBounds.right - windowSize.width / 2, minCenterX);
  final minCenterY = mediaBounds.top + windowSize.height / 2;
  final maxCenterY =
      math.max(mediaBounds.bottom - windowSize.height / 2, minCenterY);
  final center = Offset(
    rawCenter.dx.clamp(minCenterX, maxCenterX),
    rawCenter.dy.clamp(minCenterY, maxCenterY),
  );
  return Rect.fromCenter(
    center: center,
    width: windowSize.width,
    height: windowSize.height,
  );
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
    this.drawingStrokes = const <StatusDrawingStroke>[],
    this.onSourceSizeResolved,
    this.onPhotoLoadSettled,
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

  /// Freehand doodle strokes, painted on top of the media and clipped to
  /// the same frame -- shared by composer, viewer, and thumbnails since
  /// they all render through this one surface.
  final List<StatusDrawingStroke> drawingStrokes;
  final ValueChanged<Size>? onSourceSizeResolved;

  /// Fires exactly once per photo load attempt, whether it succeeded or
  /// failed -- unlike [onSourceSizeResolved] (success only), this is meant
  /// for callers that just need to know loading has *settled* (e.g. the
  /// story viewer, which pauses its progress bar until the current
  /// segment's media is actually on screen). Never fires for video/text
  /// segments, which have their own readiness signals (the video
  /// initialization future; text has nothing to load).
  final VoidCallback? onPhotoLoadSettled;
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

  /// Distinguishes "still decoding" from "gave up" -- both leave
  /// [_photoIntrinsicSize] null, but only the former should keep the
  /// top-level loading spinner (below, in build()) on screen. Without this,
  /// a photo that fails to load (e.g. a dead network URL) left the spinner
  /// spinning forever instead of handing off to the error state.
  bool _photoLoadFailed = false;

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
        _photoLoadFailed = false;
      });
      return;
    }

    final imageProvider = imageProviderForStatusMediaPath(widget.localMediaPath);
    if (imageProvider == null) {
      setState(() {
        _photoIntrinsicSize = null;
        _photoLoadFailed = true;
      });
      _notifyPhotoLoadSettled();
      return;
    }
    // Plain field resets, not setState -- this runs synchronously inside
    // initState (too early for setState) and inside didUpdateWidget (whose
    // caller is already mid-rebuild, so the imminent build() picks these up
    // without a separate trigger either way).
    _photoIntrinsicSize = null;
    _photoLoadFailed = false;
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
        _notifyPhotoLoadSettled();
      },
      onError: (_, __) {
        if (!mounted) {
          return;
        }
        setState(() {
          _photoIntrinsicSize = null;
          _photoLoadFailed = true;
        });
        _notifyPhotoLoadSettled();
      },
    );

    _imageStream = imageStream;
    _imageStreamListener = listener;
    imageStream.addListener(listener);
  }

  /// Deferred to the next frame -- `ImageStream.addListener` can resolve
  /// synchronously for an already-cached image, and `_resolvePhotoIntrinsic
  /// Size` itself runs synchronously from `initState`. Either way, calling
  /// straight into a caller's `setState` (the story viewer pausing/resuming
  /// its progress bar) while this widget is still mid-mount hits Flutter's
  /// "setState() called during build" guard, since an ancestor can't be
  /// marked dirty while one of its own descendants is still being built.
  void _notifyPhotoLoadSettled() {
    final callback = widget.onPhotoLoadSettled;
    if (callback == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        callback();
      }
    });
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
    // Crop mode shows the whole media, fixed and unclipped -- a movable
    // window (see cropWindowRectFor) is what selects the crop region, not
    // the media itself, matching WhatsApp's own crop tool. Everywhere else
    // (normal preview, the posted story) keeps rendering exactly as before:
    // the media clipped and translated/scaled to fill the ratio'd frame.
    final isCropPreview = widget.showFrameOutline;

    final surface = LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = constraints.biggest;
        final ratio = widget.mediaTransform.frameAspectRatio;
        final frameSize = statusStoryFrameSizeFor(canvasSize, ratio);
        final displaySize = isCropPreview ? canvasSize : frameSize;
        final effectiveTransform = isCropPreview
            ? widget.mediaTransform.copyWith(
                offsetDx: 0,
                offsetDy: 0,
                scale: 1,
              )
            : widget.mediaTransform;

        if (displaySize.width <= 0 || displaySize.height <= 0) {
          return const SizedBox.expand();
        }

        // Where the media actually paints inside `displaySize`. Outside
        // crop mode the media fills that box, so the two are the same. In
        // crop mode the media is contain-fit into the full canvas, leaving
        // letterbox bars the crop window has to stay inside.
        final mediaBounds = isCropPreview
            ? statusMediaBoundsFor(canvasSize, _resolvedMediaAspectRatio)
            : Offset.zero & displaySize;
        // The crop window shows exactly the region the ratio'd frame shows
        // outside crop mode, so it is the rect that drawing strokes --
        // stored normalised to that frame -- belong in while cropping.
        // Painting them over the whole canvas instead is what smeared them
        // across the letterbox bars.
        final cropWindow = isCropPreview
            ? cropWindowRectFor(
                mediaBounds,
                statusCropRatioFor(canvasSize, ratio),
                widget.mediaTransform.scale,
                widget.mediaTransform.offsetDx,
                widget.mediaTransform.offsetDy,
              )
            : Offset.zero & displaySize;

        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: widget.backgroundColor),
            Center(
              child: SizedBox(
                key: const Key('updates_media_story_frame'),
                width: displaySize.width,
                height: displaySize.height,
                child: ClipRect(
                  child: ColoredBox(
                    color: widget.backgroundColor,
                    child: hasMediaSource
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              widget.mediaTransform.blurSigma > 0
                                  ? ImageFiltered(
                                      key: const Key(
                                          'updates_story_blur_layer'),
                                      imageFilter: ImageFilter.blur(
                                        sigmaX: widget.mediaTransform.blurSigma,
                                        sigmaY: widget.mediaTransform.blurSigma,
                                      ),
                                      child: _buildTransformedMedia(
                                        mediaPath: mediaPath,
                                        frameSize: displaySize,
                                        transform: effectiveTransform,
                                        fit: isCropPreview
                                            ? BoxFit.contain
                                            : BoxFit.cover,
                                      ),
                                    )
                                  : _buildTransformedMedia(
                                      mediaPath: mediaPath,
                                      frameSize: displaySize,
                                      transform: effectiveTransform,
                                      fit: isCropPreview
                                          ? BoxFit.contain
                                          : BoxFit.cover,
                                    ),
                              if (widget.drawingStrokes.isNotEmpty)
                                // Pinned to the media's own rect, not the
                                // whole box: strokes are stored normalised
                                // to the media frame, so painting them over
                                // a larger canvas would stretch them across
                                // the letterbox bars in crop mode.
                                Positioned.fromRect(
                                  rect: cropWindow,
                                  child: IgnorePointer(
                                    // Clipped as well as positioned -- a
                                    // stroke whose points stray outside the
                                    // frame must not paint over the bars.
                                    child: ClipRect(
                                      child: CustomPaint(
                                        key: const Key(
                                            'updates_story_drawing_layer'),
                                        painter: _StatusDrawingPainter(
                                          strokes: widget.drawingStrokes,
                                          frameSize: cropWindow.size,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              // Painted as its own top layer, outside the
                              // blur/transform subtree above -- a spinner
                              // nested inside `_buildTransformedMedia` got
                              // scaled by pinch/zoom and blurred by the blur
                              // tool right along with the (not yet loaded)
                              // media underneath it, which is what made it
                              // look faint/"behind" a blurry view instead of
                              // a crisp loading state on top.
                              if (widget.type == StatusStoryType.photo &&
                                  _photoIntrinsicSize == null &&
                                  !_photoLoadFailed)
                                const IgnorePointer(
                                  child: ColoredBox(
                                    color: Colors.black,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              if (widget.type == StatusStoryType.video)
                                IgnorePointer(
                                  child: FutureBuilder<void>(
                                    future: widget.videoInitialization,
                                    builder: (context, snapshot) {
                                      // Settled, whether it succeeded or
                                      // failed -- checking isInitialized too
                                      // would leave this spinning forever
                                      // on a video that fails to initialize
                                      // (the future still completes, just
                                      // with an error).
                                      if (snapshot.connectionState ==
                                          ConnectionState.done) {
                                        return const SizedBox.shrink();
                                      }
                                      return const ColoredBox(
                                        color: Colors.black,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          )
                        : _StatusMediaUnavailableState(
                            message: widget.unavailableMessage ??
                                'This media is no longer available on this device.',
                          ),
                  ),
                ),
              ),
            ),
            // Faded rather than snapped in: entering crop mode already
            // re-lays the media out, and having the dimming and grid pop
            // on in the same frame is what made the switch feel abrupt.
            AnimatedOpacity(
              opacity: isCropPreview ? 1 : 0,
              duration: kStatusMotionDuration,
              curve: kStatusMotionCurve,
              child: IgnorePointer(
                child: _CropSelectionOverlay(
                  key: const Key('updates_media_crop_selection_overlay'),
                  canvasSize: canvasSize,
                  window: cropWindow,
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
    required StatusMediaTransform transform,
    BoxFit fit = BoxFit.cover,
  }) {
    final quarterTurns = _normalizedQuarterTurns(
      transform.rotationQuarterTurns,
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
      transform.offsetDx * frameSize.width,
      transform.offsetDy * frameSize.height,
    );

    final media = FittedBox(
      fit: fit,
      child: SizedBox(
        width: renderedSourceSize.width,
        height: renderedSourceSize.height,
        // `Transform.rotate` only affects painting, not layout -- without
        // this `OverflowBox` the tight constraints from this SizedBox
        // (renderedSourceSize, W/H-swapped for odd quarter turns) would
        // leak straight through the rotate into the inner SizedBox below,
        // clamping the real media to the wrong-shaped box: forced over-crop
        // for photos (which have BoxFit.cover to fall back on) and a hard
        // stretch for video (which doesn't). Loosening to the true
        // unrotated sourceSize here lets the media lay out correctly, get
        // rotated as a whole, and only then get cover-fit into the frame.
        child: OverflowBox(
          minWidth: sourceSize.width,
          maxWidth: sourceSize.width,
          minHeight: sourceSize.height,
          maxHeight: sourceSize.height,
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
      ),
    );

    return Transform.translate(
      offset: translation,
      child: Transform.scale(
        scale: transform.scale,
        child: media,
      ),
    );
  }

  /// The aspect ratio the media actually paints at on screen, with any
  /// rotation already applied -- null while the real source size is still
  /// unresolved (a photo mid-load, or a video before initialization), in
  /// which case callers fall back to the full canvas.
  double? get _resolvedMediaAspectRatio {
    final sourceSize = switch (widget.type) {
      StatusStoryType.photo => _photoIntrinsicSize,
      StatusStoryType.video => widget.videoController?.value.isInitialized ==
              true
          ? widget.videoController!.value.size
          : null,
      StatusStoryType.text => null,
    };
    if (sourceSize == null ||
        sourceSize.width <= 0 ||
        sourceSize.height <= 0) {
      return null;
    }
    final quarterTurns =
        _normalizedQuarterTurns(widget.mediaTransform.rotationQuarterTurns);
    return quarterTurns.isOdd
        ? sourceSize.height / sourceSize.width
        : sourceSize.width / sourceSize.height;
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
        // The crisp, unblurred/untransformed loading spinner lives as its
        // own top-level layer above (see build()) -- this placeholder just
        // needs to hold the frame's shape while decoding, not paint its
        // own (transformable, blurrable) copy of the spinner.
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return const ColoredBox(color: Colors.black);
        },
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
    // The crisp, unblurred/untransformed loading spinner lives as its own
    // top-level layer above (see build()) -- these placeholders just need
    // to hold the frame's shape while the video initializes.
    if (controller == null || initialization == null) {
      return const ColoredBox(color: Colors.black);
    }

    return FutureBuilder<void>(
      future: initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return const ColoredBox(color: Colors.black);
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

  /// Below this height there's no room for the icon+message layout below
  /// (designed for a full-screen viewer/composer canvas) -- e.g. the small
  /// 62x74 segment thumbnail in the "Manage status" sheet, which now
  /// renders through this same shared surface. A fixed icon-only fallback,
  /// not a shrunk version of the full layout, since text wouldn't stay
  /// legible at that size anyway.
  static const double _compactHeightThreshold = 120;

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight < _compactHeightThreshold) {
            return const Center(
              child: Icon(
                Icons.perm_media_outlined,
                color: Colors.white,
                size: 20,
              ),
            );
          }

          return Center(
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
          );
        },
      ),
    );
  }
}

class _StatusDrawingPainter extends CustomPainter {
  const _StatusDrawingPainter({
    required this.strokes,
    required this.frameSize,
  });

  final List<StatusDrawingStroke> strokes;
  final Size frameSize;

  @override
  void paint(Canvas canvas, Size size) {
    final shortestSide = math.min(size.width, size.height);
    // Painted into an offscreen layer so an eraser stroke's BlendMode.clear
    // only punches through ink laid down earlier in this same layer, never
    // the photo/video underneath (that's a separate layer beneath this
    // whole CustomPaint widget).
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final stroke in strokes) {
      if (stroke.points.length < 2) {
        continue;
      }
      final paint = Paint()
        ..color = stroke.isEraser ? Colors.black : stroke.color
        ..strokeWidth = stroke.strokeWidth * shortestSide
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;
      final path = Path()
        ..moveTo(
          stroke.points.first.dx * size.width,
          stroke.points.first.dy * size.height,
        );
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StatusDrawingPainter oldDelegate) {
    return oldDelegate.strokes != strokes || oldDelegate.frameSize != frameSize;
  }
}

/// Crop mode's own overlay -- dims everything outside the crop selection
/// window (see [cropWindowRectFor]) and draws a rule-of-thirds grid and
/// border around it, exactly like WhatsApp's own crop tool. With no ratio
/// selected (Original/Fit to screen), the window is exactly the media's
/// own bounds, so nothing inside the media is dimmed.
class _CropSelectionOverlay extends StatelessWidget {
  const _CropSelectionOverlay({
    required this.canvasSize,
    required this.window,
    super.key,
  });

  final Size canvasSize;

  /// The crop selection rect, already resolved by the caller so the
  /// overlay, the corner handles and the drawing layer cannot drift apart
  /// by each computing it slightly differently.
  final Rect window;

  @override
  Widget build(BuildContext context) {
    final dimColor = Colors.black.withValues(alpha: 0.82);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Four strips around the window rather than one shape with a
        // hole -- simpler and just as correct, since the strips are
        // axis-aligned rectangles that exactly tile the "outside" region.
        // When the window is the full canvas (untouched/no ratio) every
        // strip has zero size, so nothing is dimmed -- exactly right for
        // an unmodified crop.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: window.top,
          child: ColoredBox(color: dimColor),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: window.bottom,
          bottom: 0,
          child: ColoredBox(color: dimColor),
        ),
        Positioned(
          left: 0,
          top: window.top,
          width: window.left,
          height: window.height,
          child: ColoredBox(color: dimColor),
        ),
        Positioned(
          right: 0,
          top: window.top,
          left: window.right,
          height: window.height,
          child: ColoredBox(color: dimColor),
        ),
        Positioned.fromRect(
          rect: window,
          child: CustomPaint(
            painter: const _CropGridPainter(),
          ),
        ),
        Positioned.fromRect(
          rect: window,
          child: DecoratedBox(
            decoration: BoxDecoration(
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
      ],
    );
  }
}

/// The crop window's rule-of-thirds grid lines.
class _CropGridPainter extends CustomPainter {
  const _CropGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.56)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropGridPainter oldDelegate) => false;
}
