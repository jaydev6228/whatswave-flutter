import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'status_chrome.dart';

/// The draw tool's controls, shared by the status composer and the chat
/// media send preview.
///
/// The chat preview shipped its own markup tray -- a flat black bar with
/// six plain circles, no stroke width and no eraser -- which read as a
/// different app from the composer's, and was missing half the tool.
///
/// [keyPrefix] names the screen's own keys ('updates_media_draw',
/// 'media_send_preview_markup'): both screens' widget tests find these
/// controls by key, so the two cannot share one set.
class DrawColorRail extends StatefulWidget {
  const DrawColorRail({
    required this.keyPrefix,
    required this.selectedColor,
    required this.isEraserMode,
    required this.onSelectColor,
    super.key,
  });

  final String keyPrefix;
  final Color selectedColor;
  final bool isEraserMode;
  final ValueChanged<Color> onSelectColor;

  @override
  State<DrawColorRail> createState() => _DrawColorRailState();
}

class _DrawColorRailState extends State<DrawColorRail> {
  late double _barPosition = _positionForDrawBarColor(widget.selectedColor);
  bool _isDragging = false;

  @override
  void didUpdateWidget(covariant DrawColorRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The thumb follows the colour, rather than remembering where it was
    // last dragged to. Its position used to be independent state starting
    // at the top, so anything that rebuilt this widget with a colour
    // already chosen -- paging to the next photo, leaving and re-entering
    // draw mode -- left the thumb sitting on white while the pen drew
    // green. Skipped mid-drag, where the finger is the source of truth and
    // re-deriving would fight it over rounding.
    if (!_isDragging && widget.selectedColor != oldWidget.selectedColor) {
      _barPosition = _positionForDrawBarColor(widget.selectedColor);
    }
  }

  void _updateFromLocalY(double localY, double height) {
    if (height <= 0) {
      return;
    }
    final position = (localY / height).clamp(0.0, 1.0);
    setState(() => _barPosition = position);
    widget.onSelectColor(_colorForDrawBarPosition(position));
  }

  void _endDrag() {
    if (_isDragging) {
      setState(() => _isDragging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      child: StatusChromeSurface(
        key: Key('${widget.keyPrefix}_editing_tray'),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            return GestureDetector(
              key: Key('${widget.keyPrefix}_color_bar'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _updateFromLocalY(details.localPosition.dy, height),
              onVerticalDragStart: (details) {
                setState(() => _isDragging = true);
                _updateFromLocalY(details.localPosition.dy, height);
              },
              onVerticalDragUpdate: (details) =>
                  _updateFromLocalY(details.localPosition.dy, height),
              onVerticalDragEnd: (_) => _endDrag(),
              onVerticalDragCancel: _endDrag,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _kDrawColorBarStops,
                      ),
                    ),
                  ),
                  // While the finger is down, a swatch big enough to
                  // actually read floats clear of the rail -- under a
                  // fingertip the thumb itself is covered by the hand
                  // choosing it.
                  if (_isDragging && !widget.isEraserMode)
                    Positioned(
                      top: (_barPosition * height - 22)
                          .clamp(0.0, math.max(height - 44, 0.0)),
                      right: 34,
                      child: IgnorePointer(
                        child: Container(
                          key: Key('${widget.keyPrefix}_color_preview'),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: widget.selectedColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(color: Colors.black38, blurRadius: 6),
                            ],
                          ),
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
                        key: Key('${widget.keyPrefix}_color_thumb'),
                        height: 18,
                        decoration: BoxDecoration(
                          color: widget.isEraserMode
                              ? Colors.transparent
                              : widget.selectedColor,
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
      ),
    );
  }
}

const List<Color> _kDrawColorBarStops = [
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

/// Where on the bar a colour sits -- the inverse of
/// [_colorForDrawBarPosition].
///
/// Sampled rather than solved: the bar is a piecewise lerp through nine
/// stops, so inverting it analytically means per-segment case work for a
/// value only ever used to place an 18pt thumb.
double _positionForDrawBarColor(Color color) {
  const samples = 240;
  var bestPosition = 0.0;
  var bestDistance = double.infinity;
  for (var index = 0; index <= samples; index++) {
    final position = index / samples;
    final candidate = _colorForDrawBarPosition(position);
    final dr = candidate.r - color.r;
    final dg = candidate.g - color.g;
    final db = candidate.b - color.b;
    final distance = dr * dr + dg * dg + db * db;
    if (distance < bestDistance) {
      bestDistance = distance;
      bestPosition = position;
    }
  }
  return bestPosition;
}

Color _colorForDrawBarPosition(double t) {
  final stops = _kDrawColorBarStops;
  final segmentCount = stops.length - 1;
  final scaled = t.clamp(0.0, 1.0) * segmentCount;
  final index = scaled.floor().clamp(0, segmentCount - 1);
  final localT = scaled - index;
  return Color.lerp(stops[index], stops[index + 1], localT)!;
}

/// The pen/eraser toggle and the stroke sizes, in one chrome capsule -- the
/// pill that pairs with [DrawColorRail]. See there for [keyPrefix].
class DrawStrokeTray extends StatelessWidget {
  const DrawStrokeTray({
    required this.keyPrefix,
    required this.color,
    required this.isEraserMode,
    required this.onToggleEraser,
    required this.selectedStrokeIndex,
    required this.onSelectStroke,
    super.key,
  });

  /// How many widths the tray offers. Each screen keeps its own list of
  /// that many and is handed the index -- the composer's are fractions of
  /// the media frame's shortest side, the chat preview's plain pixels.
  static const int strokeCount = 3;

  final String keyPrefix;

  /// The pen's current color, so a size dot previews the real stroke.
  final Color color;

  final bool isEraserMode;
  final VoidCallback onToggleEraser;
  final int selectedStrokeIndex;
  final ValueChanged<int> onSelectStroke;

  @override
  Widget build(BuildContext context) {
    return StatusChromeButtonGroup(
      children: [
        DecoratedBox(
          // The chrome button has no selected state of its own, and the
          // eraser needs one -- otherwise there is nothing on screen
          // saying which of pen/eraser you are holding.
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isEraserMode ? Colors.white.withValues(alpha: 0.18) : null,
          ),
          child: StatusChromeButton(
            key: Key('${keyPrefix}_eraser_button'),
            tooltip: isEraserMode ? 'Pen' : 'Eraser',
            icon: isEraserMode ? Icons.edit_rounded : Icons.auto_fix_off_rounded,
            onTap: onToggleEraser,
            bare: true,
          ),
        ),
        for (var i = 0; i < strokeCount; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _StrokeSizeButton(
              key: Key('${keyPrefix}_stroke_$i'),
              dotDiameter: (isEraserMode ? 10.0 : 6.0) + i * 4.0,
              color: isEraserMode ? Colors.white : color,
              selected: selectedStrokeIndex == i,
              onTap: () => onSelectStroke(i),
            ),
          ),
      ],
    );
  }
}

/// A stroke-width option shown as an actual dot at that size, in the pen's
/// current color -- shows you what the stroke will really look like,
/// instead of an abstract "S/M/L" label.
class _StrokeSizeButton extends StatelessWidget {
  const _StrokeSizeButton({
    required this.dotDiameter,
    required this.color,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final double dotDiameter;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? Colors.white.withValues(alpha: 0.18) : null,
        ),
        child: Center(
          child: Container(
            width: dotDiameter,
            height: dotDiameter,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: color == Colors.white
                  ? Border.all(color: Colors.black26)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
