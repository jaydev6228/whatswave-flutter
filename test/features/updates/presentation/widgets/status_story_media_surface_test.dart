import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_story_media_surface.dart';

Future<void> _pumpUntilRealImageDecodes(WidgetTester tester) async {
  // Real asset decoding runs on a genuine async codec call that fake-async
  // `pump`/`pumpAndSettle` alone never resolves -- the whole pump sequence
  // needs to run inside `runAsync` so that real Future actually completes
  // before the widget rebuilds with the decoded size.
  await tester.runAsync(() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'rotating a photo lays out the real media at its true unrotated size '
      '-- not the swapped frame size -- so it does not get over-cropped',
      (tester) async {
    // A real, decodable 1080x1920 (portrait) JPEG already bundled as a
    // pubspec asset -- lets this test exercise genuine image decoding
    // instead of the missing-file fallback most composer tests use.
    const sourceSize = Size(1080, 1920);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: StatusStoryMediaSurface(
              type: StatusStoryType.photo,
              localMediaPath: 'asset://assets/media/status_demo/launch_cafe.jpg',
              mediaTransform: StatusMediaTransform(
                rotationQuarterTurns: 1,
                frameAspectRatio: sourceSize.height / sourceSize.width,
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilRealImageDecodes(tester);

    final renderedSize = tester.getSize(
      find.byKey(const Key('updates_story_media_photo')),
    );

    expect(renderedSize.width, closeTo(sourceSize.width, 0.5));
    expect(renderedSize.height, closeTo(sourceSize.height, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unrotated photo still lays out at its true size',
      (tester) async {
    const sourceSize = Size(1080, 1920);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: StatusStoryMediaSurface(
              type: StatusStoryType.photo,
              localMediaPath: 'asset://assets/media/status_demo/launch_cafe.jpg',
              mediaTransform: StatusMediaTransform(
                frameAspectRatio: sourceSize.width / sourceSize.height,
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilRealImageDecodes(tester);

    final renderedSize = tester.getSize(
      find.byKey(const Key('updates_story_media_photo')),
    );

    expect(renderedSize.width, closeTo(sourceSize.width, 0.5));
    expect(renderedSize.height, closeTo(sourceSize.height, 0.5));
  });

  testWidgets(
      'drawing strokes render as a painted layer on top of the media -- '
      'shared by composer, viewer, and thumbnails alike', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: StatusStoryMediaSurface(
              type: StatusStoryType.photo,
              localMediaPath: 'asset://assets/media/status_demo/launch_cafe.jpg',
              drawingStrokes: const <StatusDrawingStroke>[
                StatusDrawingStroke(
                  points: <Offset>[Offset(0.1, 0.1), Offset(0.9, 0.9)],
                  colorValue: 0xFFFF0000,
                  strokeWidth: 0.02,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await _pumpUntilRealImageDecodes(tester);

    expect(find.byKey(const Key('updates_story_drawing_layer')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no drawing layer is painted when there are no strokes',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: StatusStoryMediaSurface(
              type: StatusStoryType.photo,
              localMediaPath: 'asset://assets/media/status_demo/launch_cafe.jpg',
            ),
          ),
        ),
      ),
    );
    await _pumpUntilRealImageDecodes(tester);

    expect(find.byKey(const Key('updates_story_drawing_layer')), findsNothing);
  });
}
