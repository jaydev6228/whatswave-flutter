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

/// The position along [kStatusTextColorStops] that best matches [color].
///
/// The rail's thumb is derived from the selected colour rather than kept
/// as independent state: when something else changed the colour (shuffle,
/// a preset), a thumb holding its own position sat on the old colour while
/// the text rendered the new one.
double statusTextBarPositionForColor(Color color) {
  const samples = 256;
  var bestT = 0.0;
  var bestDistance = double.infinity;
  for (var i = 0; i <= samples; i++) {
    final t = i / samples;
    final candidate = statusTextColorForBarPosition(t);
    final dr = candidate.r - color.r;
    final dg = candidate.g - color.g;
    final db = candidate.b - color.b;
    final distance = (dr * dr) + (dg * dg) + (db * db);
    if (distance < bestDistance) {
      bestDistance = distance;
      bestT = t;
    }
  }
  return bestT;
}

/// The editable text card itself: the text you type, rendered in the style
/// it will actually be posted in.
/// The height [text] needs when the face's own metrics decide the line
/// box, i.e. with any `height` multiplier from the font look removed.
///
/// Used as a floor for the editor card: a multiplier below the face's
/// natural ratio makes the line box shorter than the ink, and the card
/// clips whatever hangs out of it.
/// How far a single line's ink pokes out above and below the box the font
/// look's `height` multiplier gives it.
///
/// A multiplier under the face's natural ratio -- cinema is 0.92, impact
/// 0.94, poster 0.98 -- makes the line box shorter than the glyphs, and the
/// editor card clips whatever hangs out (a TextField scrolls its own
/// viewport), which sliced the tails off descenders.
///
/// ascent + descent is no help here: Flutter scales both to fill the
/// multiplied box, so their sum always equals it. The face's real extent
/// only shows up by laying the text out again with no multiplier at all.
///
/// Deliberately measured on ONE line rather than on the whole block. The
/// shortfall is per line box, but only the first line can overflow upwards
/// and only the last downwards -- comparing whole-block heights added the
/// gap once per line and left the surplus sitting under the text.
({double top, double bottom}) _inkOverflowFor({
  required BuildContext context,
  required TextStyle textStyle,
}) {
  final fontSize = textStyle.fontSize;
  if (fontSize == null || textStyle.height == null) {
    return (top: 0, bottom: 0);
  }
  // Rebuilt field by field rather than copyWith: there is no way to clear
  // `height` back to null through copyWith.
  final natural = TextStyle(
    fontFamily: textStyle.fontFamily,
    fontFamilyFallback: textStyle.fontFamilyFallback,
    fontSize: fontSize,
    fontWeight: textStyle.fontWeight,
    fontStyle: textStyle.fontStyle,
    letterSpacing: textStyle.letterSpacing,
    wordSpacing: textStyle.wordSpacing,
    textBaseline: textStyle.textBaseline,
    fontFeatures: textStyle.fontFeatures,
    fontVariations: textStyle.fontVariations,
  );
  // A cap plus descenders, so the probe sees the face's full vertical
  // extent whatever the user has actually typed.
  const probe = 'Ggjy';
  final textDirection = Directionality.of(context);
  final scaler = MediaQuery.textScalerOf(context);

  LineMetrics metricsFor(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: probe, style: style),
      maxLines: 1,
      textDirection: textDirection,
      textScaler: scaler,
    )..layout();
    final line = painter.computeLineMetrics().first;
    painter.dispose();
    return line;
  }

  final styled = metricsFor(textStyle);
  final unstyled = metricsFor(natural);
  return (
    top: math.max(0, unstyled.ascent - styled.ascent),
    bottom: math.max(0, unstyled.descent - styled.descent),
  );
}

