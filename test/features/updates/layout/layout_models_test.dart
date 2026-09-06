import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/layout/models/layout_models.dart';

void main() {
  group('LayoutSlotContent', () {
    test('hasImage is false for null, empty, and whitespace paths', () {
      expect(const LayoutSlotContent().hasImage, isFalse);
      expect(const LayoutSlotContent(imagePath: '').hasImage, isFalse);
      expect(const LayoutSlotContent(imagePath: '   ').hasImage, isFalse);
      expect(
        const LayoutSlotContent(imagePath: '/tmp/photo.jpg').hasImage,
        isTrue,
      );
    });

    test('copyWith updates fields and can clear image and border', () {
      const original = LayoutSlotContent(
        imagePath: '/tmp/a.jpg',
        scale: 1.4,
        focalDx: 0.2,
        focalDy: 0.8,
        shape: LayoutShapeId.circle,
        borderColorValue: 0xFF2AABEE,
        borderWidth: 4,
      );

      final updated = original.copyWith(
        imagePath: '/tmp/b.jpg',
        scale: 2,
        shape: LayoutShapeId.heart,
      );
      expect(updated.imagePath, '/tmp/b.jpg');
      expect(updated.scale, 2);
      expect(updated.shape, LayoutShapeId.heart);
      expect(updated.focalDx, 0.2);

      final cleared = original.copyWith(
        clearImagePath: true,
        clearBorderColor: true,
        borderWidth: 0,
      );
      expect(cleared.hasImage, isFalse);
      expect(cleared.borderColor, isNull);
      expect(cleared.borderWidth, 0);
    });

    test('look copyWith keeps a chosen photo frame style', () {
      const original = LayoutSlotContent(look: LayoutSlotLook.border);
      expect(original.look.strokeWidth, 3);
      expect(original.look.usesColor, isTrue);

      final soft = original.copyWith(look: LayoutSlotLook.soft);
      expect(soft.look, LayoutSlotLook.soft);
      expect(soft.look.paintsShadow, isTrue);
      expect(LayoutSlotLook.shadow.defaultColorValue, 0xFF000000);
    });

    test('borderColor reconstructs from the stored ARGB value', () {
      const slot = LayoutSlotContent(borderColorValue: 0xFFFF0000);
      expect(slot.borderColor, const Color(0xFFFF0000));
    });
  });

  group('LayoutComposerState', () {
    test('canShare is true only when at least one slot has an image', () {
      const empty = LayoutComposerState(
        templateId: 'single',
        backgroundColorValue: 0xFFFFFFFF,
        slots: <LayoutSlotContent>[LayoutSlotContent()],
      );
      expect(empty.canShare, isFalse);

      const ready = LayoutComposerState(
        templateId: 'single',
        backgroundColorValue: 0xFFFFFFFF,
        slots: <LayoutSlotContent>[
          LayoutSlotContent(),
          LayoutSlotContent(imagePath: '/tmp/a.jpg'),
        ],
      );
      expect(ready.canShare, isTrue);
    });

    test('copyWith can replace slots and clear the selected index', () {
      const state = LayoutComposerState(
        templateId: 'single',
        backgroundColorValue: 0xFFFFFFFF,
        slots: <LayoutSlotContent>[LayoutSlotContent()],
        selectedSlotIndex: 0,
      );

      final cleared = state.copyWith(clearSelectedSlot: true);
      expect(cleared.selectedSlotIndex, isNull);
      expect(cleared.templateId, 'single');

      final painted = state.copyWith(backgroundColorValue: 0xFF111111);
      expect(painted.backgroundColor, const Color(0xFF111111));
    });
  });

  group('LayoutSlotDefinition and LayoutTemplate', () {
    test('copyWith keeps unspecified fields', () {
      const slot = LayoutSlotDefinition(
        rect: Rect.fromLTWH(0, 0, 1, 1),
        defaultShape: LayoutShapeId.arch,
        cornerRadius: 0.1,
      );
      final copied = slot.copyWith(defaultShape: LayoutShapeId.circle);
      expect(copied.rect, slot.rect);
      expect(copied.defaultShape, LayoutShapeId.circle);
      expect(copied.cornerRadius, 0.1);
    });

    test('slotCount matches the slots list', () {
      const template = LayoutTemplate(
        id: 'demo',
        label: 'Demo',
        slots: <LayoutSlotDefinition>[
          LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 0.5, 1)),
          LayoutSlotDefinition(rect: Rect.fromLTWH(0.5, 0, 0.5, 1)),
        ],
      );
      expect(template.slotCount, 2);
    });
  });

  test('story canvas constants stay 9:16 at 1080x1920', () {
    expect(kLayoutStoryAspectRatio, 9 / 16);
    expect(kLayoutExportWidth / kLayoutExportHeight, 9 / 16);
    expect(kLayoutPreviewMaxPixelSize, 1440);
  });

  test('full screen canvas uses the device safe area, other sizes stay fixed',
      () {
    const screen = Size(390, 844);
    final safe = layoutComposerSafeAreaSize(
      screenSize: screen,
      topInset: 47,
      bottomInset: 34,
    );
    expect(safe, const Size(390, 763));
    expect(
      LayoutCanvasRatio.fullScreen.resolve(safe),
      closeTo(390 / 763, 0.0001),
    );
    expect(LayoutCanvasRatio.story.value, 9 / 16);
    expect(LayoutCanvasRatio.portrait.value, 4 / 5);
    expect(LayoutCanvasRatio.square.value, 1);
    expect(LayoutCanvasRatio.landscape.value, 16 / 9);

    final landscape = layoutComposerSafeAreaSize(
      screenSize: const Size(844, 390),
      topInset: 0,
      bottomInset: 21,
      leftInset: 47,
      rightInset: 47,
    );
    expect(landscape, const Size(750, 369));
  });

  test('resolveLayoutSlots reweights a two-row grid and insets the frame', () {
    const grid = LayoutGridSpec(axis: LayoutSplitAxis.rows, bands: <int>[1, 1]);
    const template = LayoutTemplate(
      id: 'two',
      label: 'Two',
      grid: grid,
      slots: <LayoutSlotDefinition>[],
    );

    final equal = resolveLayoutSlots(template: template);
    expect(equal, hasLength(2));
    expect(equal.first.rect.height, closeTo(equal.last.rect.height, 0.02));

    final tallTop = resolveLayoutSlots(
      template: template,
      weights: const <double>[0.7, 0.3],
    );
    expect(tallTop.first.rect.height, greaterThan(equal.first.rect.height));

    final framed = resolveLayoutSlots(template: template, frame: 1);
    expect(framed.first.rect.top, greaterThan(equal.first.rect.top));
    expect(framed.first.rect.left, greaterThan(equal.first.rect.left));

    final flush = resolveLayoutSlots(template: template, frame: 0);
    expect(flush.first.rect.bottom, flush.last.rect.top);
    expect(layoutFrameGutter(0), 0);
    expect(kLayoutDefaultFrame, 0.05);
  });

  test('frame slider uses the same pixel gap on every edge and between photos',
      () {
    const grid = LayoutGridSpec(
      axis: LayoutSplitAxis.columns,
      bands: <int>[3, 1],
    );
    const template = LayoutTemplate(
      id: 'three_beside_one',
      label: '3 | 1',
      grid: grid,
      slots: <LayoutSlotDefinition>[],
    );
    const canvasW = 1080.0;
    const canvasH = 1920.0;

    final slots = resolveLayoutSlots(
      template: template,
      frame: 1,
      aspect: canvasW / canvasH,
    );
    expect(slots, hasLength(4));

    final leftPx = slots.first.rect.left * canvasW;
    final rightPx = (1 - slots.last.rect.right) * canvasW;
    final topPx = slots.first.rect.top * canvasH;
    final bottomPx = (1 - slots[2].rect.bottom) * canvasH;
    final vGutter = (slots[1].rect.top - slots[0].rect.bottom) * canvasH;
    final hGutter = (slots.last.rect.left - slots.first.rect.right) * canvasW;

    expect(leftPx, closeTo(kLayoutFrameGap * canvasW, 0.5));
    expect(rightPx, closeTo(leftPx, 0.5));
    expect(topPx, closeTo(leftPx, 0.5));
    expect(bottomPx, closeTo(leftPx, 0.5));
    expect(vGutter, closeTo(leftPx, 0.5));
    expect(hGutter, closeTo(leftPx, 0.5));
  });

  test('layoutDragSplitWeights moves a pair and clamps the minimum share', () {
    final dragged = layoutDragSplitWeights(
      weights: const <double>[0.5, 0.5],
      boundaryIndex: 0,
      deltaFraction: 0.2,
    );
    expect(dragged.first, closeTo(0.7, 0.001));
    expect(dragged.last, closeTo(0.3, 0.001));

    final clamped = layoutDragSplitWeights(
      weights: const <double>[0.5, 0.5],
      boundaryIndex: 0,
      deltaFraction: -1,
    );
    expect(clamped.first, kLayoutMinBandFraction);
    expect(clamped.last, closeTo(1 - kLayoutMinBandFraction, 0.001));
  });

  test('cell weights resize photos inside a 2-over-1 band', () {
    const grid = LayoutGridSpec(axis: LayoutSplitAxis.rows, bands: <int>[2, 1]);
    const template = LayoutTemplate(
      id: 'two_over_one',
      label: '2 / 1',
      grid: grid,
      slots: <LayoutSlotDefinition>[],
    );

    final equal = resolveLayoutSlots(template: template);
    expect(equal[0].rect.width, closeTo(equal[1].rect.width, 0.02));

    final wideLeft = resolveLayoutSlots(
      template: template,
      cellWeights: const <List<double>>[
        <double>[0.7, 0.3],
        <double>[1],
      ],
    );
    expect(wideLeft[0].rect.width, greaterThan(equal[0].rect.width));

    final handles = layoutSplitHandles(grid: grid);
    expect(handles.any((handle) => handle.axis == LayoutSplitAxis.rows), isTrue);
    expect(
      handles.any((handle) => handle.axis == LayoutSplitAxis.columns),
      isTrue,
    );
  });
}
