import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/layout/models/layout_models.dart';

void main() {
  test('preview cache width matches slot pixels, not slot count', () {
    expect(kLayoutPreviewMaxPixelSize, 1440);
    expect(
      layoutPreviewCacheWidth(
        slotSize: const Size(80, 80),
        devicePixelRatio: 2,
      ),
      360,
    );
    expect(
      layoutPreviewCacheWidth(
        slotSize: const Size(180, 400),
        devicePixelRatio: 3,
        imageSize: const Size(4000, 3000),
      ),
      1440,
    );
    expect(
      layoutPreviewCacheWidth(
        slotSize: const Size(180, 400),
        devicePixelRatio: 3,
        imageSize: const Size(3000, 4000),
      ),
      900,
    );
  });
}
