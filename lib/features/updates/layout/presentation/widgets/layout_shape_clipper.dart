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
    case LayoutShapeId.square:
      return Path()..addRect(_inscribedSquare(bounds));
    case LayoutShapeId.squircle:
      return _squirclePath(bounds);
    case LayoutShapeId.capsule:
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            bounds,
            Radius.circular(bounds.shortestSide / 2),
          ),
        );
    case LayoutShapeId.pentagon:
      return _regularPolygonPath(bounds, 5);
    case LayoutShapeId.octagon:
      return _regularPolygonPath(bounds, 8);
    case LayoutShapeId.cutCornerRect:
      return _cutCornerRectPath(bounds);
    case LayoutShapeId.oneRoundCorner:
      return _oneRoundCornerPath(bounds);
    case LayoutShapeId.dropCorner:
      return _dropCornerPath(bounds);
    case LayoutShapeId.leaf:
      return _leafPath(bounds);
    case LayoutShapeId.scallopedSquare:
      return _scallopedSquarePath(bounds, 4);
    case LayoutShapeId.quatrefoil:
      return _scallopedSquarePath(bounds, 1);
    case LayoutShapeId.scallopedCircle:
      return _scallopedCirclePath(bounds);
    case LayoutShapeId.cloud:
      return _cloudPath(bounds);
    case LayoutShapeId.sparkle:
      return _sparklePath(bounds);
    case LayoutShapeId.chevron:
      return _chevronPath(bounds);
    case LayoutShapeId.bittenCircle:
      return _bittenCirclePath(bounds);
    case LayoutShapeId.wavyFlag:
      return _wavyFlagPath(bounds);
    case LayoutShapeId.wavySides:
      return _wavySidesPath(bounds);
    case LayoutShapeId.pebble:
      return _pebblePath(bounds);
    case LayoutShapeId.brushStroke:
      return _brushStrokePath(bounds);
    case LayoutShapeId.horizontalOval:
      return Path()..addOval(_aspectFitRect(bounds, 1.7));
    case LayoutShapeId.tiltedOval:
      return _tiltedOvalPath(bounds);
    case LayoutShapeId.wavyBottom:
      return _wavyBottomPath(bounds);
    case LayoutShapeId.tornBottom:
      return _tornEdgePath(bounds, bottom: true);
    case LayoutShapeId.tornPaper:
      return _tornPaperPath(bounds);
    case LayoutShapeId.roughCircle:
      return _roughCirclePath(bounds);
    case LayoutShapeId.brushWide:
      return _brushBarPath(bounds, vertical: false);
    case LayoutShapeId.brushTall:
      return _brushBarPath(bounds, vertical: true);
    case LayoutShapeId.roundedStar:
      return _roundedStarPath(bounds, points: 5, innerRatio: 0.45);
    case LayoutShapeId.ribbon:
      return _ribbonPath(bounds);
    case LayoutShapeId.eightPointStar:
      return _roundedStarPath(bounds, points: 8, innerRatio: 0.58);
    case LayoutShapeId.speechRound:
      return _speechRoundPath(bounds);
    case LayoutShapeId.waveTop:
      return _waveFillPath(bounds, topWavy: false, bottomWavy: true, variant: 0);
    case LayoutShapeId.waveMid:
      return _waveFillPath(bounds, topWavy: true, bottomWavy: true, variant: 0);
    case LayoutShapeId.waveBottom:
      return _waveFillPath(bounds, topWavy: true, bottomWavy: false, variant: 0);
    case LayoutShapeId.waveTopB:
      return _waveFillPath(bounds, topWavy: false, bottomWavy: true, variant: 1);
    case LayoutShapeId.waveMidB:
      return _waveFillPath(bounds, topWavy: true, bottomWavy: true, variant: 1);
    case LayoutShapeId.waveBottomB:
      return _waveFillPath(bounds, topWavy: true, bottomWavy: false, variant: 1);
    case LayoutShapeId.slantDown:
      return _slantFillPath(bounds, kind: _SlantKind.top);
    case LayoutShapeId.slantMid:
      return _slantFillPath(bounds, kind: _SlantKind.mid);
    case LayoutShapeId.slantUp:
      return _slantFillPath(bounds, kind: _SlantKind.bottom);
    case LayoutShapeId.roundCornerTL:
      return _roundOneCornerPath(bounds, tl: true);
    case LayoutShapeId.roundCornerTR:
      return _roundOneCornerPath(bounds, tr: true);
    case LayoutShapeId.roundCornerBL:
      return _roundOneCornerPath(bounds, bl: true);
    case LayoutShapeId.roundCornerBR:
      return _roundOneCornerPath(bounds, br: true);
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

