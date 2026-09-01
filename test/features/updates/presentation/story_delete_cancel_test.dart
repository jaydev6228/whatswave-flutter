import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/core/models/story_viewer.dart';
import 'package:whatswave/features/updates/presentation/status_story_viewer_screen.dart';

void main() {
  const story = StatusStory(
    id: 'my-status',
    name: 'My Status',
    avatarLabel: 'JD',
    previewText: 'note',
    timeLabel: 'Just now',
    accentColor: AppPalette.emerald,
    type: StatusStoryType.text,
    isMine: true,
    totalSegments: 1,
    seenSegments: 0,
    segments: <StatusStorySegment>[
      StatusStorySegment(
        id: 'seg-1',
        type: StatusStoryType.text,
        previewText: 'note',
        textStyle: StatusTextStyle(fontId: 'clean'),
      ),
    ],
  );

  testWidgets('cancelling the delete dialog resumes the story', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StatusStoryViewerScreen(
          story: story,
          onStoryViewed: (_) {},
          segmentDurationOverride: const Duration(seconds: 10),
          onDeleteSegment: (_, __) async =>
              const StatusStoryDeleteResult(didDelete: true),
          onFetchViewers: (_) async => const <StoryViewer>[],
        ),
      ),
    );
    await tester.pump();

    double progress() => tester
        .getSize(find.byKey(const Key('updates_story_progress_fill_0')))
        .width;

    await tester.pump(const Duration(seconds: 2));
    final beforeDialog = progress();
    expect(beforeDialog, greaterThan(0));

    await tester.tap(find.byKey(const Key('updates_story_delete_button')));
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsOneWidget);

    // Paused while the dialog is up.
    final whilePaused = progress();
    await tester.pump(const Duration(seconds: 2));
    expect(progress(), whilePaused);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // And running again once it is dismissed. The dialog paused playback by
    // stopping the controllers directly, which _resumePlaybackFromHold
    // refuses to undo -- so the story sat frozen behind the closed dialog
    // with no way to start it again.
    await tester.pump(const Duration(seconds: 2));
    expect(
      progress(),
      greaterThan(whilePaused),
      reason: 'the story did not resume after cancelling',
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  });
}
