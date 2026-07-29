import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/widgets/avatar_badge.dart';

class StatusRingAvatar extends StatelessWidget {
  const StatusRingAvatar({
    required this.label,
    required this.color,
    required this.totalSegments,
    required this.seenSegments,
    this.size = 72,
    super.key,
  });

  final String label;
  final Color color;
  final int totalSegments;
  final int seenSegments;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarInset = (size * 0.176).clamp(9, 13.25).toDouble();

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SegmentedStoryRingPainter(
          activeColor: color,
          inactiveColor: theme.colorScheme.onSurface.withValues(alpha: 0.18),
          totalSegments: totalSegments,
          seenSegments: seenSegments,
        ),
        child: Padding(
          padding: EdgeInsets.all(avatarInset),
          child: AvatarBadge(
            label: label,
            color: color,
            size: size - (avatarInset * 2),
          ),
        ),
      ),
    );
  }
}

class _SegmentedStoryRingPainter extends CustomPainter {
  const _SegmentedStoryRingPainter({
    required this.activeColor,
    required this.inactiveColor,
    required this.totalSegments,
    required this.seenSegments,
  });

  final Color activeColor;
  final Color inactiveColor;
  final int totalSegments;
  final int seenSegments;

  @override
  void paint(Canvas canvas, Size size) {
    final segmentCount = totalSegments <= 0 ? 1 : totalSegments.clamp(1, 12);
    final center = size.center(Offset.zero);
    final strokeWidth = size.shortestSide * 0.057;
    final radius = (size.shortestSide / 2) - (strokeWidth / 2) - 1;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gapRadians = segmentCount == 1 ? 0 : 0.14;
    final sweep = ((math.pi * 2) - (gapRadians * segmentCount)) / segmentCount;

    for (var index = 0; index < segmentCount; index++) {
      final isSeen = totalSegments > 0 && index < seenSegments;
      final paint = Paint()
        ..color = isSeen ? inactiveColor : activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      final startAngle =
          -math.pi / 2 + (index * (sweep + gapRadians)) + (gapRadians / 2);
      canvas.drawArc(rect, startAngle, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedStoryRingPainter oldDelegate) {
    return oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.totalSegments != totalSegments ||
        oldDelegate.seenSegments != seenSegments;
  }
}
