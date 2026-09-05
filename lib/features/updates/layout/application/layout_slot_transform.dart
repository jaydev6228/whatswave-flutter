import 'dart:math' as math;
import 'dart:ui';

/// How far the image center may shift from the slot center, in pixels.
Offset layoutSlotPanExtents({
  required Size slotSize,
  required Size imageSize,
  required double userZoom,
}) {
  if (slotSize.width <= 0 ||
      slotSize.height <= 0 ||
      imageSize.width <= 0 ||
      imageSize.height <= 0) {
    return Offset.zero;
  }

  final zoom = userZoom.clamp(1.0, 3.0);
  final coverScale = math.max(
    slotSize.width / imageSize.width,
    slotSize.height / imageSize.height,
  );
  final totalScale = coverScale * zoom;
  final renderedW = imageSize.width * totalScale;
  final renderedH = imageSize.height * totalScale;
  return Offset(
    math.max(0, (renderedW - slotSize.width) / 2),
    math.max(0, (renderedH - slotSize.height) / 2),
  );
}

/// Pixel offset applied to a cover-fit image for normalized focal 0–1.
Offset layoutSlotPanOffset({
  required Size slotSize,
  required Size imageSize,
  required double userZoom,
  required double focalDx,
  required double focalDy,
}) {
  final extents = layoutSlotPanExtents(
    slotSize: slotSize,
    imageSize: imageSize,
    userZoom: userZoom,
  );
  return Offset(
    (0.5 - focalDx) * 2 * extents.dx,
    (0.5 - focalDy) * 2 * extents.dy,
  );
}

Size layoutSlotRenderedImageSize({
  required Size slotSize,
  required Size imageSize,
  required double userZoom,
}) {
  final zoom = userZoom.clamp(1.0, 3.0);
  final coverScale = math.max(
    slotSize.width / imageSize.width,
    slotSize.height / imageSize.height,
  );
  final totalScale = coverScale * zoom;
  return Size(
    imageSize.width * totalScale,
    imageSize.height * totalScale,
  );
}

/// Clamps focal to valid pan range; axes with no overflow lock to center.
Offset clampLayoutSlotFocal({
  required Offset focal,
  required Size slotSize,
  required Size? imageSize,
  required double userZoom,
}) {
  if (imageSize == null ||
      imageSize.width <= 0 ||
      imageSize.height <= 0 ||
      slotSize.width <= 0 ||
      slotSize.height <= 0) {
    return Offset(
      focal.dx.clamp(0.0, 1.0),
      focal.dy.clamp(0.0, 1.0),
    );
  }

  final extents = layoutSlotPanExtents(
    slotSize: slotSize,
    imageSize: imageSize,
    userZoom: userZoom,
  );
  return Offset(
    extents.dx > 0.5 ? focal.dx.clamp(0.0, 1.0) : 0.5,
    extents.dy > 0.5 ? focal.dy.clamp(0.0, 1.0) : 0.5,
  );
}

/// Maps a finger delta (pixels) to a normalized focal delta.
Offset layoutSlotFocalDeltaForPan({
  required Offset pointerDelta,
  required Size slotSize,
  required Size? imageSize,
  required double userZoom,
}) {
  if (imageSize == null) {
    final norm = math.max(slotSize.shortestSide, 48.0);
    return Offset(-pointerDelta.dx / norm, -pointerDelta.dy / norm);
  }

  final extents = layoutSlotPanExtents(
    slotSize: slotSize,
    imageSize: imageSize,
    userZoom: userZoom,
  );
  return Offset(
    extents.dx > 0.5 ? -pointerDelta.dx / (2 * extents.dx) : 0,
    extents.dy > 0.5 ? -pointerDelta.dy / (2 * extents.dy) : 0,
  );
}
