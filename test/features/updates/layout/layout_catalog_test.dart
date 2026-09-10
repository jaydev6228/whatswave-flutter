import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/layout/data/layout_catalog.dart';
import 'package:whatswave/features/updates/layout/models/layout_models.dart';

void main() {
  test('catalog ids are unique and every template has at least one slot', () {
    final ids = LayoutCatalog.templates.map((template) => template.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(LayoutCatalog.templates.length, greaterThanOrEqualTo(24));
    for (final template in LayoutCatalog.templates) {
      expect(template.slots, isNotEmpty, reason: template.id);
      expect(template.label, isNotEmpty, reason: template.id);
    }
  });

  test('every template slot stays inside the normalized 9:16 canvas', () {
    for (final template in LayoutCatalog.templates) {
      for (final slot in template.slots) {
        expect(slot.rect.left, greaterThanOrEqualTo(0), reason: template.id);
        expect(slot.rect.top, greaterThanOrEqualTo(0), reason: template.id);
        expect(slot.rect.right, lessThanOrEqualTo(1.0001), reason: template.id);
        expect(slot.rect.bottom, lessThanOrEqualTo(1.0001), reason: template.id);
        expect(slot.rect.width, greaterThan(0), reason: template.id);
        expect(slot.rect.height, greaterThan(0), reason: template.id);
      }
    }
  });

  test('templateById returns the named template or the first as fallback', () {
    expect(LayoutCatalog.templateById('two_columns').id, 'two_columns');
    expect(LayoutCatalog.templateById('missing').id, LayoutCatalog.templates.first.id);
  });

  test('initialState builds one empty slot per template slot with default shapes', () {
    final state = LayoutCatalog.initialState(templateId: 'one_beside_four');
    final template = LayoutCatalog.templateById('one_beside_four');

    expect(state.templateId, 'one_beside_four');
    expect(state.slots.length, template.slotCount);
    expect(state.canShare, isFalse);
    expect(state.selectedSlotIndex, isNull);
    for (var index = 0; index < template.slotCount; index++) {
      expect(state.slots[index].shape, template.slots[index].defaultShape);
      expect(state.slots[index].hasImage, isFalse);
    }
  });

  test('migrateState packs filled photos in order and drops extras', () {
    final filled = LayoutCatalog.initialState(templateId: 'one_beside_four').copyWith(
      slots: const <LayoutSlotContent>[
        LayoutSlotContent(imagePath: '/tmp/0.jpg', shape: LayoutShapeId.circle),
        LayoutSlotContent(imagePath: '/tmp/1.jpg'),
        LayoutSlotContent(imagePath: '/tmp/2.jpg'),
        LayoutSlotContent(imagePath: '/tmp/3.jpg'),
        LayoutSlotContent(imagePath: '/tmp/4.jpg'),
      ],
      selectedSlotIndex: 2,
    );

    final toSingle = LayoutCatalog.migrateState(
      filled,
      LayoutCatalog.templateById('single'),
    );
    expect(toSingle.slots.length, 1);
    expect(toSingle.slots.first.imagePath, '/tmp/0.jpg');
    expect(toSingle.slots.first.shape, LayoutShapeId.rectangle);
    expect(toSingle.selectedSlotIndex, isNull);

    final toTwo = LayoutCatalog.migrateState(
      LayoutCatalog.initialState(templateId: 'single').copyWith(
        slots: const <LayoutSlotContent>[
          LayoutSlotContent(imagePath: '/tmp/a.jpg'),
        ],
      ),
      LayoutCatalog.templateById('two_columns'),
    );
    expect(toTwo.slots.length, 2);
    expect(toTwo.slots.first.imagePath, '/tmp/a.jpg');
    expect(toTwo.slots.last.hasImage, isFalse);
    expect(toTwo.splitWeights, isNull);
  });

  test('migrateState keeps the frame slider and clears split weights', () {
    final current = LayoutCatalog.initialState(templateId: 'two_rows').copyWith(
      frame: 0.7,
      splitWeights: const <double>[0.7, 0.3],
    );
    final migrated = LayoutCatalog.migrateState(
      current,
      LayoutCatalog.templateById('two_columns'),
    );
    expect(migrated.frame, 0.7);
    expect(migrated.splitWeights, isNull);
    expect(migrated.cellWeights, isNull);
  });

  test('migrateState ignores empty slots when packing photos', () {
    final current = LayoutCatalog.initialState(
      templateId: 'one_over_three',
    ).copyWith(
      slots: const <LayoutSlotContent>[
        LayoutSlotContent(),
        LayoutSlotContent(imagePath: '/tmp/a.jpg', shape: LayoutShapeId.oval),
        LayoutSlotContent(imagePath: '/tmp/b.jpg', shape: LayoutShapeId.circle),
        LayoutSlotContent(imagePath: '/tmp/c.jpg', shape: LayoutShapeId.heart),
      ],
    );

    final migrated = LayoutCatalog.migrateState(
      current,
      LayoutCatalog.templateById('three_columns'),
    );

    expect(migrated.slots.length, 3);
    expect(migrated.slots[0].imagePath, '/tmp/a.jpg');
    expect(migrated.slots[1].imagePath, '/tmp/b.jpg');
    expect(migrated.slots[2].imagePath, '/tmp/c.jpg');
    expect(migrated.slots.every((slot) => slot.shape == LayoutShapeId.rectangle),
        isTrue);
  });

  test('migrateState resets zoom and focal when re-slotting photos', () {
    final current = LayoutCatalog.initialState(templateId: 'three_rows').copyWith(
      slots: const <LayoutSlotContent>[
        LayoutSlotContent(
          imagePath: '/tmp/a.jpg',
          scale: 2.4,
          focalDx: 0.1,
          focalDy: 0.9,
          shape: LayoutShapeId.oval,
        ),
      ],
    );

    final migrated = LayoutCatalog.migrateState(
      current,
      LayoutCatalog.templateById('one_beside_three'),
    );

    expect(migrated.slots.first.imagePath, '/tmp/a.jpg');
    expect(migrated.slots.first.scale, 1);
    expect(migrated.slots.first.focalDx, 0.5);
    expect(migrated.slots.first.focalDy, 0.5);
    expect(migrated.slots.first.shape, LayoutShapeId.rectangle);
  });

  test('migrateState applies the new default shape only to empty slots', () {
    final current = LayoutCatalog.initialState(templateId: 'single').copyWith(
      slots: const <LayoutSlotContent>[
        LayoutSlotContent(shape: LayoutShapeId.rectangle),
      ],
    );

    final migrated = LayoutCatalog.migrateState(
      current,
      LayoutCatalog.templateById('two_columns'),
    );

    expect(migrated.slots.first.shape, LayoutShapeId.rectangle);
    expect(migrated.slots.first.hasImage, isFalse);
  });

  test('shape picker lists each shown silhouette once', () {
    expect(kLayoutShapePickerOrder.toSet().length, kLayoutShapePickerOrder.length);
    expect(kLayoutShapePickerOrder, contains(LayoutShapeId.circle));
    expect(kLayoutShapePickerOrder, contains(LayoutShapeId.heart));
    expect(kLayoutShapePickerOrder, contains(LayoutShapeId.brushDiagonal));
    expect(kLayoutShapePickerOrder, contains(LayoutShapeId.brushWide));
    expect(kLayoutShapePickerOrder, contains(LayoutShapeId.cloud));
    expect(kLayoutShapePickerOrder, isNot(contains(LayoutShapeId.waveTop)));
    expect(kLayoutShapePickerOrder, isNot(contains(LayoutShapeId.brokenHeart)));
    expect(
      kLayoutShapeRail.map((entry) => entry.keyName).toSet().length,
      kLayoutShapeRail.length,
    );
    expect(
      kLayoutShapeRail.any((entry) => entry.templateId == 'shape_broken_heart'),
      isTrue,
    );
  });

  test('shape collages are two-plus photo slots and stay out of Layouts', () {
    expect(shapeCollages, isNotEmpty);
    for (final collage in shapeCollages) {
      expect(collage.slotCount, greaterThanOrEqualTo(2), reason: collage.id);
      expect(LayoutCatalog.templates.map((t) => t.id), isNot(contains(collage.id)));
      expect(LayoutCatalog.isShapeCollage(collage.id), isTrue);
      expect(LayoutCatalog.templateById(collage.id).id, collage.id);
      for (final slot in collage.slots) {
        expect(slot.rect.left, greaterThanOrEqualTo(-0.001), reason: collage.id);
        expect(slot.rect.top, greaterThanOrEqualTo(-0.001), reason: collage.id);
        expect(slot.rect.right, lessThanOrEqualTo(1.001), reason: collage.id);
        expect(slot.rect.bottom, lessThanOrEqualTo(1.001), reason: collage.id);
      }
    }
    expect(LayoutCatalog.templateById('shape_broken_heart').slotCount, 2);
    expect(LayoutCatalog.templateById('shape_three_brushes').slotCount, 3);
    final brushes = LayoutCatalog.templateById('shape_three_brushes').slots;
    expect(brushes[1].rect.top, greaterThanOrEqualTo(brushes[0].rect.bottom));
    expect(brushes[2].rect.top, greaterThanOrEqualTo(brushes[1].rect.bottom));
  });

  test('layouts are photo grids only — rectangles, 1–6 or 8–9 slots', () {
    const allowedCounts = <int>{1, 2, 3, 4, 5, 6, 8, 9};
    for (final template in LayoutCatalog.templates) {
      expect(allowedCounts, contains(template.slotCount), reason: template.id);
      for (final slot in template.slots) {
        expect(
          slot.defaultShape,
          LayoutShapeId.rectangle,
          reason: template.id,
        );
      }
    }
    expect(LayoutCatalog.templateById('one_beside_three').slotCount, 4);
    expect(LayoutCatalog.templateById('grid_3x3').slotCount, 9);
    expect(
      LayoutCatalog.templates.map((template) => template.id),
      isNot(contains('two_rows_tall_top')),
    );
    expect(
      LayoutCatalog.templates.map((template) => template.id),
      isNot(contains('two_columns_wide_left')),
    );
    expect(
      LayoutCatalog.templates.map((template) => template.id),
      isNot(contains('mosaic_three')),
    );
    expect(
      LayoutCatalog.templates.map((template) => template.id),
      isNot(contains('stagger_left_up')),
    );
    expect(
      LayoutCatalog.templates.map((template) => template.id),
      isNot(contains('three_brush_diagonal')),
    );
  });

  test('grid templates expose a split so ratio handles can rebuild slots', () {
    final twoRows = LayoutCatalog.templateById('two_rows');
    expect(twoRows.grid?.axis, LayoutSplitAxis.rows);
    expect(twoRows.grid?.bands, <int>[1, 1]);
    final twoCols = LayoutCatalog.templateById('two_columns');
    expect(twoCols.grid?.axis, LayoutSplitAxis.columns);
    expect(LayoutCatalog.templateById('single').grid, isNull);
  });

  test('layout list is ordered by photo count: 1, then 2, then 3…', () {
    final counts = LayoutCatalog.templates
        .map((template) => template.slotCount)
        .toList();
    expect(counts.first, 1);
    expect(counts, List<int>.from(counts)..sort());
    expect(LayoutCatalog.templates.first.id, 'single');
  });
}
