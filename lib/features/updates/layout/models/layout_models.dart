import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Identifiers for slot mask shapes. Extend this enum as new silhouettes
/// are added — the clipper registry maps each id to a [CustomClipper].
enum LayoutShapeId {
  rectangle,
  roundedRect,
  circle,
  oval,
  arch,
  heart,
  diamond,
  roundedDiamond,
  star,
  blob,
  speechBubble,
  shield,
  clippedRect,
  concave,
  banner,
  hexagon,
  triangle,
  teardrop,
  ticket,
  square,
  squircle,
  capsule,
  pentagon,
  octagon,
  cutCornerRect,
  oneRoundCorner,
  dropCorner,
  leaf,
  scallopedSquare,
  scallopedCircle,
  quatrefoil,
  cloud,
  sparkle,
  chevron,
  bittenCircle,
  wavyFlag,
  wavySides,
  pebble,
  brushStroke,
  horizontalOval,
  tiltedOval,
  wavyBottom,
  tornBottom,
  tornPaper,
  roughCircle,
  brushWide,
  brushTall,
  roundedStar,
  ribbon,
  eightPointStar,
  speechRound,
  waveTop,
  waveMid,
  waveBottom,
  waveTopB,
  waveMidB,
  waveBottomB,
  slantDown,
  slantMid,
  slantUp,
  roundCornerTL,
  roundCornerTR,
  roundCornerBL,
  roundCornerBR,
}

/// One rectangular region inside a [LayoutTemplate], expressed in normalized
/// 0–1 coordinates relative to the 9:16 story canvas.
@immutable
class LayoutSlotDefinition {
  const LayoutSlotDefinition({
    required this.rect,
    this.defaultShape = LayoutShapeId.rectangle,
    this.cornerRadius = 0,
  });

  final Rect rect;
  final LayoutShapeId defaultShape;

  /// Normalized corner radius for rectangular slots (0–0.5 of min side).
  final double cornerRadius;

  LayoutSlotDefinition copyWith({
    Rect? rect,
    LayoutShapeId? defaultShape,
    double? cornerRadius,
  }) {
    return LayoutSlotDefinition(
      rect: rect ?? this.rect,
      defaultShape: defaultShape ?? this.defaultShape,
      cornerRadius: cornerRadius ?? this.cornerRadius,
    );
  }
}

/// Row-stacked vs column-stacked bands. Handles drag along the other axis.
enum LayoutSplitAxis { rows, columns }

/// How a grid template is built so split handles can re-weight the bands.
@immutable
class LayoutGridSpec {
  const LayoutGridSpec({
    required this.axis,
    required this.bands,
  });

  final LayoutSplitAxis axis;

  /// Cells in each band. `[1, 2]` is one full row over two cells.
  final List<int> bands;

  int get bandCount => bands.length;

  bool get canSplit =>
      bandCount >= 2 || bands.any((count) => count >= 2);
}

/// A reusable collage blueprint. Templates are pure data so we can add more
/// without touching rendering or export code.
@immutable
class LayoutTemplate {
  const LayoutTemplate({
    required this.id,
    required this.label,
    required this.slots,
    this.gutter = 0.012,
    this.grid,
  });

  final String id;
  final String label;
  final List<LayoutSlotDefinition> slots;

  /// White-space between slots, as a fraction of canvas width.
  final double gutter;

  /// When set, slots are rebuilt from [resolveLayoutSlots] so the user can
  /// drag band weights and the frame slider.
  final LayoutGridSpec? grid;

  int get slotCount => slots.length;
}

/// Frame treatment on a photo. Names are what the user sees, not design
/// movements: Soft is the raised clay/neomorph look, Bold is a thick
/// poster border. Leather-style skeuomorphism is skipped — it does not
/// read on a photo.
enum LayoutSlotLook {
  none('None'),
  border('Border'),
  shadow('Shadow'),
  soft('Soft'),
  bold('Bold');

  const LayoutSlotLook(this.label);

  final String label;

  bool get usesColor => this != none;

  double get strokeWidth => switch (this) {
        none || shadow || soft => 0,
        border => 3,
        bold => 8,
      };

  bool get paintsShadow => this == shadow || this == soft;

  int get defaultColorValue =>
      this == shadow ? 0xFF000000 : 0xFFFFFFFF;
}

