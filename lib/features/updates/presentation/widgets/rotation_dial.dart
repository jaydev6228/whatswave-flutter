import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The straightening dial under the crop tool: a ruler of degree ticks that
/// slides under a fixed centre marker.
///
/// Reads as a physical wheel -- you drag the scale, not a handle along a
/// track -- which is what makes fine one-degree corrections feel controlled.
/// Snaps to zero within a degree so level is always reachable by feel, and
/// ticks the haptics as it passes each labelled mark.
class RotationDial extends StatefulWidget {
  const RotationDial({
    required this.degrees,
    required this.onChanged,
    this.onChangeEnd,
    this.maxDegrees = 45,
    super.key,
  });

  final double degrees;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeEnd;
  final double maxDegrees;

  @override
  State<RotationDial> createState() => _RotationDialState();
}

class _RotationDialState extends State<RotationDial> {
  /// Points of drag per degree. Loose enough that a whole-thumb sweep covers
  /// the range, tight enough that a single degree is still selectable.
  static const double _pointsPerDegree = 6;

  /// Within this of level, the dial settles on exactly zero -- an
  /// unstraightened photo should not sit at 0.4 degrees because a finger
  /// lifted a fraction early.
  static const double _snapToZeroWithin = 1;

  double _lastHapticMark = 0;

  void _handleDragUpdate(DragUpdateDetails details) {
    // Dragging left rotates clockwise, the way turning a physical wheel
    // away from you does.
    final next = (widget.degrees - details.delta.dx / _pointsPerDegree)
        .clamp(-widget.maxDegrees, widget.maxDegrees)
        .toDouble();
    final settled = next.abs() < _snapToZeroWithin ? 0.0 : next;

    final mark = (settled / 5).roundToDouble();
    if (mark != _lastHapticMark) {
      _lastHapticMark = mark;
      unawaited(HapticFeedback.selectionClick());
    }
    widget.onChanged(settled);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: (_) => widget.onChangeEnd?.call(),
      // Tap the dial to level the picture again.
      onDoubleTap: () {
        widget.onChanged(0);
        widget.onChangeEnd?.call();
      },
      child: SizedBox(
        height: 78,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Above the arc, not below it: underneath, the reading collided
            // with the Reset button sitting on the next row down.
            Text(
              widget.degrees == 0
                  ? '0°'
                  : '${widget.degrees > 0 ? '+' : ''}'
                      '${widget.degrees.toStringAsFixed(0)}°',
              style: TextStyle(
                color: widget.degrees == 0
                    ? Colors.white.withValues(alpha: 0.7)
                    : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: CustomPaint(
                size: Size.infinite,
                painter: _RotationDialPainter(
                  degrees: widget.degrees,
                  maxDegrees: widget.maxDegrees,
                  pointsPerDegree: _pointsPerDegree,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RotationDialPainter extends CustomPainter {
  const _RotationDialPainter({
    required this.degrees,
    required this.maxDegrees,
    required this.pointsPerDegree,
  });

  final double degrees;
  final double maxDegrees;
  final double pointsPerDegree;

  @override
  void paint(Canvas canvas, Size size) {
    // A shallow arc, read like a protractor laid under the picture: the
    // ticks belong to a wheel whose centre sits well below the screen, so
    // they curve away at the edges instead of running off flat. Radius is
    // tied to the width so the curve looks the same on any device.
    final radius = size.width * 1.15;
    final centre = Offset(size.width / 2, radius + 8);
    final radiansPerDegree = pointsPerDegree / radius;

    final tick = Paint()..strokeCap = StrokeCap.round;

    for (var value = -maxDegrees; value <= maxDegrees; value++) {
      final angle = (value - degrees) * radiansPerDegree;
      // Past a quarter turn the tick would be behind the wheel.
      if (angle.abs() > math.pi / 3) {
        continue;
      }
      final direction = Offset(math.sin(angle), -math.cos(angle));
      final outer = centre + direction * radius;
      if (outer.dx < -10 || outer.dx > size.width + 10) {
        continue;
      }

      final isMajor = value % 5 == 0;
      // Faded towards the edges so the strip reads as a wheel turning away
      // rather than a bar that simply stops.
      final fade = (1 - ((outer.dx - centre.dx).abs() / (size.width / 2)))
          .clamp(0.0, 1.0);
      tick
        ..strokeWidth = isMajor ? 2 : 1.2
        ..color = Colors.white.withValues(alpha: (isMajor ? 0.95 : 0.4) * fade);
      final length = isMajor ? 15.0 : 8.0;
      canvas.drawLine(outer, centre + direction * (radius - length), tick);
    }

    // The fixed pointer. The picture is level when a tick sits under it, so
    // it is the one thing here that never moves. Drawn as a caret above the
    // arc rather than another bar on it -- as a bar it was just a slightly
    // brighter tick, and the eye had nothing to lock onto. Turns green off
    // level, which is the only cue needed while looking at the photo.
    final colour = degrees == 0 ? Colors.white : const Color(0xFF25D366);
    final apexY = centre.dy - radius;
    final caret = Path()
      ..moveTo(centre.dx, apexY + 1)
      ..lineTo(centre.dx - 5, apexY - 7)
      ..lineTo(centre.dx + 5, apexY - 7)
      ..close();
    canvas.drawPath(caret, Paint()..color = colour);
    canvas.drawLine(
      Offset(centre.dx, apexY + 1),
      Offset(centre.dx, apexY + 17),
      Paint()
        ..color = colour
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RotationDialPainter oldDelegate) =>
      oldDelegate.degrees != degrees ||
      oldDelegate.maxDegrees != maxDegrees ||
      oldDelegate.pointsPerDegree != pointsPerDegree;
}
