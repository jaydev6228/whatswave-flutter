import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/presentation/media_status_composer_screen.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_story_media_surface.dart';

void main() {
  Future<void> pumpComposer(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  StatusMediaTransform transform(WidgetTester tester) {
    return tester
        .widgetList<StatusStoryMediaSurface>(
          find.byType(StatusStoryMediaSurface),
        )
        .first
        .mediaTransform;
  }

  testWidgets('the preview zooms but never shifts the media', (tester) async {
    await pumpComposer(tester);
    final before = transform(tester);

    // A pinch whose two fingers also drift sideways: the scale must take,
    // the translation must not. Framing belongs to the crop tool -- a stray
    // drag here would leave the preview showing something other than what
    // was cropped.
    final centre = tester.getCenter(find.byType(MediaStatusComposerScreen));
    final gestureA = await tester.startGesture(centre - const Offset(20, 0));
    final gestureB = await tester.startGesture(centre + const Offset(20, 0));
    await gestureA.moveTo(centre - const Offset(90, 40));
    await gestureB.moveTo(centre + const Offset(90, 40));
    await tester.pump();
    await gestureA.up();
    await gestureB.up();
    await tester.pumpAndSettle();

    final after = transform(tester);
    expect(after.scale, greaterThan(before.scale));
    expect(after.offsetDx, before.offsetDx);
    expect(after.offsetDy, before.offsetDy);
  });
}
