import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/layout/data/layout_catalog.dart';
import 'package:whatswave/features/updates/layout/models/layout_models.dart';
import 'package:whatswave/features/updates/layout/presentation/widgets/layout_shape_clipper.dart';

/// Bounds of the drawn outline. [Path.getBounds] pads around arcs because it
/// measures conic control points, which is too loose to catch a silhouette
/// spilling out of its slot.
Rect _outlineBounds(Path path) {
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;

  for (final metric in path.computeMetrics()) {
    const steps = 600;
    for (var step = 0; step <= steps; step++) {
      final tangent = metric.getTangentForOffset(metric.length * step / steps);
      if (tangent == null) {
        continue;
      }
      final point = tangent.position;
      left = math.min(left, point.dx);
      top = math.min(top, point.dy);
      right = math.max(right, point.dx);
      bottom = math.max(bottom, point.dy);
    }
  }

  return Rect.fromLTRB(left, top, right, bottom);
}

void main() {
  const bounds = Rect.fromLTWH(0, 0, 100, 160);

  test('safeLayoutShapePath never returns an empty bounds for any shape', () {
    for (final shape in LayoutShapeId.values) {
      final path = safeLayoutShapePath(shape: shape, bounds: bounds);
      final pathBounds = path.getBounds();
      expect(pathBounds.width, greaterThan(0), reason: '$shape');
      expect(pathBounds.height, greaterThan(0), reason: '$shape');
    }
  });

  test('every shape produces a non-empty path that stays inside the slot', () {
    const slots = <Rect>[
      Rect.fromLTWH(0, 0, 100, 160),
      Rect.fromLTWH(0, 0, 320, 180),
      Rect.fromLTWH(0, 0, 200, 200),
      Rect.fromLTWH(0, 0, 60, 400),
    ];

    for (final slot in slots) {
      for (final shape in LayoutShapeId.values) {
        final path = layoutShapePath(shape: shape, bounds: slot);
        final pathBounds = _outlineBounds(path);
        final reason = '$shape in $slot';
        expect(
          pathBounds.width,
          greaterThan(0),
          reason: '$reason should paint a visible silhouette',
        );
        expect(pathBounds.height, greaterThan(0), reason: reason);
        expect(pathBounds.left, greaterThanOrEqualTo(slot.left - 0.5), reason: reason);
        expect(pathBounds.top, greaterThanOrEqualTo(slot.top - 0.5), reason: reason);
        expect(pathBounds.right, lessThanOrEqualTo(slot.right + 0.5), reason: reason);
        expect(
          pathBounds.bottom,
          lessThanOrEqualTo(slot.bottom + 0.5),
          reason: reason,
        );
      }
    }
  });

  test('teardrop keeps its tip on top and its bulb on the bottom edge', () {
    const slot = Rect.fromLTWH(0, 0, 308, 430);
    final pathBounds = _outlineBounds(
      layoutShapePath(shape: LayoutShapeId.teardrop, bounds: slot),
    );
    expect(pathBounds.top, closeTo(slot.top, 0.5));
    expect(pathBounds.bottom, closeTo(slot.bottom, 0.5));
    expect(pathBounds.width, lessThanOrEqualTo(slot.width + 0.5));
  });

  test('circle path is a true circle on tall slot bounds', () {
    const bounds = Rect.fromLTWH(0, 0, 100, 160);
    final path = layoutShapePath(shape: LayoutShapeId.circle, bounds: bounds);
    final pathBounds = path.getBounds();
    expect(pathBounds.width, closeTo(100, 0.01));
    expect(pathBounds.height, closeTo(100, 0.01));
    expect(pathBounds.center, bounds.center);
  });

  test('oval path follows the slot aspect ratio', () {
    const bounds = Rect.fromLTWH(0, 0, 100, 160);
    final path = layoutShapePath(shape: LayoutShapeId.oval, bounds: bounds);
    final pathBounds = path.getBounds();
    expect(pathBounds.height, greaterThan(pathBounds.width));
  });

  test('oval stays a vertical egg in wide row slots', () {
    // two_rows slot on a 9:16 canvas is wider than it is tall.
    const bounds = Rect.fromLTWH(0, 0, 180, 160);
    final path = layoutShapePath(shape: LayoutShapeId.oval, bounds: bounds);
    final pathBounds = path.getBounds();
    expect(pathBounds.height, greaterThan(pathBounds.width * 1.05));
  });

  test('circle and oval are visibly different in row slots', () {
    const bounds = Rect.fromLTWH(0, 0, 180, 160);
    final circle = layoutShapePath(
      shape: LayoutShapeId.circle,
      bounds: bounds,
    ).getBounds();
    final oval = layoutShapePath(
      shape: LayoutShapeId.oval,
      bounds: bounds,
    ).getBounds();
    expect(circle.width, closeTo(circle.height, 1));
    expect(oval.height, greaterThan(oval.width * 1.1));
    expect(oval.height, greaterThan(circle.height * 0.85));
  });

  test('rectangle honors a normalized corner radius', () {
    final sharp = layoutShapePath(
      shape: LayoutShapeId.rectangle,
      bounds: bounds,
    );
    final rounded = layoutShapePath(
      shape: LayoutShapeId.rectangle,
      bounds: bounds,
      cornerRadius: 0.2,
    );
    expect(sharp.getBounds().width, 100);
    expect(rounded.getBounds().width, 100);
  });

  test('LayoutShapeClipper reclips when the shape or radius changes', () {
    const clipper = LayoutShapeClipper(shape: LayoutShapeId.circle);
    expect(clipper.getClip(const Size(40, 40)), isA<Path>());
    expect(
      clipper.shouldReclip(const LayoutShapeClipper(shape: LayoutShapeId.heart)),
      isTrue,
    );
    expect(
      clipper.shouldReclip(const LayoutShapeClipper(shape: LayoutShapeId.circle)),
      isFalse,
    );
    expect(
      const LayoutShapeClipper(
        shape: LayoutShapeId.rectangle,
        cornerRadius: 0.1,
      ).shouldReclip(
        const LayoutShapeClipper(
          shape: LayoutShapeId.rectangle,
        ),
      ),
      isTrue,
    );
  });

  test('preview painters redraw only when their data changes', () {
    const shapePainter = LayoutShapePreviewPainter(shape: LayoutShapeId.star);
    expect(
      shapePainter.shouldRepaint(
        const LayoutShapePreviewPainter(shape: LayoutShapeId.star),
      ),
      isFalse,
    );
    expect(
      shapePainter.shouldRepaint(
        const LayoutShapePreviewPainter(shape: LayoutShapeId.heart),
      ),
      isTrue,
    );

    final template = LayoutCatalog.templateById('two_columns');
    final templatePainter = LayoutTemplatePreviewPainter(template: template);
    expect(
      templatePainter.shouldRepaint(
        LayoutTemplatePreviewPainter(template: template),
      ),
      isFalse,
    );
    expect(
      templatePainter.shouldRepaint(
        LayoutTemplatePreviewPainter(
          template: LayoutCatalog.templateById('single'),
        ),
      ),
      isTrue,
    );
  });
}
