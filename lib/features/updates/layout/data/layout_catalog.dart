import 'dart:ui';

import '../models/layout_models.dart';

/// Predefined collage templates inspired by common story layout apps.
/// All coordinates are normalized to the 9:16 canvas.
class LayoutCatalog {
  LayoutCatalog._();

  static LayoutTemplate _rowGrid(String id, String label, List<int> columns) {
    final grid = LayoutGridSpec(axis: LayoutSplitAxis.rows, bands: columns);
    return LayoutTemplate(
      id: id,
      label: label,
      grid: grid,
      slots: layoutSlotsForGrid(
        grid: grid,
        weights: layoutNormalizedWeights(null, grid.bandCount),
      ),
    );
  }

  static LayoutTemplate _columnGrid(String id, String label, List<int> rows) {
    final grid = LayoutGridSpec(axis: LayoutSplitAxis.columns, bands: rows);
    return LayoutTemplate(
      id: id,
      label: label,
      grid: grid,
      slots: layoutSlotsForGrid(
        grid: grid,
        weights: layoutNormalizedWeights(null, grid.bandCount),
      ),
    );
  }

  static List<LayoutSlotDefinition> slotsFor(
    LayoutComposerState state, {
    double? aspect,
  }) {
    return resolveLayoutSlots(
      template: templateById(state.templateId),
      weights: state.splitWeights,
      cellWeights: state.cellWeights,
      frame: state.frame,
      aspect: aspect ??
          state.ratio.resolve(const Size(9, 16)),
    );
  }

  static final List<LayoutTemplate> templates = <LayoutTemplate>[
    const LayoutTemplate(
      id: 'single',
      label: 'Single',
      gutter: 0,
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 1, 1)),
      ],
    ),

    // ---- two photos ----
    _rowGrid('two_rows', '2 rows', <int>[1, 1]),
    _columnGrid('two_columns', '2 columns', <int>[1, 1]),

    // ---- three photos ----
    _rowGrid('three_rows', '3 rows', <int>[1, 1, 1]),
    _columnGrid('three_columns', '3 columns', <int>[1, 1, 1]),
    _rowGrid('one_over_two', '1 / 2', <int>[1, 2]),
    _rowGrid('two_over_one', '2 / 1', <int>[2, 1]),
    _columnGrid('one_beside_two', '1 | 2', <int>[1, 2]),
    _columnGrid('two_beside_one', '2 | 1', <int>[2, 1]),

    // ---- four photos ----
    _rowGrid('grid_2x2', '2×2', <int>[2, 2]),
    _rowGrid('four_rows', '4 rows', <int>[1, 1, 1, 1]),
    _columnGrid('four_columns', '4 columns', <int>[1, 1, 1, 1]),
    _rowGrid('one_over_three', '1 / 3', <int>[1, 3]),
    _rowGrid('three_over_one', '3 / 1', <int>[3, 1]),
    _columnGrid('one_beside_three', '1 | 3', <int>[1, 3]),
    _columnGrid('three_beside_one', '3 | 1', <int>[3, 1]),
    _columnGrid('one_beside_four', '1 | 4', <int>[1, 4]),
    _columnGrid('four_beside_one', '4 | 1', <int>[4, 1]),
    _rowGrid('one_two_one', '1 / 2 / 1', <int>[1, 2, 1]),
    _rowGrid('two_one_one', '2 / 1 / 1', <int>[2, 1, 1]),
    _rowGrid('one_one_two', '1 / 1 / 2', <int>[1, 1, 2]),
    _columnGrid('one_two_one_columns', '1 | 2 | 1', <int>[1, 2, 1]),

    // ---- five photos ----
    _rowGrid('two_over_three', '2 / 3', <int>[2, 3]),
    _rowGrid('three_over_two', '3 / 2', <int>[3, 2]),
    _rowGrid('one_two_two', '1 / 2 / 2', <int>[1, 2, 2]),
    _rowGrid('two_two_one', '2 / 2 / 1', <int>[2, 2, 1]),
    _rowGrid('two_one_two', '2 / 1 / 2', <int>[2, 1, 2]),
    _rowGrid('five_rows', '5 rows', <int>[1, 1, 1, 1, 1]),
    _columnGrid('two_beside_three', '2 | 3', <int>[2, 3]),
    _columnGrid('three_beside_two', '3 | 2', <int>[3, 2]),

    // ---- six or more ----
    _rowGrid('grid_2x3', '2×3', <int>[2, 2, 2]),
    _rowGrid('grid_3x2', '3×2', <int>[3, 3]),
    _rowGrid('one_three_two', '1 / 3 / 2', <int>[1, 3, 2]),
    _rowGrid('two_three_one', '2 / 3 / 1', <int>[2, 3, 1]),
    _rowGrid('one_three_one', '1 / 3 / 1', <int>[1, 3, 1]),
    _rowGrid('grid_3x3', '3×3', <int>[3, 3, 3]),
    _rowGrid('grid_2x4', '2×4', <int>[2, 2, 2, 2]),
    _columnGrid('grid_3x2_columns', '3 | 3', <int>[3, 3]),
  ]..sort((a, b) => a.slotCount.compareTo(b.slotCount));



  static LayoutTemplate templateById(String id) {
    return templates.firstWhere(
      (template) => template.id == id,
      orElse: () => templates.first,
    );
  }

  static LayoutComposerState initialState({String templateId = 'single'}) {
    final template = templateById(templateId);
    return LayoutComposerState(
      templateId: template.id,
      backgroundColorValue: 0xFFFFFFFF,
      slots: List<LayoutSlotContent>.generate(
        template.slotCount,
        (index) => LayoutSlotContent(
          shape: template.slots[index].defaultShape,
        ),
      ),
    );
  }

  /// When switching templates, pack existing photos into the new slots in
  /// fill order (ignoring empty indices), reset masks/zoom, and drop extras.
  static LayoutComposerState migrateState(
    LayoutComposerState current,
    LayoutTemplate newTemplate,
  ) {
    final filledPhotos = current.slots
        .where((slot) => slot.hasImage)
        .map((slot) => slot.imagePath!)
        .toList(growable: false);

    final migratedSlots = <LayoutSlotContent>[];
    for (var index = 0; index < newTemplate.slotCount; index++) {
      final definition = newTemplate.slots[index];
      if (index < filledPhotos.length) {
        migratedSlots.add(
          LayoutSlotContent(
            imagePath: filledPhotos[index],
            shape: definition.defaultShape,
          ),
        );
      } else {
        migratedSlots.add(
          LayoutSlotContent(shape: definition.defaultShape),
        );
      }
    }
    return current.copyWith(
      templateId: newTemplate.id,
      slots: migratedSlots,
      clearSelectedSlot: true,
      clearSplitWeights: true,
      clearCellWeights: true,
    );
  }
}

/// Shape options shown in the bottom shape rail. Keep this to masks people
/// actually apply — novelty silhouettes stay out of the picker.
const List<LayoutShapeId> kLayoutShapePickerOrder = <LayoutShapeId>[
  LayoutShapeId.rectangle,
  LayoutShapeId.roundedRect,
  LayoutShapeId.squircle,
  LayoutShapeId.square,
  LayoutShapeId.circle,
  LayoutShapeId.oval,
  LayoutShapeId.capsule,
  LayoutShapeId.arch,
  LayoutShapeId.heart,
  LayoutShapeId.diamond,
  LayoutShapeId.roundedDiamond,
  LayoutShapeId.star,
  LayoutShapeId.leaf,
  LayoutShapeId.hexagon,
];