/// Runtime content for one slot while the user is editing.
@immutable
class LayoutSlotContent {
  const LayoutSlotContent({
    this.imagePath,
    this.scale = 1,
    this.focalDx = 0.5,
    this.focalDy = 0.5,
    this.shape = LayoutShapeId.rectangle,
    this.fillColorValue,
    this.borderColorValue,
    this.borderWidth = 0,
    this.look = LayoutSlotLook.none,
  });

  final String? imagePath;
  final double scale;
  final double focalDx;
  final double focalDy;
  final LayoutShapeId shape;
  final int? fillColorValue;
  final int? borderColorValue;
  final double borderWidth;
  final LayoutSlotLook look;

  bool get hasImage =>
      imagePath != null && imagePath!.trim().isNotEmpty;

  Color get fillColor => Color(fillColorValue ?? 0xFFFFFFFF);

  Color? get borderColor =>
      borderColorValue == null ? null : Color(borderColorValue!);

  LayoutSlotContent copyWith({
    String? imagePath,
    bool clearImagePath = false,
    double? scale,
    double? focalDx,
    double? focalDy,
    LayoutShapeId? shape,
    int? fillColorValue,
    int? borderColorValue,
    bool clearBorderColor = false,
    double? borderWidth,
    LayoutSlotLook? look,
  }) {
    return LayoutSlotContent(
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      scale: scale ?? this.scale,
      focalDx: focalDx ?? this.focalDx,
      focalDy: focalDy ?? this.focalDy,
      shape: shape ?? this.shape,
      fillColorValue: fillColorValue ?? this.fillColorValue,
      borderColorValue: clearBorderColor
          ? null
          : (borderColorValue ?? this.borderColorValue),
      borderWidth: borderWidth ?? this.borderWidth,
      look: look ?? this.look,
    );
  }
}

/// Canvas shapes the composer can post. Templates are normalized 0–1, so
/// they lay out unchanged in any of these.
///
/// [fullScreen] fills this device's safe area while editing. The posted
/// image is still that collage (no notch baked in); the viewer contain-fits
/// it and fills leftover bands with the layout colour so every phone
/// sees the same photos.
enum LayoutCanvasRatio {
  fullScreen(null, 'Full screen'),
  story(kLayoutStoryAspectRatio, '9:16'),
  portrait23(2 / 3, '2:3'),
  portrait34(3 / 4, '3:4'),
  portrait(4 / 5, '4:5'),
  square(1, '1:1'),
  landscape32(3 / 2, '3:2'),
  landscape43(4 / 3, '4:3'),
  landscape(16 / 9, '16:9');

  const LayoutCanvasRatio(this.value, this.label);

  /// Null means fill the available safe-area canvas.
  final double? value;
  final String label;

  double resolve(Size canvasSize) {
    final fixed = value;
    if (fixed != null && fixed > 0) {
      return fixed;
    }
    if (canvasSize.height > 0) {
      return canvasSize.width / canvasSize.height;
    }
    return kLayoutStoryAspectRatio;
  }
}

/// Usable story canvas: screen minus notch, home indicator, and side
/// cutouts, so the same collage rules apply in portrait, landscape, and
/// on both iOS and Android.
Size layoutComposerSafeAreaSize({
  required Size screenSize,
  required double topInset,
  required double bottomInset,
  double leftInset = 0,
  double rightInset = 0,
}) {
  return Size(
    math.max(screenSize.width - leftInset - rightInset, 0),
    math.max(screenSize.height - topInset - bottomInset, 0),
  );
}

/// Full editable state for the layout composer. Kept separate from widgets
/// so export, tests, and future persistence can share one source of truth.
@immutable
class LayoutComposerState {
  const LayoutComposerState({
    required this.templateId,
    required this.backgroundColorValue,
    required this.slots,
    this.ratio = LayoutCanvasRatio.story,
    this.selectedSlotIndex,
    this.frame = kLayoutDefaultFrame,
    this.splitWeights,
    this.cellWeights,
  });

  final String templateId;
  final int backgroundColorValue;
  final List<LayoutSlotContent> slots;
  final LayoutCanvasRatio ratio;
  final int? selectedSlotIndex;

  /// 0 = flush photos, 1 = thick frame around and between slots.
  final double frame;

  /// Band weights for [LayoutTemplate.grid]. Null means equal bands.
  final List<double>? splitWeights;

  /// Per-band cell weights. Null means equal cells inside each band.
  final List<List<double>>? cellWeights;

