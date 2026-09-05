import 'dart:io';

import 'package:flutter/material.dart';

import '../../application/layout_slot_transform.dart';
import '../../data/layout_catalog.dart';
import '../../models/layout_models.dart';
import 'layout_shape_clipper.dart';

/// Default zoom when a photo lands in a slot.
const double kLayoutDefaultPhotoScale = 1.0;

/// The live 9:16 collage canvas. Each slot clips and pans its image inside
/// the template region. Wrapped in a [RepaintBoundary] for export.
class LayoutCanvas extends StatelessWidget {
  const LayoutCanvas({
    required this.state,
    required this.onSlotTap,
    this.onCanvasBackgroundTap,
    this.onSlotTransformEnd,
    this.isEditing = true,
    super.key,
  });

  final LayoutComposerState state;
  final ValueChanged<int> onSlotTap;
  final VoidCallback? onCanvasBackgroundTap;
  final void Function(int slotIndex, double scale, Offset focal)?
      onSlotTransformEnd;

  /// False in preview mode and during export, where the canvas has to show
  /// exactly what gets posted — no selection ring, no "Tap to add" hints.
  final bool isEditing;

  @override
  Widget build(BuildContext context) {
    final template = LayoutCatalog.templateById(state.templateId);
    final filledSlotCount =
        state.slots.where((slot) => slot.hasImage).length.clamp(0, 99);
    final previewCacheWidth = layoutPreviewCacheWidth(
      filledSlotCount == 0 ? 1 : filledSlotCount,
    );
    final selectedIndex = state.selectedSlotIndex;

    return AspectRatio(
      aspectRatio: state.ratio.value,
      child: ColoredBox(
        color: state.backgroundColor,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final canvasSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: onCanvasBackgroundTap,
                  ),
                ),
                for (var index = 0; index < template.slots.length; index++)
                  if (index < state.slots.length)
                    _LayoutSlotLayer(
                      key: ValueKey<String>(
                        'layout_slot_${state.templateId}_$index',
                      ),
                      slotIndex: index,
                      definition: template.slots[index],
                      content: state.slots[index],
                      canvasSize: canvasSize,
                      previewCacheWidth: previewCacheWidth,
                      isSelected: isEditing &&
                          selectedIndex == index &&
                          state.slots[index].hasImage,
                      showEmptyHint: isEditing,
                      canTransform: state.slots[index].hasImage &&
                          onSlotTransformEnd != null,
                      onTap: () => onSlotTap(index),
                      onTransformEnd: onSlotTransformEnd == null
                          ? null
                          : (scale, focal) =>
                              onSlotTransformEnd!(index, scale, focal),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LayoutSlotLayer extends StatefulWidget {
  const _LayoutSlotLayer({
    required this.slotIndex,
    required this.definition,
    required this.content,
    required this.canvasSize,
    required this.previewCacheWidth,
    required this.isSelected,
    required this.showEmptyHint,
    required this.canTransform,
    required this.onTap,
    this.onTransformEnd,
    super.key,
  });

  final int slotIndex;
  final LayoutSlotDefinition definition;
  final LayoutSlotContent content;
  final Size canvasSize;
  final int previewCacheWidth;
  final bool isSelected;
  final bool showEmptyHint;
  final bool canTransform;
  final VoidCallback onTap;
  final void Function(double scale, Offset focal)? onTransformEnd;

  @override
  State<_LayoutSlotLayer> createState() => _LayoutSlotLayerState();
}

class _LayoutSlotLayerState extends State<_LayoutSlotLayer> {
  double _gestureStartScale = 1;
  Offset _gestureStartFocal = Offset.zero;
  double? _liveScale;
  Offset? _liveFocal;
  bool _didPanOrZoom = false;
  Size? _imageSize;
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;

  @override
  void initState() {
    super.initState();
    _resolveImageSize();
  }

  @override
  void didUpdateWidget(covariant _LayoutSlotLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content.imagePath != widget.content.imagePath) {
      _resolveImageSize();
    }
  }

  @override
  void dispose() {
    _detachImageStream();
    super.dispose();
  }

  void _detachImageStream() {
    if (_imageStreamListener != null && _imageStream != null) {
      _imageStream!.removeListener(_imageStreamListener!);
    }
    _imageStreamListener = null;
    _imageStream = null;
  }

  void _resolveImageSize() {
    _detachImageStream();
    _imageSize = null;

    final path = widget.content.imagePath;
    if (path == null || path.trim().isEmpty) {
      return;
    }

    final stream = FileImage(File(path)).resolve(ImageConfiguration.empty);
    _imageStreamListener = ImageStreamListener((info, _) {
      if (!mounted) {
        return;
      }
      setState(() {
        _imageSize = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
      });
    });
    stream.addListener(_imageStreamListener!);
    _imageStream = stream;
  }

  Rect get _slotRect {
    return Rect.fromLTWH(
      widget.definition.rect.left * widget.canvasSize.width,
      widget.definition.rect.top * widget.canvasSize.height,
      widget.definition.rect.width * widget.canvasSize.width,
      widget.definition.rect.height * widget.canvasSize.height,
    );
  }

  double get _displayScale => _liveScale ?? widget.content.scale;

  double get _displayFocalDx => _liveFocal?.dx ?? widget.content.focalDx;

  double get _displayFocalDy => _liveFocal?.dy ?? widget.content.focalDy;

  Rect get _contentBounds {
    return layoutShapeContentBounds(
      shape: widget.content.shape,
      slotSize: _slotRect.size,
      cornerRadius: widget.definition.cornerRadius,
    );
  }

  Offset _clampFocal(Offset focal, double scale) {
    return clampLayoutSlotFocal(
      focal: focal,
      slotSize: _contentBounds.size,
      imageSize: _imageSize,
      userZoom: scale,
    );
  }

  void _commitTransform({required bool treatAsTap}) {
    if (treatAsTap) {
      widget.onTap();
      return;
    }

    final scale = _liveScale ?? widget.content.scale;
    final focal = _clampFocal(
      _liveFocal ?? Offset(widget.content.focalDx, widget.content.focalDy),
      scale,
    );
    widget.onTransformEnd?.call(scale, focal);
    if (mounted) {
      setState(() {
        _liveScale = null;
        _liveFocal = null;
        _didPanOrZoom = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rect = _slotRect;
    if (rect.width <= 0 || rect.height <= 0) {
      return const SizedBox.shrink();
    }

    final slotSize = rect.size;

    return Positioned.fromRect(
      rect: rect,
      child: RepaintBoundary(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.canTransform ? null : widget.onTap,
          onScaleStart: widget.canTransform
              ? (_) {
                  _didPanOrZoom = false;
                  _gestureStartScale = widget.content.scale;
                  _gestureStartFocal = Offset(
                    widget.content.focalDx,
                    widget.content.focalDy,
                  );
                }
              : null,
          onScaleUpdate: widget.canTransform
              ? (details) {
                  if (details.focalPointDelta.distanceSquared > 1 ||
                      (details.scale - 1).abs() > 0.001) {
                    _didPanOrZoom = true;
                  }
                  final nextScale =
                      (_gestureStartScale * details.scale).clamp(1.0, 3.0);
                  final runningFocal = _liveFocal ?? _gestureStartFocal;
                  final focalDelta = layoutSlotFocalDeltaForPan(
                    pointerDelta: details.focalPointDelta,
                    slotSize: _contentBounds.size,
                    imageSize: _imageSize,
                    userZoom: nextScale,
                  );
                  setState(() {
                    _liveScale = nextScale;
                    _liveFocal = _clampFocal(
                      runningFocal + focalDelta,
                      nextScale,
                    );
                  });
                }
              : null,
          onScaleEnd: widget.canTransform
              ? (_) => _commitTransform(treatAsTap: !_didPanOrZoom)
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!widget.content.hasImage && widget.showEmptyHint)
                const _EmptySlotPlaceholder(hasImage: false),
              if (widget.content.hasImage)
                _LayoutSlotClip(
                  shape: widget.content.shape,
                  cornerRadius: widget.definition.cornerRadius,
                  child: _SlotFileImage(
                    path: widget.content.imagePath!,
                    shape: widget.content.shape,
                    cornerRadius: widget.definition.cornerRadius,
                    slotSize: slotSize,
                    scale: _displayScale,
                    focalDx: _displayFocalDx,
                    focalDy: _displayFocalDy,
                    imageSize: _imageSize,
                    cacheWidth: widget.previewCacheWidth,
                  ),
                ),
              if (widget.content.borderColor != null &&
                  widget.content.borderWidth > 0)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _SlotBorderPainter(
                      shape: widget.content.shape,
                      cornerRadius: widget.definition.cornerRadius,
                      color: widget.content.borderColor!,
                      strokeWidth: widget.content.borderWidth,
                    ),
                  ),
                ),
              if (widget.isSelected)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _SlotSelectionPainter(
                      shape: widget.content.shape,
                      cornerRadius: widget.definition.cornerRadius,
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

/// Uses engine clippers for the common silhouettes; complex shapes still use
/// [ClipPath], but only through [safeLayoutShapePath].
class _LayoutSlotClip extends StatelessWidget {
  const _LayoutSlotClip({
    required this.shape,
    required this.cornerRadius,
    required this.child,
  });

  final LayoutShapeId shape;
  final double cornerRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.width <= 0 || size.height <= 0) {
          return child;
        }

        switch (shape) {
          case LayoutShapeId.rectangle:
            if (cornerRadius <= 0) {
              return ClipRect(child: child);
            }
            final radius = (cornerRadius * size.shortestSide)
                .clamp(0.0, size.shortestSide / 2);
            return ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: child,
            );
          case LayoutShapeId.roundedRect:
            return ClipRRect(
              borderRadius: BorderRadius.circular(size.shortestSide * 0.12),
              child: child,
            );
          case LayoutShapeId.circle:
          case LayoutShapeId.oval:
            return ClipPath(
              clipBehavior: Clip.hardEdge,
              clipper: LayoutShapeClipper(
                shape: shape,
                cornerRadius: cornerRadius,
              ),
              child: child,
            );
          default:
            return ClipPath(
              clipBehavior: Clip.hardEdge,
              clipper: LayoutShapeClipper(
                shape: shape,
                cornerRadius: cornerRadius,
              ),
              child: child,
            );
        }
      },
    );
  }
}

class _SlotFileImage extends StatelessWidget {
  const _SlotFileImage({
    required this.path,
    required this.shape,
    required this.cornerRadius,
    required this.slotSize,
    required this.scale,
    required this.focalDx,
    required this.focalDy,
    required this.cacheWidth,
    this.imageSize,
  });

  final String path;
  final LayoutShapeId shape;
  final double cornerRadius;
  final Size slotSize;
  final double scale;
  final double focalDx;
  final double focalDy;
  final int cacheWidth;
  final Size? imageSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final clipSize = constraints.biggest;
        if (clipSize.width <= 0 || clipSize.height <= 0) {
          return const SizedBox.shrink();
        }

        if (imageSize == null ||
            imageSize!.width <= 0 ||
            imageSize!.height <= 0) {
          return Image.file(
            File(path),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                const _EmptySlotPlaceholder(hasImage: true),
          );
        }

        final contentBounds = layoutShapeContentBounds(
          shape: shape,
          slotSize: slotSize,
          cornerRadius: cornerRadius,
        );
        final frameSize = contentBounds.size;
        final userZoom = scale.clamp(1.0, 3.0);
        final renderedSize = layoutSlotRenderedImageSize(
          slotSize: frameSize,
          imageSize: imageSize!,
          userZoom: userZoom,
        );
        final pan = layoutSlotPanOffset(
          slotSize: frameSize,
          imageSize: imageSize!,
          userZoom: userZoom,
          focalDx: focalDx,
          focalDy: focalDy,
        );

        return ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: contentBounds.left +
                    (frameSize.width - renderedSize.width) / 2 +
                    pan.dx,
                top: contentBounds.top +
                    (frameSize.height - renderedSize.height) / 2 +
                    pan.dy,
                width: renderedSize.width,
                height: renderedSize.height,
                child: Image.file(
                  File(path),
                  fit: BoxFit.fill,
                  width: renderedSize.width,
                  height: renderedSize.height,
                  cacheWidth: cacheWidth,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) =>
                      const _EmptySlotPlaceholder(hasImage: true),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SlotBorderPainter extends CustomPainter {
  const _SlotBorderPainter({
    required this.shape,
    required this.cornerRadius,
    required this.color,
    required this.strokeWidth,
  });

  final LayoutShapeId shape;
  final double cornerRadius;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final path = safeLayoutShapePath(
      shape: shape,
      bounds: Offset.zero & size,
      cornerRadius: cornerRadius,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _SlotBorderPainter oldDelegate) {
    return oldDelegate.shape != shape ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class _SlotSelectionPainter extends CustomPainter {
  const _SlotSelectionPainter({
    required this.shape,
    required this.cornerRadius,
  });

  final LayoutShapeId shape;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final path = safeLayoutShapePath(
      shape: shape,
      bounds: Offset.zero & size,
      cornerRadius: cornerRadius,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF2AABEE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SlotSelectionPainter oldDelegate) {
    return oldDelegate.shape != shape;
  }
}

class _EmptySlotPlaceholder extends StatelessWidget {
  const _EmptySlotPlaceholder({required this.hasImage});

  final bool hasImage;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF1A1A1A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasImage
                  ? Icons.broken_image_outlined
                  : Icons.add_photo_alternate_outlined,
              color: Colors.white.withValues(alpha: 0.45),
              size: 32,
            ),
            if (!hasImage) ...[
              const SizedBox(height: 6),
              Text(
                'Tap to add',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
