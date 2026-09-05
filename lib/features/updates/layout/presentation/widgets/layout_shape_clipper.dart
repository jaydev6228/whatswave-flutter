import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/layout_models.dart';

/// Same as [layoutShapePath] but never returns a degenerate path — complex
/// silhouettes fall back to a rounded rect instead of aborting Skia clipping.
Path safeLayoutShapePath({
  required LayoutShapeId shape,
  required Rect bounds,
  double cornerRadius = 0,
}) {
  if (bounds.width <= 0 || bounds.height <= 0) {
    return Path();
  }

  try {
    final path = layoutShapePath(
      shape: shape,
      bounds: bounds,
      cornerRadius: cornerRadius,
    );
    final pathBounds = path.getBounds();
    if (pathBounds.width <= 0 || pathBounds.height <= 0) {
      return _fallbackRectPath(bounds);
    }
    return path;
  } catch (_) {
    return _fallbackRectPath(bounds);
  }
}

Path _fallbackRectPath(Rect bounds) {
  return Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        bounds,
        Radius.circular(bounds.shortestSide * 0.08),
      ),
    );
}

Path layoutShapePath({
  required LayoutShapeId shape,
  required Rect bounds,
  double cornerRadius = 0,
}) {
  switch (shape) {
    case LayoutShapeId.rectangle:
      if (cornerRadius <= 0) {
        return Path()..addRect(bounds);
      }
      final radius = cornerRadius * bounds.shortestSide;
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(bounds, Radius.circular(radius)),
        );
    case LayoutShapeId.roundedRect:
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            bounds,
            Radius.circular(bounds.shortestSide * 0.12),
          ),
        );
    case LayoutShapeId.circle:
      return Path()..addOval(_inscribedSquare(bounds));
    case LayoutShapeId.oval:
      return Path()..addOval(_verticalOvalRect(bounds));
    case LayoutShapeId.arch:
      return _archPath(bounds);
    case LayoutShapeId.heart:
      return _heartPath(bounds);
    case LayoutShapeId.diamond:
      return _diamondPath(bounds);
    case LayoutShapeId.roundedDiamond:
      return _roundedDiamondPath(bounds);
    case LayoutShapeId.star:
      return _starPath(bounds);
    case LayoutShapeId.blob:
      return _blobPath(bounds);
    case LayoutShapeId.speechBubble:
      return _speechBubblePath(bounds);
    case LayoutShapeId.shield:
      return _shieldPath(bounds);
    case LayoutShapeId.clippedRect:
      return _clippedRectPath(bounds);
    case LayoutShapeId.concave:
      return _concavePath(bounds);
    case LayoutShapeId.banner:
      return _bannerPath(bounds);
    case LayoutShapeId.hexagon:
      return _regularPolygonPath(bounds, 6);
    case LayoutShapeId.triangle:
      return _regularPolygonPath(bounds, 3);
    case LayoutShapeId.teardrop:
      return _teardropPath(bounds);
    case LayoutShapeId.ticket:
      return _ticketPath(bounds);
  }
}

Rect _inscribedSquare(Rect bounds) {
  final side = bounds.shortestSide;
  return Rect.fromCenter(
    center: bounds.center,
    width: side,
    height: side,
  );
}

/// Vertical egg silhouette — matches the shape-picker tile proportions so the
/// canvas mask looks like the icon the user tapped (not a near-circle in wide
/// row slots).
Rect _verticalOvalRect(Rect bounds) {
  // Shape picker tiles are 52×68.
  const ovalHeightOverWidth = 68 / 52;
  final maxWidth = bounds.width * 0.92;
  final maxHeight = bounds.height * 0.92;

  var width = maxWidth;
  var height = width * ovalHeightOverWidth;
  if (height > maxHeight) {
    height = maxHeight;
    width = height / ovalHeightOverWidth;
  }

  return Rect.fromCenter(
    center: bounds.center,
    width: width,
    height: height,
  );
}

Path _archPath(Rect bounds) {
  final path = Path();
  final topRadius = bounds.width * 0.5;
  path.moveTo(bounds.left, bounds.bottom);
  path.lineTo(bounds.left, bounds.top + topRadius);
  path.arcToPoint(
    Offset(bounds.right, bounds.top + topRadius),
    radius: Radius.circular(topRadius),
    clockwise: true,
  );
  path.lineTo(bounds.right, bounds.bottom);
  path.close();
  return path;
}

