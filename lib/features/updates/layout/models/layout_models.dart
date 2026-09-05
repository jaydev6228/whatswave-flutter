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

/// A reusable collage blueprint. Templates are pure data so we can add more
/// without touching rendering or export code.
@immutable
class LayoutTemplate {
  const LayoutTemplate({
    required this.id,
    required this.label,
    required this.slots,
    this.gutter = 0.012,
  });

  final String id;
  final String label;
  final List<LayoutSlotDefinition> slots;

  /// White-space between slots, as a fraction of canvas width.
  final double gutter;

  int get slotCount => slots.length;
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
  });

  final String? imagePath;
  final double scale;
  final double focalDx;
  final double focalDy;
  final LayoutShapeId shape;
  final int? fillColorValue;
  final int? borderColorValue;
  final double borderWidth;

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
    );
  }
}

/// Canvas shapes the composer can post. Templates are normalized 0–1, so
/// they lay out unchanged in any of these.
enum LayoutCanvasRatio {
  story(kLayoutStoryAspectRatio, '9:16'),
  portrait(4 / 5, '4:5'),
  square(1, '1:1');

  const LayoutCanvasRatio(this.value, this.label);

  final double value;
  final String label;
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
  });

  final String templateId;
  final int backgroundColorValue;
  final List<LayoutSlotContent> slots;
  final LayoutCanvasRatio ratio;
  final int? selectedSlotIndex;

  Color get backgroundColor => Color(backgroundColorValue);

  bool get canShare => slots.any((slot) => slot.hasImage);

  LayoutComposerState copyWith({
    String? templateId,
    int? backgroundColorValue,
    List<LayoutSlotContent>? slots,
    LayoutCanvasRatio? ratio,
    int? selectedSlotIndex,
    bool clearSelectedSlot = false,
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
    );
  }
}

/// Returned when the user posts a layout story. The canvas is flattened to
/// one JPEG so the existing photo-status pipeline handles upload + viewing.
class LayoutStatusComposerDraft {
  const LayoutStatusComposerDraft({
    required this.exportedImagePath,
    this.aspectRatio = kLayoutStoryAspectRatio,
    this.caption = '',
  });

  final String exportedImagePath;

  /// The canvas shape the export was composed in. The viewer needs it to
  /// letterbox the image instead of cover-fitting (and cropping) it.
  final double aspectRatio;
  final String caption;
}

/// Story canvas dimensions used for preview and export.
const double kLayoutStoryAspectRatio = 9 / 16;
const int kLayoutExportWidth = 1080;
const int kLayoutExportHeight = 1920;

/// Max decode size for on-screen previews — keeps GPU memory bounded even
/// when the user fills every slot with 12 MP camera photos.
const int kLayoutPreviewMaxPixelSize = 720;

/// Scales preview decode down as more slots fill so six photos never allocate
/// six full-size GPU textures at once.
int layoutPreviewCacheWidth(int filledSlotCount) {
  final count = filledSlotCount.clamp(1, 8);
  return (kLayoutPreviewMaxPixelSize / math.sqrt(count))
      .round()
      .clamp(240, kLayoutPreviewMaxPixelSize);
}