/// Largest centred rect of the given width/height ratio that fits [bounds].
/// Silhouettes with a natural proportion (hearts, clouds, polygons) use this
/// so they keep their shape instead of stretching with the slot.
Rect _aspectFitRect(Rect bounds, double aspect) {
  var width = bounds.width;
  var height = width / aspect;
  if (height > bounds.height) {
    height = bounds.height;
    width = height * aspect;
  }
  return Rect.fromCenter(
    center: bounds.center,
    width: width,
    height: height,
  );
}

/// Scales a unit polygon to fill [bounds] at its own natural proportion.
Path _fittedPolygonPath(List<Offset> unitPoints, Rect bounds) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final point in unitPoints) {
    minX = math.min(minX, point.dx);
    minY = math.min(minY, point.dy);
    maxX = math.max(maxX, point.dx);
    maxY = math.max(maxY, point.dy);
  }
  final natural = Rect.fromLTRB(minX, minY, maxX, maxY);
  if (natural.width <= 0 || natural.height <= 0) {
    return _fallbackRectPath(bounds);
  }
  final target = _aspectFitRect(bounds, natural.width / natural.height);

  final path = Path();
  for (var index = 0; index < unitPoints.length; index++) {
    final point = unitPoints[index];
    final mapped = Offset(
      target.left + (point.dx - natural.left) / natural.width * target.width,
      target.top + (point.dy - natural.top) / natural.height * target.height,
    );
    if (index == 0) {
      path.moveTo(mapped.dx, mapped.dy);
    } else {
      path.lineTo(mapped.dx, mapped.dy);
    }
  }
  path.close();
  return path;
}

/// Traces [points] but replaces each corner with a quadratic through it, so
/// the silhouette keeps the polygon's outline with softened vertices.
Path _roundedCornerPolygonPath(List<Offset> points, double corner) {
  final path = Path();
  for (var index = 0; index < points.length; index++) {
    final previous = points[(index - 1 + points.length) % points.length];
    final current = points[index];
    final next = points[(index + 1) % points.length];
    final entry = Offset.lerp(current, previous, corner)!;
    final exit = Offset.lerp(current, next, corner)!;
    if (index == 0) {
      path.moveTo(entry.dx, entry.dy);
    } else {
      path.lineTo(entry.dx, entry.dy);
    }
    path.quadraticBezierTo(current.dx, current.dy, exit.dx, exit.dy);
  }
  path.close();
  return path;
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
  // Hearts read wrong when they stretch with the slot, so draw into a square.
  final box = _aspectFitRect(bounds, 1);
  final w = box.width;
  final h = box.height;
  final l = box.left;
  final t = box.top;
  return Path()
    ..moveTo(l + w * 0.5, t + h * 0.30)
    // left lobe
    ..cubicTo(
      l + w * 0.42,
      t + h * 0.04,
      l + w * 0.01,
      t + h * 0.10,
      l + w * 0.03,
      t + h * 0.41,
    )
    // left flank down to the point
    ..cubicTo(
      l + w * 0.05,
      t + h * 0.63,
      l + w * 0.27,
      t + h * 0.79,
      l + w * 0.5,
      t + h,
    )
    // right flank back up
    ..cubicTo(
      l + w * 0.73,
      t + h * 0.79,
      l + w * 0.95,
      t + h * 0.63,
      l + w * 0.97,
      t + h * 0.41,
    )
    // right lobe
    ..cubicTo(
      l + w * 0.99,
      t + h * 0.10,
      l + w * 0.58,
      t + h * 0.04,
      l + w * 0.5,
      t + h * 0.30,
    )
    ..close();
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
  const points = 5;
  const innerRatio = 0.45;
  final unit = <Offset>[
    for (var index = 0; index < points * 2; index++)
      () {
        final radius = index.isEven ? 1.0 : innerRatio;
        final angle = -math.pi / 2 + index * math.pi / points;
        return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      }(),
  ];
  return _fittedPolygonPath(unit, bounds);
}