Path _heartPath(Rect bounds) {
  final width = bounds.width;
  final height = bounds.height;
  final path = Path();
  path.moveTo(bounds.center.dx, bounds.top + height * 0.28);
  path.cubicTo(
    bounds.left + width * 0.1,
    bounds.top,
    bounds.left,
    bounds.top + height * 0.42,
    bounds.center.dx,
    bounds.bottom,
  );
  path.cubicTo(
    bounds.right,
    bounds.top + height * 0.42,
    bounds.right - width * 0.1,
    bounds.top,
    bounds.center.dx,
    bounds.top + height * 0.28,
  );
  path.close();
  return path;
}

Path _diamondPath(Rect bounds) {
  final path = Path();
  path.moveTo(bounds.center.dx, bounds.top);
  path.lineTo(bounds.right, bounds.center.dy);
  path.lineTo(bounds.center.dx, bounds.bottom);
  path.lineTo(bounds.left, bounds.center.dy);
  path.close();
  return path;
}

Path _starPath(Rect bounds) {
  final path = Path();
  final center = bounds.center;
  final outerRadius = bounds.shortestSide * 0.48;
  final innerRadius = outerRadius * 0.45;
  const points = 5;
  for (var index = 0; index < points * 2; index++) {
    final radius = index.isEven ? outerRadius : innerRadius;
    final angle = -math.pi / 2 + index * math.pi / points;
    final point = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    if (index == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  path.close();
  return path;
}

Path _blobPath(Rect bounds) {
  final path = Path();
  path.moveTo(bounds.left + bounds.width * 0.12, bounds.center.dy);
  path.quadraticBezierTo(
    bounds.left,
    bounds.top,
    bounds.center.dx,
    bounds.top + bounds.height * 0.08,
  );
  path.quadraticBezierTo(
    bounds.right,
    bounds.top + bounds.height * 0.02,
    bounds.right - bounds.width * 0.08,
    bounds.center.dy,
  );
  path.quadraticBezierTo(
    bounds.right,
    bounds.bottom,
    bounds.center.dx,
    bounds.bottom - bounds.height * 0.06,
  );
  path.quadraticBezierTo(
    bounds.left,
    bounds.bottom - bounds.height * 0.04,
    bounds.left + bounds.width * 0.12,
    bounds.center.dy,
  );
  path.close();
  return path;
}

Path _speechBubblePath(Rect bounds) {
  // One closed contour — multi-subpath bubbles have crashed ClipPath on iOS.
  final width = bounds.width;
  final height = bounds.height;
  final bodyBottom = bounds.top + height * 0.78;
  final radius = width * 0.1;
  final tailX = bounds.left + width * 0.28;
  final path = Path();
  path.moveTo(bounds.left + radius, bounds.top);
  path.lineTo(bounds.right - radius, bounds.top);
  path.quadraticBezierTo(bounds.right, bounds.top, bounds.right, bounds.top + radius);
  path.lineTo(bounds.right, bodyBottom - radius);
  path.quadraticBezierTo(
    bounds.right,
    bodyBottom,
    bounds.right - radius,
    bodyBottom,
  );
  path.lineTo(tailX + width * 0.08, bodyBottom);
  path.lineTo(tailX, bounds.bottom);
  path.lineTo(tailX - width * 0.06, bodyBottom);
  path.lineTo(bounds.left + radius, bodyBottom);
  path.quadraticBezierTo(bounds.left, bodyBottom, bounds.left, bodyBottom - radius);
  path.lineTo(bounds.left, bounds.top + radius);
  path.quadraticBezierTo(bounds.left, bounds.top, bounds.left + radius, bounds.top);
  path.close();
  return path;
}

Path _roundedDiamondPath(Rect bounds) {
  final inset = bounds.shortestSide * 0.08;
  return _diamondPath(bounds.deflate(inset));
}

Path _shieldPath(Rect bounds) {
  final path = Path();
  path.moveTo(bounds.left, bounds.top + bounds.height * 0.08);
  path.lineTo(bounds.left, bounds.top + bounds.height * 0.58);
  path.quadraticBezierTo(
    bounds.left,
    bounds.bottom,
    bounds.center.dx,
    bounds.bottom,
  );
  path.quadraticBezierTo(
    bounds.right,
    bounds.bottom,
    bounds.right,
    bounds.top + bounds.height * 0.58,
  );
  path.lineTo(bounds.right, bounds.top + bounds.height * 0.08);
  path.quadraticBezierTo(
    bounds.center.dx,
    bounds.top,
    bounds.left,
    bounds.top + bounds.height * 0.08,
  );
  path.close();
  return path;
}

Path _clippedRectPath(Rect bounds) {
  final cut = bounds.shortestSide * 0.28;
  final path = Path();
  path.moveTo(bounds.left, bounds.top);
  path.lineTo(bounds.right, bounds.top);
  path.lineTo(bounds.right, bounds.bottom);
  path.lineTo(bounds.left + cut, bounds.bottom);
  path.lineTo(bounds.left, bounds.bottom - cut);
  path.close();
  return path;
}

Path _concavePath(Rect bounds) {
  final dent = bounds.shortestSide * 0.18;
  final path = Path();
  path.moveTo(bounds.left + dent, bounds.top);
  path.quadraticBezierTo(
    bounds.center.dx,
    bounds.top + dent,
    bounds.right - dent,
    bounds.top,
  );
  path.lineTo(bounds.right, bounds.top + dent);
  path.quadraticBezierTo(
    bounds.right - dent,
    bounds.center.dy,
    bounds.right,
    bounds.bottom - dent,
  );
  path.lineTo(bounds.right - dent, bounds.bottom);
  path.quadraticBezierTo(
    bounds.center.dx,
    bounds.bottom - dent,
    bounds.left + dent,
    bounds.bottom,
  );
  path.lineTo(bounds.left, bounds.bottom - dent);
  path.quadraticBezierTo(
    bounds.left + dent,
    bounds.center.dy,
    bounds.left,
    bounds.top + dent,
  );
  path.close();
  return path;
}

Path _bannerPath(Rect bounds) {
  final notch = bounds.height * 0.22;
  final path = Path();
  path.moveTo(bounds.left, bounds.top);
  path.lineTo(bounds.right, bounds.top);
  path.lineTo(bounds.right, bounds.bottom);
  path.lineTo(bounds.center.dx, bounds.bottom - notch);
  path.lineTo(bounds.left, bounds.bottom);
  path.close();
  return path;
}

Path _regularPolygonPath(Rect bounds, int sides) {
  final path = Path();
  final center = bounds.center;
  final radius = bounds.shortestSide * 0.48;
  for (var index = 0; index < sides; index++) {
    final angle = -math.pi / 2 + index * 2 * math.pi / sides;
    final point = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    if (index == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  path.close();
  return path;
}

Path _teardropPath(Rect bounds) {
  // Tip at the top centre, a circle resting on the bottom edge, joined by the
  // two tangent lines. Built from the circle outwards so the silhouette can
  // never bulge past the slot the way a fixed-radius arc did.
  final radius = math.min(bounds.width / 2, bounds.height * 0.42);
  final center = Offset(bounds.center.dx, bounds.bottom - radius);
  final tip = Offset(bounds.center.dx, bounds.top);
  final tipDistance = center.dy - tip.dy;
  if (radius <= 0 || tipDistance <= radius) {
    return Path()..addOval(Rect.fromCircle(center: bounds.center, radius: radius));
  }

  // Angle between the centre→tip axis and each tangent point.
  final tangentAngle = math.acos(radius / tipDistance);
  final startAngle = tangentAngle - math.pi / 2;
  final sweepAngle = 2 * math.pi - 2 * tangentAngle;

  final path = Path()..moveTo(tip.dx, tip.dy);
  path.arcTo(
    Rect.fromCircle(center: center, radius: radius),
    startAngle,
    sweepAngle,
    false,
  );
  path.close();
  return path;
}

Path _ticketPath(Rect bounds) {
  // Path.combine can abort on some Skia builds. Draw the notches as part
  // of one contour instead.
  final notch = bounds.shortestSide * 0.12;
  final radius = bounds.shortestSide * 0.08;
  final midY = bounds.center.dy;
  final path = Path();
  path.moveTo(bounds.left + radius, bounds.top);
  path.lineTo(bounds.right - radius, bounds.top);
  path.quadraticBezierTo(
    bounds.right,
    bounds.top,
    bounds.right,
    bounds.top + radius,
  );
  path.lineTo(bounds.right, midY - notch);
  path.arcToPoint(
    Offset(bounds.right, midY + notch),
    radius: Radius.circular(notch),
    clockwise: false,
  );
  path.lineTo(bounds.right, bounds.bottom - radius);
  path.quadraticBezierTo(
    bounds.right,
    bounds.bottom,
    bounds.right - radius,
    bounds.bottom,
  );
  path.lineTo(bounds.left + radius, bounds.bottom);
  path.quadraticBezierTo(
    bounds.left,
    bounds.bottom,
    bounds.left,
    bounds.bottom - radius,
  );
  path.lineTo(bounds.left, midY + notch);
  path.arcToPoint(
    Offset(bounds.left, midY - notch),
    radius: Radius.circular(notch),
    clockwise: false,
  );
  path.lineTo(bounds.left, bounds.top + radius);
  path.quadraticBezierTo(
    bounds.left,
    bounds.top,
    bounds.left + radius,
    bounds.top,
  );
  path.close();
  return path;
}

/// Bounding rect the photo should cover-fit and pan within — matches the
/// visible shape, not the full slot (critical for circles in tall slots).
Rect layoutShapeContentBounds({
  required LayoutShapeId shape,
  required Size slotSize,
  double cornerRadius = 0,
}) {
  if (slotSize.width <= 0 || slotSize.height <= 0) {
    return Rect.zero;
  }
  final bounds = Offset.zero & slotSize;
  // [Path.getBounds] is conservative around arcs, and nothing outside the slot
  // is painted anyway, so keep the result inside the slot.
  return safeLayoutShapePath(
    shape: shape,
    bounds: bounds,
    cornerRadius: cornerRadius,
  ).getBounds().intersect(bounds);
}

class LayoutShapeClipper extends CustomClipper<Path> {
  const LayoutShapeClipper({
    required this.shape,
    this.cornerRadius = 0,
  });

  final LayoutShapeId shape;
  final double cornerRadius;

  @override
  Path getClip(Size size) {
    return safeLayoutShapePath(
      shape: shape,
      bounds: Offset.zero & size,
      cornerRadius: cornerRadius,
    );
  }

  @override
  bool shouldReclip(covariant LayoutShapeClipper oldClipper) {
    return oldClipper.shape != shape ||
        oldClipper.cornerRadius != cornerRadius;
  }
}

/// Draws a grey silhouette for template/shape picker thumbnails.
class LayoutShapePreviewPainter extends CustomPainter {
  const LayoutShapePreviewPainter({
    required this.shape,
    this.fillColor = const Color(0xFFD8D8D8),
    this.strokeColor = const Color(0xFFEFEFEF),
  });

  final LayoutShapeId shape;
  final Color fillColor;
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final path = safeLayoutShapePath(
      shape: shape,
      bounds: bounds.deflate(2),
    );
    canvas.drawPath(path, Paint()..color = fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant LayoutShapePreviewPainter oldDelegate) {
    return oldDelegate.shape != shape;
  }
}

/// Draws slot dividers for a layout template thumbnail.
class LayoutTemplatePreviewPainter extends CustomPainter {
  const LayoutTemplatePreviewPainter({
    required this.template,
    this.fillColor = const Color(0xFFD8D8D8),
    this.gutterColor = const Color(0xFFFFFFFF),
  });

  final LayoutTemplate template;
  final Color fillColor;
  final Color gutterColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = gutterColor);
    for (final slot in template.slots) {
      final rect = Rect.fromLTWH(
        slot.rect.left * size.width,
        slot.rect.top * size.height,
        slot.rect.width * size.width,
        slot.rect.height * size.height,
      );
      final path = safeLayoutShapePath(
        shape: slot.defaultShape,
        bounds: rect.deflate(0.5),
        cornerRadius: slot.cornerRadius,
      );
      canvas.drawPath(path, Paint()..color = fillColor);
    }
  }

  @override
  bool shouldRepaint(covariant LayoutTemplatePreviewPainter oldDelegate) {
    return oldDelegate.template.id != template.id;
  }
}
