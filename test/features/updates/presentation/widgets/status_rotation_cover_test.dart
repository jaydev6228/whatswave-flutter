import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_story_media_surface.dart';

void main() {
  group('statusRotationCoverScale', () {
    test('an untilted frame needs no magnification', () {
      expect(statusRotationCoverScale(300, 400, 0), 1);
    });

    test('a tilt magnifies enough to keep the corners covered', () {
      const width = 300.0;
      const height = 400.0;
      const degrees = 12.0;
      final scale = statusRotationCoverScale(width, height, degrees);
      expect(scale, greaterThan(1));

      // Check it directly: the frame's own corners, rotated back into the
      // magnified media's frame of reference, must still land inside it.
      final radians = degrees * math.pi / 180;
      final cos = math.cos(radians);
      final sin = math.sin(radians);
      for (final corner in <List<double>>[
        <double>[-width / 2, -height / 2],
        <double>[width / 2, -height / 2],
        <double>[-width / 2, height / 2],
        <double>[width / 2, height / 2],
      ]) {
        final x = corner[0] * cos + corner[1] * sin;
        final y = -corner[0] * sin + corner[1] * cos;
        expect(x.abs(), lessThanOrEqualTo(width / 2 * scale + 0.001));
        expect(y.abs(), lessThanOrEqualTo(height / 2 * scale + 0.001));
      }
    });

    test('the direction of the tilt does not matter', () {
      expect(
        statusRotationCoverScale(300, 400, -8),
        closeTo(statusRotationCoverScale(300, 400, 8), 0.0001),
      );
    });
  });
}