/// Smooth closed curve through radii sampled evenly around [bounds], joined
/// with Catmull-Rom tangents. Two different radius rings give two organic
/// silhouettes that still read as siblings in the rail.
Path _organicBlobPath(Rect bounds, List<double> radii) {
  final count = radii.length;
  final center = bounds.center;
  final rx = bounds.width / 2;
  final ry = bounds.height / 2;

  final points = <Offset>[
    for (var index = 0; index < count; index++)
      () {
        final angle = 2 * math.pi * index / count - math.pi / 2;
        return Offset(
          center.dx + rx * radii[index] * math.cos(angle),
          center.dy + ry * radii[index] * math.sin(angle),
        );
      }(),
  ];

  final path = Path()..moveTo(points[0].dx, points[0].dy);
  for (var index = 0; index < count; index++) {
    final previous = points[(index - 1 + count) % count];
    final start = points[index];
    final end = points[(index + 1) % count];
    final following = points[(index + 2) % count];
    final control1 = start + (end - previous) / 6;
    final control2 = end - (following - start) / 6;
    path.cubicTo(control1.dx, control1.dy, control2.dx, control2.dy, end.dx, end.dy);
  }
  path.close();
  return path;
}

Path _blobPath(Rect bounds) {
  return _organicBlobPath(bounds, const <double>[
    0.96, 0.90, 0.79, 0.72, 0.78, 0.89, 0.95, 0.93,
  ]);
}

Path _speechBubblePath(Rect bounds) {
  // One closed contour — multi-subpath bubbles have crashed ClipPath on iOS.
  final width = bounds.width;
  final height = bounds.height;
  final bodyBottom = bounds.top + height * 0.84;
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
  path.lineTo(tailX + width * 0.16, bodyBottom);
  path.lineTo(tailX - width * 0.02, bounds.bottom);
  path.lineTo(tailX - width * 0.12, bodyBottom);
  path.lineTo(bounds.left + radius, bodyBottom);
  path.quadraticBezierTo(bounds.left, bodyBottom, bounds.left, bodyBottom - radius);
  path.lineTo(bounds.left, bounds.top + radius);
  path.quadraticBezierTo(bounds.left, bounds.top, bounds.left + radius, bounds.top);
  path.close();
  return path;
}

