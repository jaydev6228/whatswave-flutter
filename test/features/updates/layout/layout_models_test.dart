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
    expect(kLayoutPreviewMaxPixelSize, lessThan(kLayoutExportWidth));
  });
}