class StatusTextEditorCard extends StatelessWidget {
  const StatusTextEditorCard({
    required this.controller,
    required this.focusNode,
    required this.textStyleModel,
    required this.fieldKey,
    this.hintText = 'Type something',
    this.cardKey,
    this.textStyle,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final StatusTextStyle textStyleModel;
  final Key fieldKey;
  final Key? cardKey;
  final String hintText;

  /// The style the text will actually be posted in.
  ///
  /// Each composer renders its result differently -- a media overlay uses a
  /// fixed base size, a text status scales with the canvas and the amount
  /// typed -- so the caller supplies its own posted style and the editor
  /// shows exactly that. Falling back to a single hardcoded size is what
  /// made typing look one size and the posted story another.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = resolveTextStatusFontLook(textStyleModel.fontId);
    final hasSolidBackground = textStyleModel.useSolidBackground ||
        textStyleModel.backgroundColor != null;
    // Transparent until the user asks for a plate (the fill button toggles
    // useSolidBackground). The editor is a preview of the posted text, and
    // a posted status has no card behind it unless one was chosen -- the
    // old always-on 22% wash was chrome the result never had.
    final surfaceColor = hasSolidBackground
        ? (textStyleModel.backgroundColor ?? Colors.black)
            .withValues(alpha: 0.62)
        : Colors.transparent;
    final resolvedStyle = this.textStyle ??
        look.apply(
          (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
            color: textStyleModel.textColor ?? Colors.white,
            fontSize: (24 *
                    textStyleModel.sizeScale.clamp(
                      kStatusTextMinSizeScale,
                      kStatusTextMaxSizeScale,
                    ))
                .clamp(kStatusTextMinFontSize, double.infinity),
            fontWeight: textStyleModel.fontWeight,
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
    // The user's weight wins over whatever the font look sets.
    final textStyle =
        resolvedStyle.copyWith(fontWeight: textStyleModel.fontWeight);

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
        final visibleLines =
            (availableHeight / lineHeight).floor().clamp(3, 40);

        const horizontalPadding = 12.0;
        const verticalPadding = 10.0;
        // Rebuilds as the text changes, so the card keeps hugging it while
        // typing even if the host screen does not itself rebuild.
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            // A TextField takes every pixel of width offered and has no
            // usable intrinsic width once maxLines > 1, so the card stayed
            // full-width for a single letter and swallowed taps meant for
            // the canvas around it. Measuring the text is what lets the
            // card actually hug it.
            final available = textBounds.width - (horizontalPadding * 2);
            // Floor so a single character still leaves a grabbable target
            // (docs/ui_layout_guidelines.md rule 7).
            final minInnerWidth =
                math.min(56.0 - (horizontalPadding * 2), available);
            final measured = TextPainter(
              text: TextSpan(
                text: controller.text.isEmpty ? hintText : controller.text,
                style: textStyle,
              ),
              maxLines: visibleLines,
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: available);
            // Re-layout at the width the field will actually get. The card
            // shrinks to hug the text, so measuring at the full available
            // width and then rendering into a narrower box let the text
            // re-wrap onto more lines than were measured -- the card came
            // out a line short and the field scrolled, slicing the top line
            // off. Measure and render must agree on the width.
            final innerWidth = math
                .min(measured.width + 1, available)
                .clamp(minInnerWidth, available);
            measured.layout(maxWidth: innerWidth);
            // A TextField with minLines/maxLines lays out at its *maxLines*
            // height here, not its content's, so the card was as tall as
            // the whole editing area for a single letter. Feeding it the
            // real line count makes it hug the text and still grow line by
            // line as you type, capped so it scrolls past the fold.
            final contentLines =
                measured.computeLineMetrics().length.clamp(1, visibleLines);
            final overflow = _inkOverflowFor(
              context: context,
              textStyle: textStyle,
            );
            final measuredHeight =
                measured.height + overflow.top + overflow.bottom;
            measured.dispose();

            return SizedBox(
              // Small enough that a one-character status leaves the rest of
              // the canvas tappable, but still a grabbable target for
              // re-entering editing (docs/ui_layout_guidelines.md rule 7).
              // The +1 absorbs the cursor, which sits just past the glyphs.
              width: innerWidth + (horizontalPadding * 2),
              // Height comes from the measurement too. Left to itself the
              // field filled the whole editing area regardless of
              // maxLines, so the card covered the canvas above and below
              // the text and ate taps meant to dismiss the keyboard.
              height: measuredHeight + (verticalPadding * 2),
              child: Container(
                key: cardKey,
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
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
                  maxLines: contentLines,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.newline,
                  textAlign: switch (textStyleModel.alignment) {
                    StatusTextAlignment.left => TextAlign.left,
                    StatusTextAlignment.center => TextAlign.center,
                    StatusTextAlignment.right => TextAlign.right,
                  },
                  style: textStyle,
                  cursorColor: textStyleModel.textColor ?? Colors.white,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    // The extra height goes above the first line and below
                    // the last, not all in one lump under the text.
                    contentPadding: EdgeInsets.only(
                      top: overflow.top,
                      bottom: overflow.bottom,
                    ),
                    filled: false,
                    // Every border spelled out, not just `border`: the app
                    // theme sets a focusedBorder, and InputDecoration.collapsed
                    // leaves that one alone -- which is where the green outline
                    // around the text while typing came from.
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    hintText: hintText,
                    // Wraps like real text; a single-line hint ran straight out
                    // past the card's edge at these sizes.
                    hintMaxLines: visibleLines,
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
  late double _barPosition =
      statusTextBarPositionForColor(widget.selectedColor);

  @override
  void didUpdateWidget(covariant StatusTextColorRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedColor == widget.selectedColor) {
      return;
    }
    // Only re-derive when the colour changed from *outside* -- during a
    // drag the colour we just reported back would otherwise snap the thumb
    // to the nearest sampled stop and make the gesture judder.
    final ownColor = statusTextColorForBarPosition(_barPosition);
    if (ownColor == widget.selectedColor) {
      return;
    }
    setState(() {
      _barPosition = statusTextBarPositionForColor(widget.selectedColor);
    });
  }

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

/// The size/weight controls, shared by both composers.
///
/// Size is a slider rather than a pinch-only gesture so it is discoverable
/// and reachable one-handed; weight is a tap-to-cycle button showing the
/// weight it will apply next, so it costs a single control slot.
class StatusTextSizeWeightControls extends StatelessWidget {
  const StatusTextSizeWeightControls({
    required this.style,
    required this.onSizeChanged,
    required this.onWeightChanged,
    required this.sliderKey,
    required this.weightButtonKey,
    this.minScale = kStatusTextMinSizeScale,
    this.maxScale = kStatusTextMaxSizeScale,
    super.key,
  });

  final StatusTextStyle style;
  final ValueChanged<double> onSizeChanged;
  final ValueChanged<int> onWeightChanged;
  final Key sliderKey;
  final Key weightButtonKey;
  final double minScale;
  final double maxScale;

  @override
  Widget build(BuildContext context) {
    final nextWeightIndex =
        (style.fontWeightIndex + 1) % kStatusTextFontWeights.length;
    return Row(
      children: [
        const Icon(Icons.text_fields_rounded, color: Colors.white70, size: 18),
        // The slider takes the slack, so the row fits any width and text
        // scale (docs/ui_layout_guidelines.md rule 6).
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.28),
              thumbColor: Colors.white,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              key: sliderKey,
              min: minScale,
              max: maxScale,
              value: style.sizeScale.clamp(minScale, maxScale),
              onChanged: onSizeChanged,
            ),
          ),
        ),
        // Shows the weight it is currently set to, drawn at that weight --
        // an abstract "B" would say nothing about which of four it is on.
        GestureDetector(
          key: weightButtonKey,
          behavior: HitTestBehavior.opaque,
          onTap: () => onWeightChanged(nextWeightIndex),
          child: Container(
            // Platform minimum tap target (rule 7), even though the glyph
            // inside is small.
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            alignment: Alignment.center,
            child: Text(
              'Aa',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: style.fontWeight,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
