import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/presentation/media_status_composer_screen.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_story_media_surface.dart';

void main() {
  const cropTool = Key('updates_media_crop_rotate_button');
  const dial = Key('updates_media_rotation_dial');
  const reset = Key('updates_media_crop_reset_button');

  Future<void> openCropTool(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(cropTool));
    await tester.pumpAndSettle();
  }

  StatusMediaTransform transform(WidgetTester tester) => tester
      .widgetList<StatusStoryMediaSurface>(find.byType(StatusStoryMediaSurface))
      .first
      .mediaTransform;

  testWidgets('the dial belongs to the crop tool', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(dial), findsNothing);

    await tester.tap(find.byKey(cropTool));
    await tester.pumpAndSettle();
    expect(find.byKey(dial), findsOneWidget);
  });

  testWidgets('dragging the dial straightens the media', (tester) async {
    await openCropTool(tester);
    expect(transform(tester).rotationDegrees, 0);

    // Left drags clockwise, the way turning a wheel away from you does.
    await tester.drag(find.byKey(dial), const Offset(-90, 0));
    await tester.pumpAndSettle();

    expect(transform(tester).rotationDegrees, greaterThan(0));
  });

  testWidgets('the dial settles on level rather than a fraction of a degree',
      (tester) async {
    await openCropTool(tester);

    // Just off centre: an unstraightened photo should not sit at 0.4
    // degrees because a finger lifted a fraction early.
    await tester.drag(find.byKey(dial), const Offset(-3, 0));
    await tester.pumpAndSettle();

    expect(transform(tester).rotationDegrees, 0);
  });

  testWidgets('straightening alone offers Reset, and Reset levels it',
      (tester) async {
    await openCropTool(tester);
    expect(find.byKey(reset), findsNothing);

    await tester.drag(find.byKey(dial), const Offset(-90, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(reset), findsOneWidget);

    await tester.tap(find.byKey(reset));
    await tester.pumpAndSettle();
    expect(transform(tester).rotationDegrees, 0);
  });
}
