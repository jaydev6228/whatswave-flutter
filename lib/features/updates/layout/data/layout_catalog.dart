import 'dart:ui';

import '../models/layout_models.dart';

/// Predefined collage templates inspired by common story layout apps.
/// All coordinates are normalized to the 9:16 canvas.
class LayoutCatalog {
  LayoutCatalog._();

  static const double _g = 0.012;

  static const List<LayoutTemplate> templates = <LayoutTemplate>[
    LayoutTemplate(
      id: 'single',
      label: 'Single',
      gutter: 0,
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 1, 1)),
      ],
    ),
    LayoutTemplate(
      id: 'two_columns',
      label: '2 columns',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 0.5 - _g / 2, 1)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.5 + _g / 2, 0, 0.5 - _g / 2, 1),
        ),
      ],
    ),
    LayoutTemplate(
      id: 'two_rows',
      label: '2 rows',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 1, 0.5 - _g / 2)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0, 0.5 + _g / 2, 1, 0.5 - _g / 2),
        ),
      ],
    ),
    LayoutTemplate(
      id: 'three_rows',
      label: '3 rows',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 1, 0.333 - _g * 0.66)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0, 0.333 + _g * 0.33, 1, 0.334 - _g * 0.66),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0, 0.667 + _g * 0.33, 1, 0.333 - _g * 0.66),
        ),
      ],
    ),
    LayoutTemplate(
      id: 'grid_2x2',
      label: '2×2',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0, 0, 0.5 - _g / 2, 0.5 - _g / 2),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.5 + _g / 2, 0, 0.5 - _g / 2, 0.5 - _g / 2),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0, 0.5 + _g / 2, 0.5 - _g / 2, 0.5 - _g / 2),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.5 + _g / 2, 0.5 + _g / 2, 0.5 - _g / 2, 0.5 - _g / 2),
        ),
      ],
    ),
    LayoutTemplate(
      id: 'hero_right',
      label: 'Tall right',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0, 0, 0.38 - _g / 2, 0.5 - _g / 2),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0, 0.5 + _g / 2, 0.38 - _g / 2, 0.5 - _g / 2),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.38 + _g / 2, 0, 0.62 - _g / 2, 1),
        ),
      ],
    ),
    LayoutTemplate(
      id: 'hero_left',
      label: 'Tall left',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 0.62 - _g / 2, 1)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.62 + _g / 2, 0, 0.38 - _g / 2, 0.5 - _g / 2),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.62 + _g / 2, 0.5 + _g / 2, 0.38 - _g / 2, 0.5 - _g / 2),
        ),
      ],
    ),
    LayoutTemplate(
      id: 'three_columns',
      label: '3 columns',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 0.333 - _g * 0.66, 1)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.333 + _g * 0.33, 0, 0.334 - _g * 0.66, 1),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.667 + _g * 0.33, 0, 0.333 - _g * 0.66, 1),
        ),
      ],
    ),
    LayoutTemplate(
      id: 'narrow_wide_narrow',
      label: 'Narrow sides',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 0.22, 1)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.22 + _g, 0, 0.56 - _g * 2, 1)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.78, 0, 0.22, 1)),
      ],
    ),
    LayoutTemplate(
      id: 'top_strip_three',
      label: 'Top strip',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 0.333 - _g * 0.66, 0.22)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.333 + _g * 0.33, 0, 0.334 - _g * 0.66, 0.22),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.667 + _g * 0.33, 0, 0.333 - _g * 0.66, 0.22),
        ),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0.22 + _g, 1, 0.78 - _g)),
      ],
    ),
    LayoutTemplate(
      id: 'bottom_strip_three',
      label: 'Bottom strip',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 1, 0.78 - _g)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0, 0.78 + _g, 0.333 - _g * 0.66, 0.22 - _g),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(
            0.333 + _g * 0.33,
            0.78 + _g,
            0.334 - _g * 0.66,
            0.22 - _g,
          ),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(
            0.667 + _g * 0.33,
            0.78 + _g,
            0.333 - _g * 0.66,
            0.22 - _g,
          ),
        ),
      ],
    ),
    LayoutTemplate(
      id: 'three_top_one_bottom',
      label: 'Three + hero',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 0.333 - _g * 0.66, 0.28)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.333 + _g * 0.33, 0, 0.334 - _g * 0.66, 0.28),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.667 + _g * 0.33, 0, 0.333 - _g * 0.66, 0.28),
        ),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0.28 + _g, 1, 0.72 - _g)),
      ],
    ),
    LayoutTemplate(
      id: 'sandwich',
      label: 'Sandwich',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 0.5 - _g / 2, 0.2)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.5 + _g / 2, 0, 0.5 - _g / 2, 0.2)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0.2 + _g, 1, 0.6 - _g * 2)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0, 0.8 + _g, 0.5 - _g / 2, 0.2 - _g),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.5 + _g / 2, 0.8 + _g, 0.5 - _g / 2, 0.2 - _g),
        ),
      ],
    ),
    LayoutTemplate(
      id: 'two_left_tall_right',
      label: '2 + tall',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 0.42, 0.5 - _g / 2)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0, 0.5 + _g / 2, 0.42, 0.5 - _g / 2),
        ),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.42 + _g, 0, 0.58 - _g, 1)),
      ],
    ),
    LayoutTemplate(
      id: 'arch_three_bottom',
      label: 'Arch',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.08, 0.02, 0.84, 0.52),
          defaultShape: LayoutShapeId.arch,
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0, 0.56 + _g, 0.333 - _g * 0.66, 0.42 - _g),
          cornerRadius: 0.08,
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(
            0.333 + _g * 0.33,
            0.56 + _g,
            0.334 - _g * 0.66,
            0.42 - _g,
          ),
          cornerRadius: 0.08,
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(
            0.667 + _g * 0.33,
            0.56 + _g,
            0.333 - _g * 0.66,
            0.42 - _g,
          ),
          cornerRadius: 0.08,
        ),
      ],
    ),
    LayoutTemplate(
      id: 'two_arches',
      label: 'Twin arches',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0, 0, 0.5 - _g / 2, 0.58),
          defaultShape: LayoutShapeId.arch,
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.5 + _g / 2, 0, 0.5 - _g / 2, 0.58),
          defaultShape: LayoutShapeId.arch,
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0, 0.58 + _g, 0.5 - _g / 2, 0.42 - _g),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.5 + _g / 2, 0.58 + _g, 0.5 - _g / 2, 0.42 - _g),
        ),
      ],
    ),
    LayoutTemplate(
      id: 'cross_hub',
      label: 'Cross',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.34, 0, 0.32, 0.28)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0.34, 0.32, 0.32)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.34, 0.34, 0.32, 0.32)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.68, 0.34, 0.32, 0.32)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.34, 0.68, 0.32, 0.32)),
      ],
    ),
    LayoutTemplate(
      id: 'plus_frame',
      label: 'Plus frame',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.28, 0.08, 0.44, 0.84)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.04, 0.04, 0.2, 0.2)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.76, 0.04, 0.2, 0.2)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.04, 0.76, 0.2, 0.2)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.76, 0.76, 0.2, 0.2)),
      ],
    ),
    LayoutTemplate(
      id: 'corner_accents',
      label: 'Corners',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.12, 0.12, 0.76, 0.76)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.02, 0.02, 0.22, 0.16)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.76, 0.02, 0.22, 0.16)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.02, 0.82, 0.22, 0.16)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.76, 0.82, 0.22, 0.16)),
      ],
    ),
    LayoutTemplate(
      id: 'diagonal_two',
      label: 'Diagonal',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 0.72, 0.55)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.28, 0.45, 0.72, 0.55)),
      ],
    ),
    LayoutTemplate(
      id: 'cascade',
      label: 'Cascade',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 1, 1)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.08, 0.12, 0.5, 0.28)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.28, 0.36, 0.5, 0.28)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.48, 0.6, 0.5, 0.28)),
      ],
    ),
    LayoutTemplate(
      id: 'inset_corner',
      label: 'Inset',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 1, 1)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.06, 0.06, 0.32, 0.22)),
      ],
    ),
    LayoutTemplate(
      id: 'film_strip',
      label: 'Film strip',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 0.68 - _g / 2, 1)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.68 + _g / 2, 0, 0.32 - _g / 2, 0.24 - _g * 0.75),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(
            0.68 + _g / 2,
            0.25 + _g * 0.25,
            0.32 - _g / 2,
            0.24 - _g * 0.75,
          ),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(
            0.68 + _g / 2,
            0.5 + _g * 0.25,
            0.32 - _g / 2,
            0.24 - _g * 0.75,
          ),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(
            0.68 + _g / 2,
            0.75 + _g * 0.25,
            0.32 - _g / 2,
            0.25 - _g * 0.75,
          ),
        ),
      ],
    ),
    LayoutTemplate(
      id: 'film_strip_three',
      label: 'Film 3',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 0.64, 1)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.64 + _g, 0, 0.36 - _g, 0.333 - _g * 0.66)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(
            0.64 + _g,
            0.333 + _g * 0.33,
            0.36 - _g,
            0.334 - _g * 0.66,
          ),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(
            0.64 + _g,
            0.667 + _g * 0.33,
            0.36 - _g,
            0.333 - _g * 0.66,
          ),
        ),
      ],
    ),
    LayoutTemplate(
      id: 'staggered_quad',
      label: 'Staggered',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 0.58, 0.46)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.58 + _g, 0.08, 0.42 - _g, 0.38)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0.46 + _g, 0.42, 0.54 - _g)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.42 + _g, 0.46 + _g, 0.58 - _g, 0.54 - _g),
        ),
      ],
    ),
    LayoutTemplate(
      id: 'mid_band_flanked',
      label: 'Mid band',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 1, 0.28)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0.28 + _g, 0.28, 0.44 - _g * 2)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.28 + _g, 0.28 + _g, 0.44 - _g * 2, 0.44 - _g * 2),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.72, 0.28 + _g, 0.28, 0.44 - _g * 2),
        ),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0.72, 1, 0.28)),
      ],
    ),
    LayoutTemplate(
      id: 'center_circle',
      label: 'Circle focus',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 1, 1)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.18, 0.28, 0.64, 0.36),
          defaultShape: LayoutShapeId.circle,
        ),
      ],
    ),
    LayoutTemplate(
      id: 'circle_and_squares',
      label: 'Circle + tiles',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 1, 1)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.06, 0.62, 0.36, 0.22),
          defaultShape: LayoutShapeId.circle,
        ),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.58, 0.08, 0.34, 0.18)),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0.58, 0.3, 0.34, 0.18)),
      ],
    ),
    LayoutTemplate(
      id: 'heart_scatter',
      label: 'Heart',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 1, 1)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.22, 0.28, 0.56, 0.36),
          defaultShape: LayoutShapeId.heart,
        ),
      ],
    ),
    LayoutTemplate(
      id: 'heart_cluster',
      label: 'Hearts',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 1, 1)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.32, 0.34, 0.36, 0.24),
          defaultShape: LayoutShapeId.heart,
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.08, 0.12, 0.22, 0.14),
          defaultShape: LayoutShapeId.heart,
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.7, 0.12, 0.22, 0.14),
          defaultShape: LayoutShapeId.heart,
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.08, 0.72, 0.22, 0.14),
          defaultShape: LayoutShapeId.heart,
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.7, 0.72, 0.22, 0.14),
          defaultShape: LayoutShapeId.heart,
        ),
      ],
    ),
    LayoutTemplate(
      id: 'masonry_six',
      label: 'Masonry',
      slots: <LayoutSlotDefinition>[
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0, 0.5 - _g / 2, 0.38)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.5 + _g / 2, 0, 0.5 - _g / 2, 0.24),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.5 + _g / 2, 0.24 + _g, 0.5 - _g / 2, 0.3),
        ),
        LayoutSlotDefinition(rect: Rect.fromLTWH(0, 0.38 + _g, 0.5 - _g / 2, 0.3)),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0.5 + _g / 2, 0.54 + _g, 0.5 - _g / 2, 0.46 - _g),
        ),
        LayoutSlotDefinition(
          rect: Rect.fromLTWH(0, 0.68 + _g, 0.5 - _g / 2, 0.32 - _g),
        ),
      ],
    ),
  ];

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
    );
  }
}

/// Shape options shown in the bottom shape rail.
const List<LayoutShapeId> kLayoutShapePickerOrder = <LayoutShapeId>[
  LayoutShapeId.rectangle,
  LayoutShapeId.roundedRect,
  LayoutShapeId.circle,
  LayoutShapeId.oval,
  LayoutShapeId.arch,
  LayoutShapeId.heart,
  LayoutShapeId.diamond,
  LayoutShapeId.roundedDiamond,
  LayoutShapeId.star,
  LayoutShapeId.blob,
  LayoutShapeId.speechBubble,
  LayoutShapeId.shield,
  LayoutShapeId.clippedRect,
  LayoutShapeId.concave,
  LayoutShapeId.banner,
  LayoutShapeId.hexagon,
  LayoutShapeId.triangle,
  LayoutShapeId.teardrop,
  LayoutShapeId.ticket,
];