Path _roundedDiamondPath(Rect bounds) {
  const corner = 0.3;
  final square = _inscribedSquare(bounds);
  final center = square.center;
  // A quadratic only reaches halfway to its control point, so grow the
  // diamond by the amount each rounded tip gives back and it ends up flush.
  final reach = 1 / (1 - 0.5 * corner);
  final rx = square.width / 2 * reach;
  final ry = square.height / 2 * reach;
  return _roundedCornerPolygonPath(
    <Offset>[
      Offset(center.dx, center.dy - ry),
      Offset(center.dx + rx, center.dy),
      Offset(center.dx, center.dy + ry),
      Offset(center.dx - rx, center.dy),
    ],
    corner,
  );
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
  // Flat-topped hexagons/octagons look better than point-topped ones; odd
  // polygons keep a vertex on top so triangles and pentagons point up.
  final rotation = sides.isEven ? math.pi / sides : 0.0;
  final unit = <Offset>[
    for (var index = 0; index < sides; index++)
      () {
        final angle =
            -math.pi / 2 + rotation + index * 2 * math.pi / sides;
        return Offset(math.cos(angle), math.sin(angle));
      }(),
  ];
  return _fittedPolygonPath(unit, bounds);
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

/// Superellipse (|x/a|⁴ + |y/b|⁴ = 1) — the "squircle" tile: squarer than a
/// rounded rect but with no straight-to-curve seam.
Path _squirclePath(Rect bounds) {
  const steps = 96;
  final a = bounds.width / 2;
  final b = bounds.height / 2;
  final center = bounds.center;
  final path = Path();
  for (var index = 0; index <= steps; index++) {
    final t = 2 * math.pi * index / steps;
    final point = Offset(
      center.dx + a * _signedPow(math.cos(t), 0.5),
      center.dy + b * _signedPow(math.sin(t), 0.5),
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

double _signedPow(double value, double exponent) {
  if (value == 0) {
    return 0;
  }
  return math.pow(value.abs(), exponent).toDouble() * value.sign;
}

Path _cutCornerRectPath(Rect bounds) {
  final cut = bounds.shortestSide * 0.2;
  return Path()
    ..moveTo(bounds.left + cut, bounds.top)
    ..lineTo(bounds.right - cut, bounds.top)
    ..lineTo(bounds.right, bounds.top + cut)
    ..lineTo(bounds.right, bounds.bottom - cut)
    ..lineTo(bounds.right - cut, bounds.bottom)
    ..lineTo(bounds.left + cut, bounds.bottom)
    ..lineTo(bounds.left, bounds.bottom - cut)
    ..lineTo(bounds.left, bounds.top + cut)
    ..close();
}

Path _oneRoundCornerPath(Rect bounds) {
  final big = bounds.shortestSide * 0.5;
  final small = bounds.shortestSide * 0.08;
  return Path()
    ..addRRect(
      RRect.fromRectAndCorners(
        bounds,
        topLeft: Radius.circular(big),
        topRight: Radius.circular(small),
        bottomLeft: Radius.circular(small),
        bottomRight: Radius.circular(big),
      ),
    );
}

/// Map-marker silhouette: rounded everywhere except a square bottom-left tip.
Path _dropCornerPath(Rect bounds) {
  final radius = bounds.shortestSide * 0.48;
  return Path()
    ..addRRect(
      RRect.fromRectAndCorners(
        bounds,
        topLeft: Radius.circular(radius),
        topRight: Radius.circular(radius),
        bottomRight: Radius.circular(radius),
      ),
    );
}

/// Two opposite pointed corners, two swept edges.
Path _leafPath(Rect bounds) {
  final box = _inscribedSquare(bounds);
  final w = box.width;
  final h = box.height;
  final l = box.left;
  final t = box.top;
  return Path()
    ..moveTo(l, t)
    ..cubicTo(l + w * 0.72, t, l + w, t + h * 0.28, l + w, t + h)
    ..cubicTo(l + w * 0.28, t + h, l, t + h * 0.72, l, t)
    ..close();
}

/// Semicircular bumps walked around an inner square. [bumpsPerSide] of 1 gives
/// a quatrefoil, 4 gives the flower-edged square from the reference rail.
///
/// The inner square and bump radius are sized so bump centres sit exactly
/// `2r` apart all the way round (corners included) and the bumps top out flush
/// with the slot — so the silhouette never spills past its bounds.
Path _scallopedSquarePath(Rect bounds, int bumpsPerSide) {
  final square = _inscribedSquare(bounds);
  final radius = square.width / (2 * (bumpsPerSide + 1));
  final inner = square.deflate(radius);
  if (inner.width <= 0 || radius <= 0) {
    return _fallbackRectPath(bounds);
  }
  final step = inner.width / bumpsPerSide;

  final centers = <Offset>[];
  for (var i = 0; i < bumpsPerSide; i++) {
    centers.add(Offset(inner.left + step * i, inner.top));
  }
  for (var i = 0; i < bumpsPerSide; i++) {
    centers.add(Offset(inner.right, inner.top + step * i));
  }
  for (var i = 0; i < bumpsPerSide; i++) {
    centers.add(Offset(inner.right - step * i, inner.bottom));
  }
  for (var i = 0; i < bumpsPerSide; i++) {
    centers.add(Offset(inner.left, inner.bottom - step * i));
  }

  final path = Path()..moveTo(centers.first.dx, centers.first.dy);
  for (var i = 1; i <= centers.length; i++) {
    final next = centers[i % centers.length];
    path.arcToPoint(next, radius: Radius.circular(radius));
  }
  path.close();
  return path;
}

/// Same trick on a circle — the cog/stamp edge.
Path _scallopedCirclePath(Rect bounds) {
  const bumps = 14;
  final outerRadius = bounds.shortestSide / 2;
  final bumpRadius =
      outerRadius * math.sin(math.pi / bumps) / (1 + math.sin(math.pi / bumps));
  final innerRadius = outerRadius - bumpRadius;
  final center = bounds.center;

  final path = Path();
  for (var i = 0; i <= bumps; i++) {
    final angle = -math.pi / 2 + 2 * math.pi * i / bumps;
    final point = Offset(
      center.dx + innerRadius * math.cos(angle),
      center.dy + innerRadius * math.sin(angle),
    );
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.arcToPoint(point, radius: Radius.circular(bumpRadius));
    }
  }
  path.close();
  return path;
}

/// Three lobes over a flat base. Every control point sits inside the box, so
/// the curves are contained by their convex hulls.
Path _cloudPath(Rect bounds) {
  final box = _aspectFitRect(bounds, 1.25);
  final w = box.width;
  final h = box.height;
  final l = box.left;
  final t = box.top;
  final baseY = t + h * 0.96;
  return Path()
    ..moveTo(l + w * 0.12, baseY)
    // left lobe
    ..cubicTo(l, baseY, l, t + h * 0.46, l + w * 0.20, t + h * 0.42)
    // notch between the left and middle lobes
    ..cubicTo(
      l + w * 0.26,
      t + h * 0.50,
      l + w * 0.26,
      t + h * 0.52,
      l + w * 0.30,
      t + h * 0.46,
    )
    // tall middle lobe
    ..cubicTo(
      l + w * 0.30,
      t + h * 0.02,
      l + w * 0.68,
      t,
      l + w * 0.70,
      t + h * 0.36,
    )
    // notch between the middle and right lobes
    ..cubicTo(
      l + w * 0.72,
      t + h * 0.43,
      l + w * 0.74,
      t + h * 0.41,
      l + w * 0.76,
      t + h * 0.36,
    )
    // right lobe
    ..cubicTo(
      l + w * 0.92,
      t + h * 0.30,
      l + w,
      t + h * 0.70,
      l + w * 0.88,
      baseY,
    )
    ..close();
}

/// Four-point concave star.
Path _sparklePath(Rect bounds) {
  final center = bounds.center;
  final rx = bounds.width / 2;
  final ry = bounds.height / 2;
  const waist = 0.18;
  return Path()
    ..moveTo(center.dx, center.dy - ry)
    ..quadraticBezierTo(
      center.dx + rx * waist,
      center.dy - ry * waist,
      center.dx + rx,
      center.dy,
    )
    ..quadraticBezierTo(
      center.dx + rx * waist,
      center.dy + ry * waist,
      center.dx,
      center.dy + ry,
    )
    ..quadraticBezierTo(
      center.dx - rx * waist,
      center.dy + ry * waist,
      center.dx - rx,
      center.dy,
    )
    ..quadraticBezierTo(
      center.dx - rx * waist,
      center.dy - ry * waist,
      center.dx,
      center.dy - ry,
    )
    ..close();
}

/// Downward arrow band — notched on both the top and bottom edge.
Path _chevronPath(Rect bounds) {
  final notch = bounds.height * 0.2;
  return Path()
    ..moveTo(bounds.left, bounds.top)
    ..lineTo(bounds.center.dx, bounds.top + notch)
    ..lineTo(bounds.right, bounds.top)
    ..lineTo(bounds.right, bounds.bottom - notch)
    ..lineTo(bounds.center.dx, bounds.bottom)
    ..lineTo(bounds.left, bounds.bottom - notch)
    ..close();
}

/// Circle with a rounded bite out of the upper right.
Path _bittenCirclePath(Rect bounds) {
  final square = _inscribedSquare(bounds);
  final center = square.center;
  final radius = square.width / 2;
  Offset onCircle(double degrees) {
    final angle = degrees * math.pi / 180;
    return Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
  }

  final start = onCircle(-78);
  final end = onCircle(30);
  return Path()
    ..moveTo(start.dx, start.dy)
    ..arcToPoint(
      end,
      radius: Radius.circular(radius),
      clockwise: false,
      largeArc: true,
    )
    // The bite curves back toward the centre, so it stays inside the circle.
    ..quadraticBezierTo(
      center.dx + radius * 0.18,
      center.dy - radius * 0.16,
      start.dx,
      start.dy,
    )
    ..close();
}

/// Ribbon: rippled top and bottom edges, straight sides.
Path _wavyFlagPath(Rect bounds) {
  final w = bounds.width;
  final amp = bounds.height * 0.07;
  final top = bounds.top + amp * 2;
  final bottom = bounds.bottom - amp * 2;
  return Path()
    ..moveTo(bounds.left, top)
    ..cubicTo(
      bounds.left + w * 0.33,
      top - amp * 2,
      bounds.left + w * 0.67,
      top + amp * 2,
      bounds.right,
      top,
    )
    ..lineTo(bounds.right, bottom)
    ..cubicTo(
      bounds.left + w * 0.67,
      bottom + amp * 2,
      bounds.left + w * 0.33,
      bottom - amp * 2,
      bounds.left,
      bottom,
    )
    ..close();
}

/// Bobbin: straight top and bottom, sides pinched toward the middle.
Path _wavySidesPath(Rect bounds) {
  final dent = bounds.width * 0.2;
  return Path()
    ..moveTo(bounds.left, bounds.top)
    ..lineTo(bounds.right, bounds.top)
    ..quadraticBezierTo(
      bounds.right - dent,
      bounds.center.dy,
      bounds.right,
      bounds.bottom,
    )
    ..lineTo(bounds.left, bounds.bottom)
    ..quadraticBezierTo(
      bounds.left + dent,
      bounds.center.dy,
      bounds.left,
      bounds.top,
    )
    ..close();
}

/// Asymmetric pebble — a second organic silhouette that reads differently
/// from [_blobPath] when both sit next to each other in the rail.
Path _pebblePath(Rect bounds) {
  return _organicBlobPath(bounds, const <double>[
    0.76, 0.86, 0.95, 0.91, 0.80, 0.73, 0.81, 0.90,
  ]);
}

List<Offset> _fittedPoints(List<Offset> unitPoints, Rect bounds) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final point in unitPoints) {
    minX = math.min(minX, point.dx);
    minY = math.min(minY, point.dy);
    maxX = math.max(maxX, point.dx);
    maxY = math.max(maxY, point.dy);
  }
  final natural = Rect.fromLTRB(minX, minY, maxX, maxY);
  if (natural.width <= 0 || natural.height <= 0) {
    return const <Offset>[];
  }
  final target = _aspectFitRect(bounds, natural.width / natural.height);
  return <Offset>[
    for (final point in unitPoints)
      Offset(
        target.left + (point.dx - natural.left) / natural.width * target.width,
        target.top + (point.dy - natural.top) / natural.height * target.height,
      ),
  ];
}

Path _tiltedOvalPath(Rect bounds) {
  final box = _inscribedSquare(bounds).deflate(bounds.shortestSide * 0.08);
  final oval = Rect.fromCenter(
    center: box.center,
    width: box.width * 0.72,
    height: box.height * 0.4,
  );
  final path = Path()..addOval(oval);
  final matrix = Matrix4.identity()
    ..translate(box.center.dx, box.center.dy)
    ..rotateZ(-0.55)
    ..translate(-box.center.dx, -box.center.dy);
  return path.transform(matrix.storage);
}

Path _wavyBottomPath(Rect bounds) {
  final amp = bounds.height * 0.1;
  return Path()
    ..moveTo(bounds.left, bounds.top)
    ..lineTo(bounds.right, bounds.top)
    ..lineTo(bounds.right, bounds.bottom - amp * 1.4)
    ..cubicTo(
      bounds.left + bounds.width * 0.72,
      bounds.bottom,
      bounds.left + bounds.width * 0.38,
      bounds.bottom - amp * 2.4,
      bounds.left,
      bounds.bottom - amp,
    )
    ..close();
}

Path _tornEdgePath(Rect bounds, {required bool bottom}) {
  final teeth = 9;
  final depth = bounds.height * 0.1;
  final path = Path()..moveTo(bounds.left, bounds.top);
  path.lineTo(bounds.right, bounds.top);
  if (bottom) {
    path.lineTo(bounds.right, bounds.bottom - depth);
    for (var i = teeth; i >= 0; i--) {
      final t = i / teeth;
      final jag = i.isEven ? 0.0 : depth;
      path.lineTo(
        bounds.left + bounds.width * t,
        bounds.bottom - jag,
      );
    }
  }
  path.lineTo(bounds.left, bounds.top);
  path.close();
  return path;
}

Path _tornPaperPath(Rect bounds) {
  final box = bounds.deflate(bounds.shortestSide * 0.1);
  final shear = box.width * 0.08;
  final jag = box.height * 0.06;
  return Path()
    ..moveTo(box.left + shear, box.top + jag)
    ..lineTo(box.right - shear * 0.2, box.top)
    ..lineTo(box.right - shear * 0.4, box.top + jag * 1.4)
    ..lineTo(box.right, box.top + jag * 0.4)
    ..lineTo(box.right - shear * 0.3, box.bottom - jag)
    ..lineTo(box.right - shear, box.bottom)
    ..lineTo(box.left + shear * 0.4, box.bottom - jag * 0.3)
    ..lineTo(box.left, box.bottom - jag * 1.2)
    ..close();
}

Path _roughCirclePath(Rect bounds) {
  return _organicBlobPath(
    _inscribedSquare(bounds).deflate(bounds.shortestSide * 0.04),
    const <double>[
      0.96, 0.74, 0.92, 0.70, 0.94, 0.76, 0.88, 0.72, 0.95, 0.78, 0.90, 0.73,
    ],
  );
}

Path _brushBarPath(Rect bounds, {required bool vertical}) {
  final box = bounds.deflate(bounds.shortestSide * 0.1);
  final wobble = vertical ? box.width * 0.16 : box.height * 0.16;
  final steps = 10;
  final path = Path();
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final wiggle = (i.isEven ? 1.0 : -0.65) * wobble * (0.45 + 0.55 * t);
    final point = vertical
        ? Offset(box.left + wiggle.abs() * 0.15, box.top + box.height * t)
        : Offset(box.left + box.width * t, box.top + wiggle.abs() * 0.15);
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  for (var i = steps; i >= 0; i--) {
    final t = i / steps;
    final wiggle = (i.isEven ? 1.0 : -0.65) * wobble * (0.45 + 0.55 * (1 - t));
    final point = vertical
        ? Offset(box.right - wiggle.abs() * 0.15, box.top + box.height * t)
        : Offset(box.left + box.width * t, box.bottom - wiggle.abs() * 0.15);
    path.lineTo(point.dx, point.dy);
  }
  path.close();
  return path;
}

Path _roundedStarPath(Rect bounds, {required int points, required double innerRatio}) {
  final unit = <Offset>[
    for (var index = 0; index < points * 2; index++)
      () {
        final radius = index.isEven ? 1.0 : innerRatio;
        final angle = -math.pi / 2 + index * math.pi / points;
        return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      }(),
  ];
  final fitted = _fittedPoints(unit, bounds.deflate(bounds.shortestSide * 0.04));
  if (fitted.length < 3) {
    return _fallbackRectPath(bounds);
  }
  return _roundedCornerPolygonPath(fitted, 0.3);
}

Path _ribbonPath(Rect bounds) {
  final notch = bounds.height * 0.14;
  return Path()
    ..moveTo(bounds.left, bounds.top)
    ..lineTo(bounds.center.dx, bounds.top + notch)
    ..lineTo(bounds.right, bounds.top)
    ..lineTo(bounds.right, bounds.bottom - notch)
    ..lineTo(bounds.center.dx, bounds.bottom)
    ..lineTo(bounds.left, bounds.bottom - notch)
    ..close();
}

Path _speechRoundPath(Rect bounds) {
  final box = _inscribedSquare(bounds);
  final radius = box.width * 0.36;
  final center = Offset(box.center.dx, box.top + radius + box.height * 0.06);
  Offset onCircle(double degrees) {
    final angle = degrees * math.pi / 180;
    return Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
  }

  final start = onCircle(140);
  final end = onCircle(40);
  return Path()
    ..moveTo(start.dx, start.dy)
    ..arcToPoint(
      end,
      radius: Radius.circular(radius),
      largeArc: true,
    )
    ..lineTo(center.dx - radius * 0.45, box.bottom)
    ..close();
}

Path _waveFillPath(
  Rect bounds, {
  required bool topWavy,
  required bool bottomWavy,
  required int variant,
}) {
  final amp = bounds.height * (variant == 0 ? 0.1 : 0.14);
  List<Offset> edge(bool fromTop) {
    final y0 = fromTop ? bounds.top + amp : bounds.bottom - amp;
    final sign = variant == 0 ? 1.0 : -1.0;
    final peaks = variant == 0
        ? const <double>[0.0, -1.0, 0.35, 1.0, 0.0]
        : const <double>[0.0, 0.7, -0.85, 0.55, -0.4, 0.9, 0.0];
    return <Offset>[
      for (var i = 0; i < peaks.length; i++)
        Offset(
          bounds.left + bounds.width * i / (peaks.length - 1),
          (y0 + amp * sign * peaks[i]).clamp(bounds.top, bounds.bottom),
        ),
    ];
  }

  void addWave(Path path, List<Offset> points, {required bool reverse}) {
    final pts = reverse ? points.reversed.toList() : points;
    path.lineTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final prev = pts[i - 1];
      final next = pts[i];
      final midX = (prev.dx + next.dx) / 2;
      path.cubicTo(midX, prev.dy, midX, next.dy, next.dx, next.dy);
    }
  }

  final path = Path()..moveTo(bounds.left, bounds.top);
  if (topWavy) {
    addWave(path, edge(true), reverse: false);
  } else {
    path.lineTo(bounds.right, bounds.top);
  }
  path.lineTo(bounds.right, bounds.bottom);
  if (bottomWavy) {
    addWave(path, edge(false), reverse: true);
  } else {
    path.lineTo(bounds.left, bounds.bottom);
  }
  path.close();
  return path;
}