  Color get backgroundColor => Color(backgroundColorValue);

  bool get canShare => slots.any((slot) => slot.hasImage);

  LayoutComposerState copyWith({
    String? templateId,
    int? backgroundColorValue,
    List<LayoutSlotContent>? slots,
    LayoutCanvasRatio? ratio,
    int? selectedSlotIndex,
    bool clearSelectedSlot = false,
    double? frame,
    List<double>? splitWeights,
    bool clearSplitWeights = false,
    List<List<double>>? cellWeights,
    bool clearCellWeights = false,
  }) {
    return LayoutComposerState(
      templateId: templateId ?? this.templateId,
      backgroundColorValue:
          backgroundColorValue ?? this.backgroundColorValue,
      slots: slots ?? this.slots,
      ratio: ratio ?? this.ratio,
      selectedSlotIndex: clearSelectedSlot
          ? null
          : (selectedSlotIndex ?? this.selectedSlotIndex),
      frame: frame ?? this.frame,
      splitWeights: clearSplitWeights
          ? null
          : (splitWeights ?? this.splitWeights),
      cellWeights: clearCellWeights
          ? null
          : (cellWeights ?? this.cellWeights),
    );
  }
}

/// Returned when the user posts a layout story. The canvas is flattened to
/// one JPEG so the existing photo-status pipeline handles upload + viewing.
class LayoutStatusComposerDraft {
  const LayoutStatusComposerDraft({
    required this.exportedImagePath,
    this.aspectRatio = kLayoutStoryAspectRatio,
    this.backgroundColorValue,
    this.caption = '',
  });

  final String exportedImagePath;

  /// The canvas shape the export was composed in. The viewer contain-fits
  /// to this instead of cover-cropping. Null fills the viewer's screen.
  final double? aspectRatio;

  /// Posted letterbox colour. Must travel with the image so leftover
  /// bands on a different phone match the collage, not black.
  final int? backgroundColorValue;
  final String caption;
}

/// Story canvas dimensions used for preview and export.
const double kLayoutStoryAspectRatio = 9 / 16;
const int kLayoutExportWidth = 1080;
const int kLayoutExportHeight = 1920;

/// Max decode edge for on-screen previews. High enough for a 3x tall slot
/// without pulling in a full 12 MP camera frame.
const int kLayoutPreviewMaxPixelSize = 1440;

/// Decode width so a cover-fit in [slotSize] stays sharp on this screen.
int layoutPreviewCacheWidth({
  required Size slotSize,
  required double devicePixelRatio,
  double zoom = 1,
  Size? imageSize,
}) {
  final dpr = devicePixelRatio.clamp(1.0, 4.0);
  final zoomed = zoom.clamp(1.0, 3.0);
  final physical = Size(
    slotSize.width * dpr * zoomed,
    slotSize.height * dpr * zoomed,
  );
  var needed = physical.longestSide;
  if (imageSize != null && imageSize.width > 0 && imageSize.height > 0) {
    final forWidth = physical.width;
    final forHeight = physical.height * imageSize.width / imageSize.height;
    needed = math.max(forWidth, forHeight);
  }
  return needed.round().clamp(360, kLayoutPreviewMaxPixelSize);
}

/// Default frame slider — a little space between photos (~5%).
const double kLayoutDefaultFrame = 0.05;

/// Smallest share a dragged band may keep.
const double kLayoutMinBandFraction = 0.18;

/// Max edge/gutter gap as a fraction of canvas **width**, so top/bottom
/// match left/right in pixels on a tall story canvas.
const double kLayoutFrameGap = 0.10;

@immutable
class LayoutFrameSpacing {
  const LayoutFrameSpacing({
    required this.insetX,
    required this.insetY,
    required this.gutterX,
    required this.gutterY,
  });

  const LayoutFrameSpacing.zero()
      : insetX = 0,
        insetY = 0,
        gutterX = 0,
        gutterY = 0;

  final double insetX;
  final double insetY;
  final double gutterX;
  final double gutterY;
}

/// Same pixel gap on every edge and between photos.
LayoutFrameSpacing layoutFrameSpacing(
  double frame, {
  double aspect = kLayoutStoryAspectRatio,
}) {
  final gap = kLayoutFrameGap * frame.clamp(0.0, 1.0);
  final ratio = aspect > 0 ? aspect : kLayoutStoryAspectRatio;
  final gapY = gap * ratio;
  return LayoutFrameSpacing(
    insetX: gap,
    insetY: gapY,
    gutterX: gap,
    gutterY: gapY,
  );
}

