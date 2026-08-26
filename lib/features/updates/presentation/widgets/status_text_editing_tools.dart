import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/models/status_story.dart';
import '../status_motion.dart';
import 'status_media_decoration_overlay.dart';
import 'text_status_canvas.dart';

/// The text-editing tool shared by both status composers.
///
/// Written for the media composer's "Add text" overlay first, then pulled
/// out here so the text status composer uses the very same controls rather
/// than a parallel implementation that drifts from it. Every widget takes
/// its [Key]s from the caller, so each screen keeps the keys its own tests
/// and semantics already rely on.
///
/// Anything specific to one composer -- the media composer's placement and
/// dragging, the text composer's backgrounds, layouts and shuffle -- stays
/// with that screen; only the text-styling controls live here.
const List<Color> kStatusTextColorStops = [
  Colors.white,
  Color(0xFFFF3B30),
  Color(0xFFFF9500),
  Color(0xFFFFCC00),
  Color(0xFF34C759),
  Color(0xFF00C7BE),
  Color(0xFF0A84FF),
  Color(0xFFBF5AF2),
  Colors.black,
];

/// The colour at [t] (0..1) along [kStatusTextColorStops] -- a continuous
/// blend rather than a fixed swatch list, so dragging the rail sweeps
/// through every shade in between.
Color statusTextColorForBarPosition(double t) {
  const stops = kStatusTextColorStops;
  final segmentCount = stops.length - 1;
  final scaled = t.clamp(0.0, 1.0) * segmentCount;
  final index = scaled.floor().clamp(0, segmentCount - 1);
  final localT = scaled - index;
  return Color.lerp(stops[index], stops[index + 1], localT)!;
}

