import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/layout/models/layout_models.dart';

void main() {
  test('preview cache width shrinks as more slots fill', () {
    expect(kLayoutPreviewMaxPixelSize, 720);
    expect(layoutPreviewCacheWidth(1), 720);
    expect(layoutPreviewCacheWidth(4), lessThanOrEqualTo(360));
    expect(layoutPreviewCacheWidth(6), lessThanOrEqualTo(294));
    expect(layoutPreviewCacheWidth(99), greaterThanOrEqualTo(240));
  });
}