double layoutFrameGutter(double frame) => layoutFrameSpacing(frame).gutterX;

List<double> layoutNormalizedWeights(List<double>? weights, int count) {
  if (count <= 0) {
    return const <double>[];
  }
  if (weights == null || weights.length != count) {
    return List<double>.filled(count, 1 / count);
  }
  final total = weights.fold<double>(0, (sum, weight) => sum + weight.abs());
  if (total <= 0) {
    return List<double>.filled(count, 1 / count);
  }
  return [for (final weight in weights) weight.abs() / total];
}

List<List<double>> layoutSeedCellWeights(
  LayoutGridSpec grid,
  List<List<double>>? current,
) {
  return [
    for (var band = 0; band < grid.bandCount; band++)
      layoutNormalizedWeights(
        current != null && band < current.length ? current[band] : null,
        grid.bands[band],
      ),
  ];
}

/// Rebuilds slot rects from the template grid (or inset baked slots).
List<LayoutSlotDefinition> resolveLayoutSlots({
  required LayoutTemplate template,
  List<double>? weights,
  List<List<double>>? cellWeights,
  double frame = 0,
  double aspect = kLayoutStoryAspectRatio,
}) {
  final spacing = layoutFrameSpacing(frame, aspect: aspect);
  final grid = template.grid;
  if (grid != null) {
    return layoutSlotsForGrid(
      grid: grid,
      weights: layoutNormalizedWeights(weights, grid.bandCount),
      cellWeights: layoutSeedCellWeights(grid, cellWeights),
      spacing: spacing,
    );
  }
  final innerW = 1 - 2 * spacing.insetX;
  final innerH = 1 - 2 * spacing.insetY;
  return [
    for (final slot in template.slots)
      slot.copyWith(
        rect: Rect.fromLTWH(
          spacing.insetX + slot.rect.left * innerW,
          spacing.insetY + slot.rect.top * innerH,
          slot.rect.width * innerW,
          slot.rect.height * innerH,
        ),
      ),
  ];
}

List<LayoutSlotDefinition> layoutSlotsForGrid({
  required LayoutGridSpec grid,
  required List<double> weights,
  List<List<double>>? cellWeights,
  LayoutFrameSpacing spacing = const LayoutFrameSpacing.zero(),
}) {
  final slots = <LayoutSlotDefinition>[];
  final innerW = 1 - 2 * spacing.insetX;
  final innerH = 1 - 2 * spacing.insetY;
  final cells = layoutSeedCellWeights(grid, cellWeights);
  final bandAlongX = grid.axis == LayoutSplitAxis.columns;
  var cursor = bandAlongX ? spacing.insetX : spacing.insetY;
  for (var band = 0; band < grid.bandCount; band++) {
    final inner = bandAlongX ? innerW : innerH;
    final span = band == grid.bandCount - 1
        ? math.max((bandAlongX ? spacing.insetX : spacing.insetY) + inner - cursor, 0.0)
        : weights[band] * inner;
    final count = grid.bands[band];
    var cellCursor = bandAlongX ? spacing.insetY : spacing.insetX;
    for (var cell = 0; cell < count; cell++) {
      final cellInner = bandAlongX ? innerH : innerW;
      final cellSpan = cell == count - 1
          ? math.max(
              (bandAlongX ? spacing.insetY : spacing.insetX) + cellInner - cellCursor,
              0.0,
            )
          : cells[band][cell] * cellInner;
      late final Rect rect;
      if (grid.axis == LayoutSplitAxis.rows) {
        rect = _gutteredRect(
          left: cellCursor,
          top: cursor,
          right: cellCursor + cellSpan,
          bottom: cursor + span,
          spacing: spacing,
        );
      } else {
        rect = _gutteredRect(
          left: cursor,
          top: cellCursor,
          right: cursor + span,
          bottom: cellCursor + cellSpan,
          spacing: spacing,
        );
      }
      slots.add(LayoutSlotDefinition(rect: rect));
      cellCursor += cellSpan;
    }
    cursor += span;
  }
  return slots;
}