/// The editable text card itself: the text you type, rendered in the style
/// it will actually be posted in.
class StatusTextEditorCard extends StatelessWidget {
  const StatusTextEditorCard({
    required this.controller,
    required this.focusNode,
    required this.textStyleModel,
    required this.fieldKey,
    this.hintText = 'Type something',
    this.cardKey,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final StatusTextStyle textStyleModel;
  final Key fieldKey;
  final Key? cardKey;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = resolveTextStatusFontLook(textStyleModel.fontId);
    final hasSolidBackground = textStyleModel.useSolidBackground ||
        textStyleModel.backgroundColor != null;
    final surfaceColor = (textStyleModel.backgroundColor ?? Colors.black)
        .withValues(alpha: hasSolidBackground ? 0.62 : 0.22);
    final textStyle = look.apply(
      (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
        color: textStyleModel.textColor ?? Colors.white,
        fontSize: 24 * textStyleModel.sizeScale.clamp(0.72, 1.28),
        fontWeight: FontWeight.w800,
        height: 1.12,
        shadows: <Shadow>[
          Shadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );

    // Wrap at exactly the width a posted overlay wraps at, so what is typed
    // here breaks across lines the same way it will on the story.
    final textBounds = statusOverlayTextBoundsFor(MediaQuery.sizeOf(context));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Show as many lines as the editing area can actually hold rather
        // than a fixed few, so long text looks here like it will once
        // posted; past that the field scrolls internally.
        final lineHeight =
            (textStyle.fontSize ?? 24) * (textStyle.height ?? 1.12);
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight - 20
            : lineHeight * 5;
        final visibleLines = (availableHeight / lineHeight).floor().clamp(3, 40);

        return ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 120,
            maxWidth: textBounds.width,
          ),
          child: Container(
            key: cardKey,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: TextField(
              key: fieldKey,
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              minLines: 1,
              maxLines: visibleLines,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              textAlign: switch (textStyleModel.alignment) {
                StatusTextAlignment.left => TextAlign.left,
                StatusTextAlignment.center => TextAlign.center,
                StatusTextAlignment.right => TextAlign.right,
              },
              style: textStyle,
              cursorColor: textStyleModel.textColor ?? Colors.white,
              decoration: InputDecoration.collapsed(
                hintText: hintText,
                hintStyle: textStyle.copyWith(
                  color: (textStyleModel.textColor ?? Colors.white)
                      .withValues(alpha: 0.42),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The vertical colour rail that floats on the right edge while editing --
/// a continuous drag-to-pick gradient rather than a fixed swatch list.
class StatusTextColorRail extends StatefulWidget {
  const StatusTextColorRail({
    required this.selectedColor,
    required this.onSelectColor,
    required this.railKey,
    required this.barKey,
    required this.thumbKey,
    super.key,
  });

  final Color selectedColor;
  final ValueChanged<Color> onSelectColor;
  final Key railKey;
  final Key barKey;
  final Key thumbKey;

  @override
  State<StatusTextColorRail> createState() => _StatusTextColorRailState();
}

class _StatusTextColorRailState extends State<StatusTextColorRail> {
  double _barPosition = 0;

  void _updateFromLocalY(double localY, double height) {
    if (height <= 0) {
      return;
    }
    final position = (localY / height).clamp(0.0, 1.0);
    setState(() => _barPosition = position);
    widget.onSelectColor(statusTextColorForBarPosition(position));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: widget.railKey,
      width: 34,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          return GestureDetector(
            key: widget.barKey,
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) =>
                _updateFromLocalY(details.localPosition.dy, height),
            onVerticalDragStart: (details) =>
                _updateFromLocalY(details.localPosition.dy, height),
            onVerticalDragUpdate: (details) =>
                _updateFromLocalY(details.localPosition.dy, height),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: kStatusTextColorStops,
                    ),
                  ),
                ),
                Positioned(
                  top: (_barPosition * height - 9)
                      .clamp(0.0, math.max(height - 18, 0.0)),
                  left: -5,
                  right: -5,
                  child: IgnorePointer(
                    child: Container(
                      key: widget.thumbKey,
                      height: 18,
                      decoration: BoxDecoration(
                        color: widget.selectedColor,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The font-style row -- horizontally scrollable circular swatches, each
/// previewing a real font look, tapped directly rather than cycled one at a
/// time. Sits just above the keyboard while editing.
class StatusTextFontStyleRow extends StatelessWidget {
  const StatusTextFontStyleRow({
    required this.selectedFontId,
    required this.onFontSelected,
    required this.rowKey,
    required this.optionKeyBuilder,
    super.key,
  });

  final String selectedFontId;
  final ValueChanged<String> onFontSelected;
  final Key rowKey;
  final Key Function(String fontId) optionKeyBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: rowKey,
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: kTextStatusFontLooks.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final look = kTextStatusFontLooks[index];
          final isSelected = look.id == selectedFontId;
          final sample =
              look.uppercase ? look.sample.toUpperCase() : look.sample;
          return GestureDetector(
            key: optionKeyBuilder(look.id),
            onTap: () => onFontSelected(look.id),
            child: AnimatedContainer(
              duration: kStatusMotionFastDuration,
              curve: kStatusMotionCurve,
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? Colors.white
                    : Colors.black.withValues(alpha: 0.28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isSelected ? 0 : 0.16),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                sample,
                style: look.apply(
                  TextStyle(
                    fontSize: 18,
                    color: isSelected ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Cycles text alignment left -> centre -> right.
StatusTextAlignment nextStatusTextAlignment(StatusTextAlignment current) {
  return switch (current) {
    StatusTextAlignment.left => StatusTextAlignment.center,
    StatusTextAlignment.center => StatusTextAlignment.right,
    StatusTextAlignment.right => StatusTextAlignment.left,
  };
}

/// The icon that shows which alignment is currently active.
IconData statusTextAlignmentIcon(StatusTextAlignment alignment) {
  return switch (alignment) {
    StatusTextAlignment.left => Icons.format_align_left_rounded,
    StatusTextAlignment.center => Icons.format_align_center_rounded,
    StatusTextAlignment.right => Icons.format_align_right_rounded,
  };
}
