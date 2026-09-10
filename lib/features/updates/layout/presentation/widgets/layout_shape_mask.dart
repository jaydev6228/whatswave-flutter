import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/layout_models.dart';
import 'layout_shape_clipper.dart';

/// PNG alpha masks extracted from the user's shape screenshots.
String? layoutShapeMaskAsset(LayoutShapeId shape) {
  return switch (shape) {
    LayoutShapeId.brushWide || LayoutShapeId.brushStroke =>
      'assets/layout/shapes/brush_h1.png',
    LayoutShapeId.brushH2 => 'assets/layout/shapes/brush_h2.png',
    LayoutShapeId.brushH3 => 'assets/layout/shapes/brush_h3.png',
    LayoutShapeId.roughCircle => 'assets/layout/shapes/brush_round.png',
    LayoutShapeId.brushDiagonal => 'assets/layout/shapes/brush_diag.png',
    LayoutShapeId.brushTall => 'assets/layout/shapes/brush_v.png',
    LayoutShapeId.brushBlock || LayoutShapeId.tornPaper =>
      'assets/layout/shapes/brush_block.png',
    LayoutShapeId.brushSplat => 'assets/layout/shapes/brush_splat.png',
    LayoutShapeId.sealCircle => 'assets/layout/shapes/seal.png',
    LayoutShapeId.leafCorners => 'assets/layout/shapes/leaf_corners.png',
    LayoutShapeId.speechRound => 'assets/layout/shapes/speech.png',
    LayoutShapeId.roundedStar => 'assets/layout/shapes/star_soft.png',
    LayoutShapeId.blob => 'assets/layout/shapes/blob.png',
    LayoutShapeId.cloud => 'assets/layout/shapes/cloud.png',
    LayoutShapeId.stepLeaf => 'assets/layout/shapes/step_leaf.png',
    LayoutShapeId.brokenHeart => 'assets/layout/shapes/broken_heart.png',
    LayoutShapeId.brokenHeartLeft => 'assets/layout/shapes/broken_heart_l.png',
    LayoutShapeId.brokenHeartRight => 'assets/layout/shapes/broken_heart_r.png',
    _ => null,
  };
}

const Map<String, Size> _kMaskPixelSizes = <String, Size>{
  'assets/layout/shapes/brush_h1.png': Size(979, 823),
  'assets/layout/shapes/brush_h2.png': Size(1023, 841),
  'assets/layout/shapes/brush_h3.png': Size(1035, 799),
  'assets/layout/shapes/brush_round.png': Size(978, 949),
  'assets/layout/shapes/brush_diag.png': Size(1007, 1059),
  'assets/layout/shapes/brush_v.png': Size(675, 1809),
  'assets/layout/shapes/brush_block.png': Size(964, 1199),
  'assets/layout/shapes/brush_splat.png': Size(1006, 987),
  'assets/layout/shapes/seal.png': Size(950, 950),
  'assets/layout/shapes/leaf_corners.png': Size(956, 955),
  'assets/layout/shapes/speech.png': Size(985, 938),
  'assets/layout/shapes/star_soft.png': Size(976, 975),
  'assets/layout/shapes/blob.png': Size(930, 929),
  'assets/layout/shapes/cloud.png': Size(974, 748),
  'assets/layout/shapes/step_leaf.png': Size(1026, 1211),
  'assets/layout/shapes/broken_heart.png': Size(1029, 887),
  'assets/layout/shapes/broken_heart_l.png': Size(567, 875),
  'assets/layout/shapes/broken_heart_r.png': Size(556, 852),
};

/// Where the PNG mask is drawn inside [slotSize] (contain, centered).
Rect? layoutShapeMaskDestRect({
  required LayoutShapeId shape,
  required Size slotSize,
  Size? imageSize,
}) {
  final maskSize = imageSize ??
      _kMaskPixelSizes[layoutShapeMaskAsset(shape) ?? ''];
  if (maskSize == null ||
      maskSize.isEmpty ||
      slotSize.width <= 0 ||
      slotSize.height <= 0) {
    return null;
  }
  final fitted = applyBoxFit(BoxFit.contain, maskSize, slotSize);
  return Alignment.center.inscribe(fitted.destination, Offset.zero & slotSize);
}

void paintLayoutShapeMask({
  required Canvas canvas,
  required ui.Image image,
  required Rect dest,
  required Paint paint,
}) {
  canvas.drawImageRect(
    image,
    Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
    dest,
    paint,
  );
}

/// Ring around the photo mask so looks follow the silhouette, not the slot.
void paintLayoutShapeMaskOutline({
  required Canvas canvas,
  required ui.Image image,
  required Rect dest,
  required Color color,
  required double width,
}) {
  final pad = width.clamp(1.0, 24.0);
  canvas.saveLayer(dest.inflate(pad + 2), Paint());
  paintLayoutShapeMask(
    canvas: canvas,
    image: image,
    dest: dest.inflate(pad),
    paint: Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
  );
  paintLayoutShapeMask(
    canvas: canvas,
    image: image,
    dest: dest,
    paint: Paint()..blendMode = BlendMode.dstOut,
  );
  canvas.restore();
}

void paintLayoutShapeMaskShadow({
  required Canvas canvas,
  required ui.Image image,
  required Rect dest,
  required Color color,
  required bool soft,
}) {
  canvas.save();
  canvas.translate(0, soft ? 3 : 4);
  paintLayoutShapeMask(
    canvas: canvas,
    image: image,
    dest: dest,
    paint: Paint()
      ..colorFilter = ColorFilter.mode(
        color.withValues(alpha: soft ? 0.45 : 0.55),
        BlendMode.srcIn,
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, soft ? 8 : 10),
  );
  canvas.restore();
}

final Map<String, Future<ui.Image>> _maskCache = <String, Future<ui.Image>>{};

Future<ui.Image> loadLayoutShapeMask(String asset) {
  return _maskCache.putIfAbsent(asset, () async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  });
}

/// Clips [child] with a screenshot PNG mask (holes and bristles included).
class LayoutShapeMaskClip extends StatefulWidget {
  const LayoutShapeMaskClip({
    required this.asset,
    required this.fallbackShape,
    required this.cornerRadius,
    required this.child,
    super.key,
  });

  final String asset;
  final LayoutShapeId fallbackShape;
  final double cornerRadius;
  final Widget child;

  @override
  State<LayoutShapeMaskClip> createState() => _LayoutShapeMaskClipState();
}

class _LayoutShapeMaskClipState extends State<LayoutShapeMaskClip> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LayoutShapeMaskClip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) {
      _image = null;
      _load();
    }
  }

  Future<void> _load() async {
    final image = await loadLayoutShapeMask(widget.asset);
    if (!mounted) {
      return;
    }
    setState(() => _image = image);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return ClipPath(
        clipBehavior: Clip.hardEdge,
        clipper: LayoutShapeClipper(
          shape: widget.fallbackShape,
          cornerRadius: widget.cornerRadius,
        ),
        child: widget.child,
      );
    }

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final imageSize = Size(image.width.toDouble(), image.height.toDouble());
        final fitted = applyBoxFit(BoxFit.contain, imageSize, bounds.size);
        final dest = Alignment.center.inscribe(fitted.destination, bounds);
        final matrix = Matrix4.identity()
          ..translate(dest.left, dest.top)
          ..scale(dest.width / imageSize.width, dest.height / imageSize.height);
        return ImageShader(
          image,
          TileMode.decal,
          TileMode.decal,
          matrix.storage,
        );
      },
      child: widget.child,
    );
  }
}
