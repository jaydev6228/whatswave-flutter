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
    final state = LayoutCatalog.initialState(templateId: 'arch_three_bottom');
    final template = LayoutCatalog.templateById('arch_three_bottom');

    expect(state.templateId, 'arch_three_bottom');
    expect(state.slots.length, template.slotCount);
    expect(state.canShare, isFalse);
    expect(state.selectedSlotIndex, isNull);
    for (var index = 0; index < template.slotCount; index++) {
      expect(state.slots[index].shape, template.slots[index].defaultShape);
      expect(state.slots[index].hasImage, isFalse);
    }
  });

  test('migrateState packs filled photos in order and drops extras', () {
    final filled = LayoutCatalog.initialState(templateId: 'film_strip').copyWith(
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
  });

  test('migrateState ignores empty slots when packing photos', () {
    final current = LayoutCatalog.initialState(
      templateId: 'bottom_strip_three',
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
      LayoutCatalog.templateById('film_strip_three'),
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
      LayoutCatalog.templateById('arch_three_bottom'),
    );

    expect(migrated.slots.first.shape, LayoutShapeId.arch);
    expect(migrated.slots.first.hasImage, isFalse);
  });

  test('shape picker lists every supported silhouette once', () {
    expect(kLayoutShapePickerOrder.toSet().length, kLayoutShapePickerOrder.length);
    expect(kLayoutShapePickerOrder.length, greaterThanOrEqualTo(16));
    expect(kLayoutShapePickerOrder, contains(LayoutShapeId.circle));
    expect(kLayoutShapePickerOrder, contains(LayoutShapeId.shield));
    expect(kLayoutShapePickerOrder, contains(LayoutShapeId.ticket));
  });
}
