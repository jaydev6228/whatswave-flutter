import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/presentation/media_status_composer_screen.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_story_media_surface.dart';

void main() {
  const cropTool = Key('updates_media_crop_rotate_button');

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

  Future<void> pinchOut(WidgetTester tester) async {
    final centre = tester.getCenter(find.byType(MediaStatusComposerScreen));
    final a = await tester.startGesture(centre - const Offset(20, 0));
    final b = await tester.startGesture(centre + const Offset(20, 0));
    await a.moveTo(centre - const Offset(100, 0));
    await b.moveTo(centre + const Offset(100, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  }

  testWidgets(
      'dragging moves the media, so the selection travels the other '
      'way', (tester) async {
    await openCropTool(tester);
    // Zoom in first: an untouched window already encloses the whole media,
    // so there is nowhere for it to slide to.
    await pinchOut(tester);
    final before = transform(tester);

    // Drag right. The media follows the finger, which means the window over
    // it slides left -- the tool used to drag the window itself, so the
    // picture stood still and the selection chased the finger.
    await tester.drag(
      find.byType(MediaStatusComposerScreen),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();

    expect(transform(tester).offsetDx, greaterThan(before.offsetDx));
  });

  testWidgets('pinching zooms the media, tightening the selection',
      (tester) async {
    await openCropTool(tester);
    final before = transform(tester);

    await pinchOut(tester);

    // A bigger media under the same frame means less of it is enclosed.
    expect(transform(tester).scale, greaterThan(before.scale));
  });

  testWidgets('the crop frame stays put while the media moves', (tester) async {
    await openCropTool(tester);

    final canvas = tester.getSize(find.byType(MediaStatusComposerScreen));
    final ratio = transform(tester).frameAspectRatio;
    final frameBefore = statusCropFrameRectFor(canvas, ratio);

    await tester.drag(
      find.byType(MediaStatusComposerScreen),
      const Offset(40, 30),
    );
    await tester.pumpAndSettle();

    // The frame is fixed by construction -- it depends only on the canvas
    // and the chosen ratio, never on where the media has been dragged to.
    expect(
      statusCropFrameRectFor(canvas, transform(tester).frameAspectRatio),
      frameBefore,
    );
  });

  testWidgets('resizing from a corner holds the media still', (tester) async {
    await openCropTool(tester);

    // A corner drag tightens the selection, and with a fixed frame that
    // would otherwise magnify the picture under the finger. The media is
    // frozen for the duration instead: the rect shrinks over a still
    // picture, and only re-fits once the finger lifts.
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const Key('updates_media_crop_corner_bottomRight')),
      ),
    );
    await tester.pump();

    await gesture.moveBy(const Offset(-80, -70));
    await tester.pump();

    // Mid-drag the surface is handed the frozen anchor, which is what pins
    // the media.
    final surface = tester
        .widgetList<StatusStoryMediaSurface>(
            find.byType(StatusStoryMediaSurface))
        .first;
    expect(surface.cropResizeAnchorWindow, isNotNull);

    await gesture.up();
    await tester.pumpAndSettle();

    // Released, the freeze lifts and the new selection re-fits the frame.
    final settled = tester
        .widgetList<StatusStoryMediaSurface>(
            find.byType(StatusStoryMediaSurface))
        .first;
    expect(
      settled.cropResizeAnchorWindow,
      isNull,
      reason: 'the media stayed frozen after the drag ended',
    );
  });

  testWidgets('the re-fit after a resize is travelled, not jumped',
      (tester) async {
    await openCropTool(tester);

    Rect? anchor() => tester
        .widgetList<StatusStoryMediaSurface>(
            find.byType(StatusStoryMediaSurface))
        .first
        .cropResizeAnchorWindow;

    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const Key('updates_media_crop_corner_bottomRight')),
      ),
    );
    await tester.pump();
    // In steps: the first movement is swallowed by touch slop, so a single
    // hop registers the grab without ever resizing anything.
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(-30, -28));
      await tester.pump();
    }
    final frozen = anchor();
    expect(frozen, isNotNull);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Part-way through: the media is still being carried back to the frame,
    // from where the drag froze it. It used to arrive in a single frame.
    final settling = anchor();
    expect(settling, isNotNull, reason: 'the re-fit was instant');
    expect(settling, isNot(frozen), reason: 'the re-fit never started');

    await tester.pumpAndSettle();
    expect(anchor(), isNull, reason: 'the re-fit never finished');
  });

  testWidgets('entering and leaving the crop tool are travelled, not swapped',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    double inset() => tester
        .widgetList<StatusStoryMediaSurface>(
            find.byType(StatusStoryMediaSurface))
        .first
        .cropInsetFactor;

    await tester.tap(find.byKey(cropTool));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Part-way in: the frame is on its way to the tool's inset framing.
    final entering = inset();
    expect(entering, greaterThan(0));
    expect(entering, lessThan(1));

    await tester.pumpAndSettle();
    expect(inset(), 1);

    // And Done carries it back rather than dropping it in one frame.
    await tester.tap(find.byKey(const Key('updates_media_crop_done_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final leaving = inset();
    expect(leaving, lessThan(1));
    expect(leaving, greaterThan(0));

    await tester.pumpAndSettle();
  });

  testWidgets('the two framings cross-fade rather than swapping',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    int framings() => find.byType(StatusStoryMediaSurface).evaluate().length;

    // Crop mode and the preview do not render the media the same way -- the
    // geometries disagree by a fixed amount, so swapping between them in one
    // frame is a visible jump. Both are drawn and faded across instead.
    expect(framings(), 1, reason: 'the preview should draw one framing');

    await tester.tap(find.byKey(cropTool));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      framings(),
      2,
      reason: 'mid-transition both framings should be on screen',
    );

    await tester.pumpAndSettle();
    expect(
      framings(),
      1,
      reason: 'the media must not stay drawn twice once settled',
    );
  });
}
