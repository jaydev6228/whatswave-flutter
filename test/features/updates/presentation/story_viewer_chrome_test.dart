import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/core/models/story_viewer.dart';
import 'package:whatswave/features/updates/presentation/status_story_viewer_screen.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_chrome.dart';

void main() {
  // A remote video segment, so the mute toggle is in play on both stories.
  const segment = StatusStorySegment(
    id: 'seg-1',
    type: StatusStoryType.video,
    previewText: 'clip',
    localMediaPath: 'https://storage.example.com/clip.mp4',
  );

  StatusStory story({required bool isMine}) => StatusStory(
        id: isMine ? 'my-status' : 'ava-story',
        name: isMine ? 'My Status' : 'Ava',
        avatarLabel: 'AV',
        previewText: 'clip',
        timeLabel: '15m ago',
        accentColor: AppPalette.green,
        type: StatusStoryType.video,
        isMine: isMine,
        totalSegments: 1,
        seenSegments: 0,
        segments: const <StatusStorySegment>[segment],
      );

  Future<void> pumpViewer(WidgetTester tester, {required bool isMine}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StatusStoryViewerScreen(
          // Distinct key so pumping the other story type in the same test
          // builds a fresh State rather than reusing the previous one.
          key: ValueKey<bool>(isMine),
          story: story(isMine: isMine),
          onStoryViewed: (_) {},
          segmentDurationOverride: const Duration(seconds: 10),
          onDeleteSegment: isMine
              ? (_, __) async => const StatusStoryDeleteResult(didDelete: true)
              : null,
          onFetchViewers: isMine ? (_) async => const <StoryViewer>[] : null,
        ),
      ),
    );
    await tester.pump();
  }

  const closeButton = Key('updates_story_close_button');
  const deleteButton = Key('updates_story_delete_button');

  for (final isMine in <bool>[true, false]) {
    final which = isMine ? 'your own status' : "someone else's status";

    testWidgets('$which builds its actions from the shared chrome button',
        (tester) async {
      await pumpViewer(tester, isMine: isMine);

      // Separate small buttons floating over the story -- deliberately not
      // the composer's grouped capsule, which reads as a bar laid across
      // the media.
      expect(find.byType(StatusChromeButtonGroup), findsNothing);
      expect(find.byKey(closeButton), findsOneWidget);

      // But still the shared component, not a viewer-private button that
      // can drift away from the rest of the chrome -- and at the compact
      // size, uniformly.
      final buttons = tester
          .widgetList<StatusChromeButton>(find.byType(StatusChromeButton));
      expect(buttons, isNotEmpty);
      for (final button in buttons) {
        expect(button.size, StatusChromeButton.compactSize);
      }
    });
  }

  testWidgets('delete is the only difference between the two story types',
      (tester) async {
    await pumpViewer(tester, isMine: false);
    expect(find.byKey(deleteButton), findsNothing);
    final theirs = tester
        .widgetList<StatusChromeButton>(find.byType(StatusChromeButton))
        .length;

    await pumpViewer(tester, isMine: true);
    expect(find.byKey(deleteButton), findsOneWidget);
    final mine = tester
        .widgetList<StatusChromeButton>(find.byType(StatusChromeButton))
        .length;

    expect(mine, theirs + 1);
  });

  testWidgets('the view count sits centred at the bottom of your own status',
      (tester) async {
    await pumpViewer(tester, isMine: true);

    final pill =
        tester.getRect(find.byKey(const Key('updates_story_viewer_count')));
    final screen = tester.getRect(find.byType(StatusStoryViewerScreen));

    expect(
      pill.center.dx,
      closeTo(screen.center.dx, 1),
      reason: 'the view count is not horizontally centred',
    );
  });
}
