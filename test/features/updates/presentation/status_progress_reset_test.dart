import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/presentation/status_story_viewer_screen.dart';

void main() {
  // Two text segments: nothing to decode or stream, so any stale progress on
  // screen is the bar's own bug rather than media still loading.
  const story = StatusStory(
    id: 'ava-story',
    name: 'Ava',
    avatarLabel: 'AP',
    previewText: 'first',
    timeLabel: '15m ago',
    accentColor: AppPalette.green,
    type: StatusStoryType.text,
    totalSegments: 2,
    seenSegments: 0,
    segments: <StatusStorySegment>[
      StatusStorySegment(
        id: 'seg-1',
        type: StatusStoryType.text,
        previewText: 'first',
        textStyle: StatusTextStyle(fontId: 'clean'),
      ),
      // Deliberately a *remote video*. A text segment restarts its bar
      // synchronously and so never had this bug; the gap only opens when
      // the restart waits on a platform channel -- disposing a controller,
      // probing the media cache, initializing a player.
      StatusStorySegment(
        id: 'seg-2',
        type: StatusStoryType.video,
        previewText: 'second',
        localMediaPath: 'https://storage.example.com/clip.mp4',
      ),
    ],
  );

  Future<void> pumpViewer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StatusStoryViewerScreen(
          story: story,
          onStoryViewed: (_) {},
          segmentDurationOverride: const Duration(seconds: 10),
        ),
      ),
    );
    await tester.pump();
  }

  double fillWidth(WidgetTester tester, int index) {
    return tester
        .getSize(find.byKey(Key('updates_story_progress_fill_$index')))
        .width;
  }

  testWidgets('the next segment\'s bar never flashes the previous value',
      (tester) async {
    await pumpViewer(tester);

    // Let segment 1 get a visible way along.
    await tester.pump(const Duration(seconds: 3));
    expect(fillWidth(tester, 0), greaterThan(0));

    // Tap the right-hand side to advance, then look at the very first frame
    // the new segment gets. The bug: restarting the bar happens after an
    // async gap, so this frame painted segment 2 at segment 1's progress --
    // part-way here, completely full when a segment ends on its own.
    final size = tester.getSize(find.byType(StatusStoryViewerScreen));
    await tester.tapAt(Offset(size.width * 0.85, size.height * 0.5));
    await tester.pump();

    expect(fillWidth(tester, 1), 0);

    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  });

  testWidgets('going back does not leave the earlier bar part-filled',
      (tester) async {
    await pumpViewer(tester);

    final size = tester.getSize(find.byType(StatusStoryViewerScreen));
    await tester.tapAt(Offset(size.width * 0.85, size.height * 0.5));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    // Back to the first segment: its bar restarts from zero too.
    await tester.tapAt(Offset(size.width * 0.1, size.height * 0.5));
    await tester.pump();

    expect(fillWidth(tester, 0), 0);

    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  });
}
