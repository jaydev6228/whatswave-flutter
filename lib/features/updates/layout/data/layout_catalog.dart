import 'dart:ui';

import 'package:flutter/foundation.dart';

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
    for (final template in templates) {
      if (template.id == id) {
        return template;
      }
    }
    for (final template in shapeCollages) {
      if (template.id == id) {
        return template;
      }
    }
    return templates.first;
  }

  static bool isShapeCollage(String templateId) {
    return shapeCollages.any((template) => template.id == templateId);
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

/// One tile in the Shapes rail — a single mask, or a multi-photo collage.
@immutable
class LayoutShapeRailEntry {
  const LayoutShapeRailEntry.mask(this.shape) : templateId = null;
  const LayoutShapeRailEntry.collage(this.templateId) : shape = null;

  final LayoutShapeId? shape;
  final String? templateId;

  bool get isCollage => templateId != null;

  String get keyName => isCollage
      ? 'layout_shape_collage_$templateId'
      : 'layout_shape_${shape!.name}';
}

LayoutSlotDefinition _shapeSlot(
  double left,
  double top,
  double width,
  double height,
  LayoutShapeId shape,
) {
  return LayoutSlotDefinition(
    rect: Rect.fromLTWH(left, top, width, height),
    defaultShape: shape,
  );
}

/// Multi-photo organic collages shown in Shapes, never in Layouts.
final List<LayoutTemplate> shapeCollages = <LayoutTemplate>[
  LayoutTemplate(
    id: 'shape_two_hearts_offset',
    label: '2 hearts',
    slots: <LayoutSlotDefinition>[
      _shapeSlot(0.10, 0.12, 0.72, 0.52, LayoutShapeId.heart),
      _shapeSlot(0.42, 0.52, 0.48, 0.36, LayoutShapeId.heart),
    ],
  ),
  LayoutTemplate(
    id: 'shape_two_petals',
    label: '2 petals',
    slots: <LayoutSlotDefinition>[
      _shapeSlot(0.08, 0.36, 0.56, 0.38, LayoutShapeId.roundDiag),
      _shapeSlot(0.30, 0.16, 0.62, 0.42, LayoutShapeId.roundDiag),
    ],
  ),
  const LayoutTemplate(
    id: 'shape_broken_heart',
    label: 'Broken heart',
    previewAsset: 'assets/layout/shapes/broken_heart.png',
    slots: <LayoutSlotDefinition>[
      LayoutSlotDefinition(
        rect: Rect.fromLTWH(0.0058, 0.2609, 0.5510, 0.4781),
        defaultShape: LayoutShapeId.brokenHeartLeft,
      ),
      LayoutSlotDefinition(
        rect: Rect.fromLTWH(0.4538, 0.2609, 0.5403, 0.4716),
        defaultShape: LayoutShapeId.brokenHeartRight,
      ),
    ],
  ),
  LayoutTemplate(
    id: 'shape_two_hearts_stack',
    label: '2 hearts stacked',
    slots: <LayoutSlotDefinition>[
      _shapeSlot(0.22, 0.08, 0.56, 0.34, LayoutShapeId.heart),
      _shapeSlot(0.10, 0.40, 0.80, 0.50, LayoutShapeId.heart),
    ],
  ),
  LayoutTemplate(
    id: 'shape_split_capsule',
    label: 'Split capsule',
    slots: <LayoutSlotDefinition>[
      _shapeSlot(0.16, 0.12, 0.68, 0.37, LayoutShapeId.capsuleTop),
      _shapeSlot(0.16, 0.51, 0.68, 0.37, LayoutShapeId.capsuleBottom),
    ],
  ),
  LayoutTemplate(
    id: 'shape_two_teardrops',
    label: '2 teardrops',
    slots: <LayoutSlotDefinition>[
      _shapeSlot(0.22, 0.08, 0.56, 0.42, LayoutShapeId.teardrop),
      _shapeSlot(0.22, 0.50, 0.56, 0.42, LayoutShapeId.teardropDown),
    ],
  ),
  LayoutTemplate(
    id: 'shape_two_circles',
    label: '2 circles',
    slots: <LayoutSlotDefinition>[
      _shapeSlot(0.16, 0.08, 0.68, 0.40, LayoutShapeId.circle),
      _shapeSlot(0.16, 0.52, 0.68, 0.40, LayoutShapeId.circle),
    ],
  ),
  LayoutTemplate(
    id: 'shape_two_circles_overlap',
    label: '2 circles overlap',
    slots: <LayoutSlotDefinition>[
      _shapeSlot(0.42, 0.14, 0.46, 0.28, LayoutShapeId.circle),
      _shapeSlot(0.12, 0.28, 0.72, 0.46, LayoutShapeId.circle),
    ],
  ),
  LayoutTemplate(
    id: 'shape_two_squircles',
    label: '2 squircles',
    slots: <LayoutSlotDefinition>[
      _shapeSlot(0.16, 0.10, 0.68, 0.40, LayoutShapeId.squircle),
      _shapeSlot(0.16, 0.50, 0.68, 0.40, LayoutShapeId.squircle),
    ],
  ),
  LayoutTemplate(
    id: 'shape_three_brushes',
    label: '3 brushes',
    slots: <LayoutSlotDefinition>[
      _shapeSlot(0.04, 0.05, 0.92, 0.28, LayoutShapeId.brushDiagonal),
      _shapeSlot(0.04, 0.36, 0.92, 0.28, LayoutShapeId.brushDiagonal),
      _shapeSlot(0.04, 0.67, 0.92, 0.28, LayoutShapeId.brushDiagonal),
    ],
  ),
  LayoutTemplate(
    id: 'shape_three_hearts',
    label: '3 hearts',
    slots: <LayoutSlotDefinition>[
      _shapeSlot(0.28, 0.04, 0.44, 0.24, LayoutShapeId.heart),
      _shapeSlot(0.10, 0.26, 0.80, 0.46, LayoutShapeId.heart),
      _shapeSlot(0.28, 0.72, 0.44, 0.24, LayoutShapeId.heart),
    ],
  ),
  LayoutTemplate(
    id: 'shape_three_hearts_cluster',
    label: '3 hearts cluster',
    slots: <LayoutSlotDefinition>[
      _shapeSlot(0.08, 0.10, 0.42, 0.28, LayoutShapeId.heart),
      _shapeSlot(0.50, 0.10, 0.42, 0.28, LayoutShapeId.heart),
      _shapeSlot(0.14, 0.36, 0.72, 0.50, LayoutShapeId.heart),
    ],
  ),
  LayoutTemplate(
    id: 'shape_four_hearts',
    label: '4 hearts',
    slots: <LayoutSlotDefinition>[
      _shapeSlot(0.16, 0.04, 0.68, 0.40, LayoutShapeId.heart),
      _shapeSlot(0.08, 0.40, 0.40, 0.28, LayoutShapeId.heart),
      _shapeSlot(0.52, 0.40, 0.40, 0.28, LayoutShapeId.heart),
      _shapeSlot(0.30, 0.64, 0.40, 0.28, LayoutShapeId.heart),
    ],
  ),
  LayoutTemplate(
    id: 'shape_three_ovals',
    label: '3 ovals',
    slots: <LayoutSlotDefinition>[
      _shapeSlot(0.06, 0.08, 0.50, 0.30, LayoutShapeId.circle),
      _shapeSlot(0.22, 0.32, 0.62, 0.22, LayoutShapeId.horizontalOval),
      _shapeSlot(0.40, 0.52, 0.52, 0.30, LayoutShapeId.circle),
    ],
  ),
];

/// Single silhouettes in the Shapes rail (collages are appended after).
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
  LayoutShapeId.cutCornerRect,
  LayoutShapeId.octagon,
  LayoutShapeId.wavyBottom,
  LayoutShapeId.brushWide,
  LayoutShapeId.roughCircle,
  LayoutShapeId.brushH2,
  LayoutShapeId.brushH3,
  LayoutShapeId.brushDiagonal,
  LayoutShapeId.brushTall,
  LayoutShapeId.brushBlock,
  LayoutShapeId.brushSplat,
  LayoutShapeId.sealCircle,
  LayoutShapeId.leafCorners,
  LayoutShapeId.speechRound,
  LayoutShapeId.roundedStar,
  LayoutShapeId.blob,
  LayoutShapeId.cloud,
];

final List<LayoutShapeRailEntry> kLayoutShapeRail = <LayoutShapeRailEntry>[
  for (final shape in kLayoutShapePickerOrder) LayoutShapeRailEntry.mask(shape),
  for (final collage in shapeCollages)
    LayoutShapeRailEntry.collage(collage.id),
];
