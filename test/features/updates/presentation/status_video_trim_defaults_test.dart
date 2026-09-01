import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/presentation/media_status_composer_screen.dart';

void main() {
  group('statusVideoSeconds', () {
    test('keeps sub-second precision instead of truncating', () {
      // The regression this file exists for: `Duration.inSeconds` would
      // report 5 here, and the editor opened with a 5.0s trim over a 5.8s
      // clip -- a visibly unselected tail in the filmstrip.
      expect(statusVideoSeconds(const Duration(milliseconds: 5800)), 5.8);
    });

    test('treats a null controller duration as zero', () {
      expect(statusVideoSeconds(null), 0);
    });
  });

  group('statusVideoDefaultTrimSeconds', () {
    test('selects the whole clip, tail included', () {
      expect(
        statusVideoDefaultTrimSeconds(
          const Duration(milliseconds: 5800),
          minSeconds: 3,
        ),
        5.8,
      );
    });

    test('caps at the 30s status limit for a long clip', () {
      expect(
        statusVideoDefaultTrimSeconds(
          const Duration(seconds: 62),
          minSeconds: 3,
        ),
        30,
      );
    });

    test('reaches the true end of a clip just over a whole second', () {
      // 20.7s truncates to 20, which used to become the max as well, so the
      // last 0.7s was unreachable even by dragging.
      const duration = Duration(milliseconds: 20700);
      expect(statusVideoMaxTrimSeconds(duration), 20.7);
      expect(
        statusVideoDefaultTrimSeconds(duration, minSeconds: 3),
        20.7,
      );
    });

    test('floors a very short clip at the minimum trim length', () {
      expect(
        statusVideoDefaultTrimSeconds(
          const Duration(milliseconds: 1200),
          minSeconds: 3,
        ),
        3,
      );
    });
  });
}