Rect _gutteredRect({
  required double left,
  required double top,
  required double right,
  required double bottom,
  required LayoutFrameSpacing spacing,
}) {
  return Rect.fromLTRB(
    left + (left > spacing.insetX + 0.0001 ? spacing.gutterX / 2 : 0),
    top + (top > spacing.insetY + 0.0001 ? spacing.gutterY / 2 : 0),
    right - (right < 1 - spacing.insetX - 0.0001 ? spacing.gutterX / 2 : 0),
    bottom - (bottom < 1 - spacing.insetY - 0.0001 ? spacing.gutterY / 2 : 0),
  );
}

/// One draggable divider between bands or between cells in a band.
@immutable
class LayoutSplitHandle {
  const LayoutSplitHandle({
    required this.boundaryIndex,
    required this.axis,
    required this.normalizedOffset,
    this.bandIndex,
    this.crossStart = 0,
    this.crossEnd = 1,
  });

  final int boundaryIndex;
  final LayoutSplitAxis axis;

  /// Null for a band divider; set for a cell divider inside that band.
  final int? bandIndex;

  /// 0–1 position of the divider along the drag axis.
  final double normalizedOffset;
  final double crossStart;
  final double crossEnd;

  bool get isCellHandle => bandIndex != null;

  String get keyName => isCellHandle
      ? 'layout_split_handle_cell_${bandIndex}_$boundaryIndex'
      : 'layout_split_handle_$boundaryIndex';
}

List<LayoutSplitHandle> layoutSplitHandles({
  required LayoutGridSpec grid,
  List<double>? weights,
  List<List<double>>? cellWeights,
  double frame = 0,
  double aspect = kLayoutStoryAspectRatio,
}) {
  if (!grid.canSplit) {
    return const <LayoutSplitHandle>[];
  }
  final spacing = layoutFrameSpacing(frame, aspect: aspect);
  final innerW = 1 - 2 * spacing.insetX;
  final innerH = 1 - 2 * spacing.insetY;
  final bandAlongX = grid.axis == LayoutSplitAxis.columns;
  final bandWeights = layoutNormalizedWeights(weights, grid.bandCount);
  final cells = layoutSeedCellWeights(grid, cellWeights);
  final handles = <LayoutSplitHandle>[];
  var bandCursor = bandAlongX ? spacing.insetX : spacing.insetY;
  for (var band = 0; band < grid.bandCount; band++) {
    final inner = bandAlongX ? innerW : innerH;
    final span = band == grid.bandCount - 1
        ? math.max(
            (bandAlongX ? spacing.insetX : spacing.insetY) + inner - bandCursor,
            0.0,
          )
        : bandWeights[band] * inner;
    var cellCursor = bandAlongX ? spacing.insetY : spacing.insetX;
    for (var cell = 0; cell < grid.bands[band] - 1; cell++) {
      final cellInner = bandAlongX ? innerH : innerW;
      cellCursor += cells[band][cell] * cellInner;
      handles.add(
        LayoutSplitHandle(
          axis: grid.axis == LayoutSplitAxis.rows
              ? LayoutSplitAxis.columns
              : LayoutSplitAxis.rows,
          boundaryIndex: cell,
          bandIndex: band,
          normalizedOffset: cellCursor,
          crossStart: bandCursor,
          crossEnd: bandCursor + span,
        ),
      );
    }
    if (band < grid.bandCount - 1) {
      handles.add(
        LayoutSplitHandle(
          axis: grid.axis,
          boundaryIndex: band,
          normalizedOffset: bandCursor + span,
          crossStart: bandAlongX ? spacing.insetY : spacing.insetX,
          crossEnd: bandAlongX
              ? spacing.insetY + innerH
              : spacing.insetX + innerW,
        ),
      );
    }
    bandCursor += span;
  }
  return handles;
}

List<double> layoutDragSplitWeights({
  required List<double> weights,
  required int boundaryIndex,
  required double deltaFraction,
}) {
  final next = List<double>.from(
    layoutNormalizedWeights(weights, weights.length),
  );
  if (boundaryIndex < 0 || boundaryIndex + 1 >= next.length) {
    return next;
  }
  final pair = next[boundaryIndex] + next[boundaryIndex + 1];
  final minShare = math.min(kLayoutMinBandFraction, pair / 2);
  final first = (next[boundaryIndex] + deltaFraction).clamp(minShare, pair - minShare);
  next[boundaryIndex] = first;
  next[boundaryIndex + 1] = pair - first;
  return next;
}
