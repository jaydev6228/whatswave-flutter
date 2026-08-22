import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/core/models/story_viewer.dart';
import 'package:whatswave/features/updates/presentation/status_story_viewer_screen.dart';

import '../../../support/device_matrix.dart';

void main() {
  const story = StatusStory(
    id: 'ava-story',
    name: 'Ava',
    avatarLabel: 'AP',
    previewText: 'Late-night launch coffee',
    timeLabel: '15m ago',
    accentColor: AppPalette.green,
    type: StatusStoryType.photo,
    totalSegments: 3,
    seenSegments: 0,
  );
  const viewedStory = StatusStory(
    id: 'priya-story',
    name: 'Priya',
    avatarLabel: 'PR',
    previewText: 'Sketchbook dump',
    timeLabel: '1h ago',
    accentColor: AppPalette.green,
    type: StatusStoryType.photo,
    totalSegments: 3,
    seenSegments: 3,
  );
  const myTextStory = StatusStory(
    id: 'my-status',
    name: 'My Status',
    avatarLabel: 'JD',
    previewText: 'Studio launch invite',
    timeLabel: 'Just now',
    accentColor: AppPalette.emerald,
    type: StatusStoryType.text,
    isMine: true,
    totalSegments: 2,
    seenSegments: 0,
    segments: <StatusStorySegment>[
      StatusStorySegment(
        id: 'my-status-first',
        type: StatusStoryType.text,
        previewText: 'Earlier note',
        textStyle: StatusTextStyle(
          fontId: 'clean',
          backgroundId: 'emerald_pop',
          layout: StatusTextLayout.classic,
          alignment: StatusTextAlignment.center,
        ),
      ),
      StatusStorySegment(
        id: 'my-status-second',
        type: StatusStoryType.text,
        previewText: 'Studio launch invite\n7 PM tonight',
        textStyle: StatusTextStyle(
          fontId: 'serif',
          backgroundId: 'sunset_glow',
          layout: StatusTextLayout.invitation,
          alignment: StatusTextAlignment.center,
        ),
      ),
    ],
  );
  const longCaptionStory = StatusStory(
    id: 'long-caption-story',
    name: 'Luna',
    avatarLabel: 'LU',
    previewText: 'Shared a new photo update',
    timeLabel: 'Just now',
    accentColor: AppPalette.green,
    type: StatusStoryType.photo,
    totalSegments: 1,
    seenSegments: 0,
    segments: <StatusStorySegment>[
      StatusStorySegment(
        id: 'long-caption-segment',
        type: StatusStoryType.photo,
        previewText:
            'Tonight we are turning this whole status into a proper invitation banner with the headline, timing, venue notes, a dress-code hint, and a warm RSVP message so the caption needs a cleaner collapsed preview and a Show more action instead of just dropping useful text.',
        localMediaPath: '/missing/media/long-caption.jpg',
        textStyle: StatusTextStyle(
          fontId: 'journal',
          backgroundId: 'midnight_drive',
          layout: StatusTextLayout.note,
          alignment: StatusTextAlignment.left,
          textColorValue: 0xFFFFFFFF,
          sizeScale: 1.04,
        ),
      ),
    ],
  );
  const musicBackedStory = StatusStory(
    id: 'music-story',
    name: 'Noah',
    avatarLabel: 'NO',
    previewText: 'Shared a new photo update',
    timeLabel: 'Just now',
    accentColor: AppPalette.green,
    type: StatusStoryType.photo,
    totalSegments: 1,
    seenSegments: 0,
    segments: <StatusStorySegment>[
      StatusStorySegment(
        id: 'music-segment',
        type: StatusStoryType.photo,
        previewText: 'Shared a new photo update',
        localMediaPath: '/missing/media/music.jpg',
        musicTrack: StatusMusicTrack(
          id: 'hip-hop-02',
          title: 'Hip Hop 02',
          artist: 'Lily J',
          colorValue: 0xFF25D366,
          secondaryColorValue: 0xFFD9FBE8,
          previewAssetPath: 'assets/audio/status_music/hip_hop_02.mp3',
          bannerStyleId: 'cover',
        ),
      ),
    ],
  );
  const drawnPhotoStory = StatusStory(
    id: 'drawn-story',
    name: 'Marco',
    avatarLabel: 'MA',
    previewText: 'Shared a new photo update',
    timeLabel: 'Just now',
    accentColor: AppPalette.green,
    type: StatusStoryType.photo,
    totalSegments: 1,
    seenSegments: 0,
    segments: <StatusStorySegment>[
      StatusStorySegment(
        id: 'drawn-segment',
        type: StatusStoryType.photo,
        previewText: 'Shared a new photo update',
        localMediaPath: 'asset://assets/media/status_demo/launch_cafe.jpg',
        drawingStrokes: <StatusDrawingStroke>[
          StatusDrawingStroke(
            points: <Offset>[Offset(0.1, 0.1), Offset(0.9, 0.9)],
            colorValue: 0xFFFFD60A,
            strokeWidth: 0.02,
          ),
        ],
      ),
    ],
  );

  testWidgets('progress bar fills and auto-plays until the story closes',
      (tester) async {
    final viewedStories = <StatusStory>[];

    await _pumpStoryViewerHarness(
      tester,
      story: story,
      segmentDurationOverride: const Duration(milliseconds: 120),
      onStoryViewed: viewedStories.add,
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();

    expect(find.byKey(const Key('updates_story_viewer')), findsOneWidget);
    expect(viewedStories.first.id, 'ava-story');
    expect(viewedStories.first.seenSegments, 1);
    expect(_fillWidthFactor(tester, 0), 0);

    await tester.pump(const Duration(milliseconds: 60));
    expect(_fillWidthFactor(tester, 0), greaterThan(0.35));
    expect(_fillWidthFactor(tester, 0), lessThan(0.75));

    await tester.pump(const Duration(milliseconds: 330));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_story_viewer')), findsNothing);
    expect(find.byKey(const Key('viewer_home_marker')), findsOneWidget);
    expect(viewedStories.last.seenSegments, 3);
  });

  testWidgets(
      'local media stories stay edge-to-edge instead of shrinking into a padded card',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpStoryViewerHarness(
      tester,
      story: longCaptionStory,
      segmentDurationOverride: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final mediaRect = tester
        .getRect(find.byKey(const Key('updates_story_viewer_media_surface')));
    expect(mediaRect.width, closeTo(iphoneSeProfile.size.width, 0.1));
  });

  testWidgets(
      'a posted photo status still shows its drawing strokes in the viewer',
      (tester) async {
    await _pumpStoryViewerHarness(
      tester,
      story: drawnPhotoStory,
      segmentDurationOverride: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const Key('updates_story_drawing_layer')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'fully viewed stories reopen from the first segment and left tap keeps them open',
      (tester) async {
    await _pumpStoryViewerHarness(
      tester,
      story: viewedStory,
      segmentDurationOverride: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));
    final beforeRestart = _fillWidthFactor(tester, 0);
    expect(beforeRestart, greaterThan(0));

    await tester.tap(find.byKey(const Key('updates_story_viewer_left_zone')));
    await tester.pump();

    expect(find.byKey(const Key('updates_story_viewer')), findsOneWidget);
    expect(_fillWidthFactor(tester, 0), lessThan(beforeRestart));

    await tester.tap(find.byKey(const Key('updates_story_viewer_right_zone')));
    await tester.pump();

    expect(_fillWidthFactor(tester, 0), 1);
  });

  testWidgets('tap zones move backward and forward through a user story',
      (tester) async {
    await _pumpStoryViewerHarness(
      tester,
      story: story,
      segmentDurationOverride: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('updates_story_viewer_right_zone')));
    await tester.pump();
    expect(_fillWidthFactor(tester, 0), 1);

    await tester.tap(find.byKey(const Key('updates_story_viewer_left_zone')));
    await tester.pump();
    expect(_fillWidthFactor(tester, 0), lessThan(1));

    await tester.tap(find.byKey(const Key('updates_story_viewer_right_zone')));
    await tester.pump();
    expect(_fillWidthFactor(tester, 0), 1);

    await tester.tap(find.byKey(const Key('updates_story_viewer_right_zone')));
    await tester.pump();
    expect(_fillWidthFactor(tester, 1), 1);

    await tester.tap(find.byKey(const Key('updates_story_viewer_right_zone')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_story_viewer')), findsNothing);
    expect(find.byKey(const Key('viewer_home_marker')), findsOneWidget);
  });

  testWidgets('holding a story pauses progress until the finger is released',
      (tester) async {
    await _pumpStoryViewerHarness(
      tester,
      story: story,
      segmentDurationOverride: const Duration(seconds: 2),
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final progressBeforeHold = _fillWidthFactor(tester, 0);

    final gesture = await tester.createGesture();
    await gesture.down(
      tester
          .getCenter(find.byKey(const Key('updates_story_viewer_right_zone'))),
    );
    await tester.pump(const Duration(milliseconds: 20));

    final pausedProgress = _fillWidthFactor(tester, 0);
    expect(pausedProgress, closeTo(progressBeforeHold, 0.02));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_fillWidthFactor(tester, 0), closeTo(pausedProgress, 0.02));
    expect(_fillWidthFactor(tester, 1), 0);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(_fillWidthFactor(tester, 0), greaterThan(pausedProgress));
  });

  testWidgets(
      'holding on the last segment resumes playback instead of closing the viewer',
      (tester) async {
    await _pumpStoryViewerHarness(
      tester,
      story: story,
      segmentDurationOverride: const Duration(seconds: 2),
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('updates_story_viewer_right_zone')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    final progressBeforeHold = _fillWidthFactor(tester, 1);

    final gesture = await tester.createGesture();
    await gesture.down(
      tester
          .getCenter(find.byKey(const Key('updates_story_viewer_right_zone'))),
    );
    await tester.pump(const Duration(milliseconds: 20));

    final pausedProgress = _fillWidthFactor(tester, 1);
    expect(pausedProgress, closeTo(progressBeforeHold, 0.02));
    await tester.pump(const Duration(milliseconds: 280));
    expect(_fillWidthFactor(tester, 1), closeTo(pausedProgress, 0.02));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.byKey(const Key('updates_story_viewer')), findsOneWidget);
    expect(_fillWidthFactor(tester, 1), greaterThan(pausedProgress));
  });

  testWidgets('my multi-segment text status opens on the first segment',
      (tester) async {
    await _pumpStoryViewerHarness(
      tester,
      story: myTextStory,
      segmentDurationOverride: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();

    expect(find.byKey(const Key('updates_story_text_card')), findsOneWidget);
    expect(find.text('Earlier note'), findsOneWidget);
    expect(find.text('Studio launch invite\n7 PM tonight'), findsNothing);
  });

  testWidgets(
      'viewer can jump directly to a later text segment using initialSegmentIndex',
      (tester) async {
    await _pumpStoryViewerHarness(
      tester,
      story: myTextStory,
      segmentDurationOverride: const Duration(seconds: 10),
      initialSegmentIndex: 1,
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();

    expect(find.byKey(const Key('updates_story_text_card')), findsOneWidget);
    expect(find.text('Studio launch invite\n7 PM tonight'), findsOneWidget);
    expect(find.text('Earlier note'), findsNothing);
  });

  testWidgets('long media captions can expand without triggering navigation',
      (tester) async {
    await _pumpStoryViewerHarness(
      tester,
      story: longCaptionStory,
      segmentDurationOverride: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();

    final captionTextFinder =
        find.byKey(const Key('updates_media_caption_text'));
    expect(captionTextFinder, findsOneWidget);
    expect(
      tester.widget<Text>(captionTextFinder).maxLines,
      4,
    );
    expect(
      find.byKey(const Key('updates_media_caption_expand_button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('updates_media_caption_expand_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.byKey(const Key('updates_story_viewer')), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);
    expect(
      tester.widget<Text>(captionTextFinder).maxLines,
      isNull,
    );
  });

  testWidgets('music-backed statuses stay stable and keep progressing',
      (tester) async {
    await _pumpStoryViewerHarness(
      tester,
      story: musicBackedStory,
      segmentDurationOverride: const Duration(seconds: 2),
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('updates_story_viewer')), findsOneWidget);
    expect(find.text('Hip Hop 02'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening the viewed-by sheet pauses the progress bar',
      (tester) async {
    await _pumpStoryViewerHarness(
      tester,
      story: myTextStory,
      segmentDurationOverride: const Duration(seconds: 10),
      onFetchViewers: (_) async => const <StoryViewer>[],
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final fillBeforeSheet = _fillWidthFactor(tester, 0);
    expect(fillBeforeSheet, greaterThan(0));

    await tester.tap(find.byKey(const Key('updates_story_viewer_count')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('story_viewers_sheet')), findsOneWidget);
    final fillWhileSheetOpen = _fillWidthFactor(tester, 0);
    expect(fillWhileSheetOpen, closeTo(fillBeforeSheet, 0.02));
  });

  testWidgets('my status can delete the current segment after confirmation',
      (tester) async {
    String? deletedSegmentId;

    await _pumpStoryViewerHarness(
      tester,
      story: myTextStory,
      segmentDurationOverride: const Duration(seconds: 10),
      initialSegmentIndex: 1,
      onDeleteSegment: (story, segment) async {
        deletedSegmentId = segment.id;
        return StatusStoryDeleteResult(
          didDelete: true,
          updatedStory: story.copyWith(
            previewText: 'Earlier note',
            totalSegments: 1,
            seenSegments: 0,
            segments: const <StatusStorySegment>[
              StatusStorySegment(
                id: 'my-status-first',
                type: StatusStoryType.text,
                previewText: 'Earlier note',
                textStyle: StatusTextStyle(
                  fontId: 'clean',
                  backgroundId: 'emerald_pop',
                  layout: StatusTextLayout.classic,
                  alignment: StatusTextAlignment.center,
                ),
              ),
            ],
          ),
        );
      },
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('updates_story_delete_button')));
    await tester.pumpAndSettle();

    expect(find.text('Delete this status item?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(deletedSegmentId, 'my-status-second');
    expect(find.byKey(const Key('updates_story_viewer')), findsOneWidget);
    expect(find.text('Earlier note'), findsOneWidget);
    expect(find.text('Studio launch invite\n7 PM tonight'), findsNothing);
  });
}

double _fillWidthFactor(WidgetTester tester, int segmentIndex) {
  final fillSize = tester.getSize(
    find.byKey(Key('updates_story_progress_fill_$segmentIndex')),
  );
  final trackSize = tester.getSize(
    find.byKey(Key('updates_story_progress_track_$segmentIndex')),
  );
  if (trackSize.width == 0) {
    return 0;
  }
  return fillSize.width / trackSize.width;
}

Future<void> _pumpStoryViewerHarness(
  WidgetTester tester, {
  required StatusStory story,
  required Duration segmentDurationOverride,
  int? initialSegmentIndex,
  ValueChanged<StatusStory>? onStoryViewed,
  Future<StatusStoryDeleteResult> Function(
    StatusStory story,
    StatusStorySegment segment,
  )? onDeleteSegment,
  Future<List<StoryViewer>> Function(StatusStory story)? onFetchViewers,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open_viewer_button'),
                onPressed: () {
                  Navigator.of(context).push(
                    PageRouteBuilder<void>(
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      pageBuilder: (_, __, ___) => StatusStoryViewerScreen(
                        story: story,
                        onStoryViewed: onStoryViewed ?? (_) {},
                        segmentDurationOverride: segmentDurationOverride,
                        initialSegmentIndex: initialSegmentIndex,
                        onDeleteSegment: onDeleteSegment,
                        onFetchViewers: onFetchViewers,
                      ),
                    ),
                  );
                },
                child: const Text(
                  'Open',
                  key: Key('viewer_home_marker'),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(tester.takeException(), isNull);
}
