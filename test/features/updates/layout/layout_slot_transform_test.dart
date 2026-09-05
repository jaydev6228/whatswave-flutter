import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/layout/application/layout_slot_transform.dart';
import 'package:whatswave/features/updates/layout/models/layout_models.dart';
import 'package:whatswave/features/updates/layout/presentation/widgets/layout_shape_clipper.dart';

void main() {
  test('portrait photo in a wide slot allows horizontal pan at default zoom',
      () {
    const slot = Size(200, 400);
    const image = Size(800, 1000);
    final extents = layoutSlotPanExtents(
      slotSize: slot,
      imageSize: image,
      userZoom: 1,
    );
    expect(extents.dx, greaterThan(0));
    expect(extents.dy, lessThan(0.5));
  });

  test('focal 0 and 1 reach opposite pan extremes', () {
    const slot = Size(200, 400);
    const image = Size(800, 1000);
    final left = layoutSlotPanOffset(
      slotSize: slot,
      imageSize: image,
      userZoom: 1,
      focalDx: 0,
      focalDy: 0.5,
    );
    final right = layoutSlotPanOffset(
      slotSize: slot,
      imageSize: image,
      userZoom: 1,
      focalDx: 1,
      focalDy: 0.5,
    );
    expect(left.dx, greaterThan(right.dx));
  });

  test('circle in a tall slot allows vertical pan at default zoom', () {
    const slot = Size(180, 640);
    const image = Size(800, 1000);
    final circleBounds = layoutShapeContentBounds(
      shape: LayoutShapeId.circle,
      slotSize: slot,
    );
    expect(circleBounds.height, lessThan(slot.height));

    final slotExtents = layoutSlotPanExtents(
      slotSize: slot,
      imageSize: image,
      userZoom: 1,
    );
    final circleExtents = layoutSlotPanExtents(
      slotSize: circleBounds.size,
      imageSize: image,
      userZoom: 1,
    );
    expect(slotExtents.dy, lessThan(0.5));
    expect(circleExtents.dy, greaterThan(0));
  });

  test('zoom increases pan range on both axes when image overflows', () {
    const slot = Size(300, 300);
    const image = Size(600, 600);
    final atOne = layoutSlotPanExtents(
      slotSize: slot,
      imageSize: image,
      userZoom: 1,
    );
    final atTwo = layoutSlotPanExtents(
      slotSize: slot,
      imageSize: image,
      userZoom: 2,
    );
    expect(atTwo.dx, greaterThan(atOne.dx));
    expect(atTwo.dy, greaterThan(atOne.dy));
  });
}