enum _SlantKind { top, mid, bottom }

Path _slantFillPath(Rect bounds, {required _SlantKind kind}) {
  final d = bounds.height * 0.2;
  switch (kind) {
    case _SlantKind.top:
      return Path()
        ..moveTo(bounds.left, bounds.top)
        ..lineTo(bounds.right, bounds.top)
        ..lineTo(bounds.right, bounds.bottom - d)
        ..lineTo(bounds.left, bounds.bottom)
        ..close();
    case _SlantKind.mid:
      return Path()
        ..moveTo(bounds.left, bounds.top)
        ..lineTo(bounds.right, bounds.top + d)
        ..lineTo(bounds.right, bounds.bottom)
        ..lineTo(bounds.left, bounds.bottom - d)
        ..close();
    case _SlantKind.bottom:
      return Path()
        ..moveTo(bounds.left, bounds.top)
        ..lineTo(bounds.right, bounds.top + d)
        ..lineTo(bounds.right, bounds.bottom)
        ..lineTo(bounds.left, bounds.bottom)
        ..close();
  }
}

Path _roundOneCornerPath(
  Rect bounds, {
  bool tl = false,
  bool tr = false,
  bool bl = false,
  bool br = false,
}) {
  final radius = bounds.shortestSide * 0.5;
  return Path()
    ..addRRect(
      RRect.fromRectAndCorners(
        bounds,
        topLeft: tl ? Radius.circular(radius) : Radius.zero,
        topRight: tr ? Radius.circular(radius) : Radius.zero,
        bottomLeft: bl ? Radius.circular(radius) : Radius.zero,
        bottomRight: br ? Radius.circular(radius) : Radius.zero,
      ),
    );
}

/// Soft diagonal ribbon — a thick rounded stroke, not a lightning zigzag.
Path _brushStrokePath(Rect bounds) {
  final inset = bounds.shortestSide * 0.08;
  final box = bounds.deflate(inset);
  if (box.width <= 0 || box.height <= 0) {
    return Path();
  }
  final radius = box.shortestSide * 0.28;
  final start = Offset(box.left + radius, box.top + radius);
  final end = Offset(box.right - radius, box.bottom - radius);
  final delta = end - start;
  final length = delta.distance;
  if (length <= 0) {
    return Path()..addOval(Rect.fromCircle(center: box.center, radius: radius));
  }
  final px = -delta.dy / length * radius;
  final py = delta.dx / length * radius;
  return Path()
    ..moveTo(start.dx + px, start.dy + py)
    ..lineTo(end.dx + px, end.dy + py)
    ..arcToPoint(
      Offset(end.dx - px, end.dy - py),
      radius: Radius.circular(radius),
    )
    ..lineTo(start.dx - px, start.dy - py)
    ..arcToPoint(
      Offset(start.dx + px, start.dy + py),
      radius: Radius.circular(radius),
    )
    ..close();
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
