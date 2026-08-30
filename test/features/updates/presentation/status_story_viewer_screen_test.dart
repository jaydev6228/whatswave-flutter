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
  const overlayAndCaptionStory = StatusStory(
    id: 'overlay-and-caption-story',
    name: 'Jay',
    avatarLabel: 'JD',
    previewText: 'Caption text',
    timeLabel: 'Just now',
    accentColor: AppPalette.green,
    type: StatusStoryType.photo,
    isMine: true,
    totalSegments: 1,
    seenSegments: 0,
    segments: <StatusStorySegment>[
      StatusStorySegment(
        id: 'overlay-and-caption-segment',
        type: StatusStoryType.photo,
        previewText: 'Caption text',
        localMediaPath: '/missing/media/overlay-and-caption.jpg',
        overlayItems: <StatusMediaOverlayItem>[
          StatusMediaOverlayItem(
            id: 'overlay-1',
            type: StatusMediaOverlayType.text,
            label: 'overlay text one',
          ),
          StatusMediaOverlayItem(
            id: 'overlay-2',
            type: StatusMediaOverlayType.text,
            label: 'overlay text two',
            positionDy: 0.3,
          ),
        ],
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

  testWidgets(
      'a long media caption collapses to three lines with a Show more '
      'affordance, and Show more expands that same caption in place -- over '
      'a translucent scrim, with no second copy left behind it -- until a '
      'tap anywhere collapses it again', (tester) async {
    // A real phone width -- the default 800px test surface is wide enough
    // to fit this caption in three lines, which would hide the very
    // affordance under test.
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpStoryViewerHarness(
      tester,
      story: longCaptionStory,
      segmentDurationOverride: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();

    final captionTextFinder =
        find.byKey(const Key('updates_story_viewer_caption_text'));
    expect(captionTextFinder, findsOneWidget);

    // Collapsed: three lines, ellipsised, with the affordance beneath.
    final collapsed = tester.widget<Text>(captionTextFinder);
    expect(collapsed.maxLines, kStoryCaptionCollapsedLines);
    expect(collapsed.overflow, TextOverflow.ellipsis);
    final showMore =
        find.byKey(const Key('updates_story_viewer_caption_show_more'));
    expect(showMore, findsOneWidget);
    expect(
      find.byKey(const Key('updates_story_viewer_caption_scrim')),
      findsNothing,
    );

    // No boxed-card chrome from the shared decoration overlay.
    expect(find.byKey(const Key('updates_media_caption_card')), findsNothing);
    expect(
      find.byKey(const Key('updates_media_caption_expand_button')),
      findsNothing,
    );

    // Still the caption's own base face, not the segment's 'journal'
    // rich-overlay look (italic serif -- see resolveTextStatusFontLook).
    final style = collapsed.style;
    final expectedBaseStyle = Theme.of(
      tester.element(captionTextFinder),
    ).textTheme.titleMedium;
    expect(style?.fontStyle, isNot(FontStyle.italic));
    expect(style?.fontFamily, isNot('serif'));
    expect(style?.fontWeight, expectedBaseStyle?.fontWeight);
    expect(style?.fontSize, expectedBaseStyle?.fontSize);

    await tester.tap(showMore);
    await tester.pumpAndSettle();

    // Expanded: still exactly ONE caption on screen -- the same one, grown
    // in place. A second, full-text copy layered over the collapsed one
    // would leave the three-line version visible behind it.
    expect(captionTextFinder, findsOneWidget);
    final expanded = tester.widget<Text>(captionTextFinder);
    expect(expanded.data, longCaptionStory.segments.single.previewText);
    expect(expanded.maxLines, isNull);
    expect(expanded.overflow, isNot(TextOverflow.ellipsis));
    expect(showMore, findsNothing);

    // Scrolls when the caption outgrows its share of the screen.
    expect(
      find.ancestor(
        of: captionTextFinder,
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );

    // Translucent, not opaque -- the story still reads through it.
    final scrimFinder =
        find.byKey(const Key('updates_story_viewer_caption_scrim'));
    expect(scrimFinder, findsOneWidget);
    final scrim = tester.widget<ColoredBox>(
      find.descendant(of: scrimFinder, matching: find.byType(ColoredBox)),
    );
    expect(scrim.color.a, greaterThan(0));
    expect(scrim.color.a, lessThan(1));

    // A tap anywhere collapses it back -- and does not skip the segment.
    // Single pump, not pumpAndSettle: collapsing resumes playback, and
    // settling would run the whole segment out and close the viewer.
    await tester.tapAt(const Offset(30, 300));
    await tester.pump();

    expect(scrimFinder, findsNothing);
    expect(showMore, findsOneWidget);
    expect(
      tester.widget<Text>(captionTextFinder).maxLines,
      kStoryCaptionCollapsedLines,
    );
    expect(find.byKey(const Key('updates_story_viewer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a quick swipe does not skip the segment -- only a real tap navigates, '
      'so scrolling a long text overlay cannot advance the story underneath',
      (tester) async {
    await _pumpStoryViewerHarness(
      tester,
      story: story,
      segmentDurationOverride: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();

    expect(_fillWidthFactor(tester, 0), lessThan(1));
    expect(_fillWidthFactor(tester, 1), 0);

    // A fast flick on the right zone: no elapsed time at all, so it beats
    // the tap *duration* threshold -- only the travel distance can tell it
    // apart from a tap.
    final gesture = await tester.startGesture(
      tester
          .getCenter(find.byKey(const Key('updates_story_viewer_right_zone'))),
    );
    await gesture.moveBy(const Offset(0, -160));
    await gesture.up();
    await tester.pump();

    // Still on the first segment: advancing would have filled bar 0
    // completely, the same signal the genuine tap below produces.
    expect(
      _fillWidthFactor(tester, 0),
      lessThan(1),
      reason: 'a swipe must not advance the story',
    );
    expect(find.byKey(const Key('updates_story_viewer')), findsOneWidget);

    // A genuine tap still advances, so the guard did not break navigation.
    await tester.tap(find.byKey(const Key('updates_story_viewer_right_zone')));
    await tester.pump();
    expect(_fillWidthFactor(tester, 0), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a caption short enough to fit shows no Show more affordance',
      (tester) async {
    await _pumpStoryViewerHarness(
      tester,
      story: overlayAndCaptionStory,
      segmentDurationOverride: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();

    expect(
      find.byKey(const Key('updates_story_viewer_caption_text')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('updates_story_viewer_caption_show_more')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final device in compactDeviceMatrix) {
    testWidgets(
        'a very long caption stays readable and overflow-free on '
        '${device.name} at the largest accessibility text scale',
        (tester) async {
      await tester.binding.setSurfaceSize(device.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // No length cap exists any more, so prove the layout copes with a
      // caption far longer than any previous limit.
      final maxedCaption = 'wandering words ' * 60;
      final story = StatusStory(
        id: 'max-caption-story',
        name: 'Luna',
        avatarLabel: 'LU',
        previewText: maxedCaption,
        timeLabel: 'Just now',
        accentColor: AppPalette.green,
        type: StatusStoryType.photo,
        totalSegments: 1,
        seenSegments: 0,
        segments: <StatusStorySegment>[
          StatusStorySegment(
            id: 'max-caption-segment',
            type: StatusStoryType.photo,
            previewText: maxedCaption,
            localMediaPath: '/missing/media/max-caption.jpg',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          home: MediaQuery(
            // 200% -- Android 14's ceiling, the floor this project tests
            // against (see docs/ui_layout_guidelines.md).
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: StatusStoryViewerScreen(
              story: story,
              onStoryViewed: (_) {},
              segmentDurationOverride: const Duration(seconds: 10),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('updates_story_viewer_caption_text')),
        findsOneWidget,
      );
      // The whole point: the biggest caption we accept, at the biggest
      // text size the OS offers, on the smallest screen we support, still
      // lays out without a single overflow.
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'placed rich text overlays still render in the viewer alongside a '
      "separately typed caption -- moving the caption into the viewer's "
      "own bottom chrome must not also hide the media layer's overlay "
      'items', (tester) async {
    await _pumpStoryViewerHarness(
      tester,
      story: overlayAndCaptionStory,
      segmentDurationOverride: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();

    expect(find.text('overlay text one'), findsOneWidget);
    expect(find.text('overlay text two'), findsOneWidget);
    expect(find.byKey(const Key('updates_story_viewer_caption_text')),
        findsOneWidget);
    expect(find.text('Caption text'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets(
      'the view count sits at the bottom of the story like WhatsApp, not in '
      'the name row', (tester) async {
    await _pumpStoryViewerHarness(
      tester,
      story: myTextStory,
      segmentDurationOverride: const Duration(seconds: 10),
      onFetchViewers: (_) async => const <StoryViewer>[],
    );

    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final screen =
        tester.getSize(find.byKey(const Key('updates_story_viewer')));
    final count =
        tester.getRect(find.byKey(const Key('updates_story_viewer_count')));
    final name = tester.getRect(find.text(myTextStory.name));

    expect(
      count.top,
      greaterThan(screen.height * 0.5),
      reason: 'the view count is still up in the header',
    );
    expect(count.top, greaterThan(name.bottom));
    // Still a real tap target, and still opens the viewers sheet.
    expect(count.height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('updates_story_viewer_count')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('story_viewers_sheet')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a caption still shows when a placed overlay happens to say the same '
      'thing, the way WhatsApp shows both', (tester) async {
    const shared = 'snsnsnssnmasmm';
    final story = StatusStory(
      id: 'mine-media',
      name: 'Jay',
      avatarLabel: 'JD',
      previewText: shared,
      timeLabel: 'Just now',
      accentColor: AppPalette.emerald,
      type: StatusStoryType.photo,
      totalSegments: 1,
      seenSegments: 0,
      isMine: true,
      segments: const [
        StatusStorySegment(
          id: 'seg-1',
          type: StatusStoryType.photo,
          previewText: shared,
          localMediaPath: '/missing/photo.jpg',
          overlayItems: [
            StatusMediaOverlayItem(
              id: 'overlay-text',
              type: StatusMediaOverlayType.text,
              label: shared,
            ),
          ],
        ),
      ],
    );

    await _pumpStoryViewerHarness(
      tester,
      story: story,
      segmentDurationOverride: const Duration(seconds: 10),
      onFetchViewers: (_) async => const <StoryViewer>[],
    );
    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Once as the placed overlay, once as the caption. Suppressing the
    // caption because an overlay matched it made a caption the user had
    // definitely typed simply never appear.
    expect(
      find.text(shared),
      findsNWidgets(2),
      reason: 'the caption was swallowed by the matching overlay',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the view count is per status item -- someone who watched a story '
      'that is gone does not count toward a new one', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const story = StatusStory(
      id: 'mine-fresh',
      name: 'Jay',
      avatarLabel: 'JD',
      previewText: 'Brand new',
      timeLabel: 'Just now',
      accentColor: AppPalette.emerald,
      type: StatusStoryType.photo,
      totalSegments: 1,
      seenSegments: 0,
      isMine: true,
      segments: [
        StatusStorySegment(
          id: 'fresh-segment',
          type: StatusStoryType.photo,
          previewText: 'Brand new',
          localMediaPath: '/missing/photo.jpg',
        ),
      ],
    );

    // Watched three segments of an earlier story, none of them this one.
    // The old count-based rule read that as "has seen >= 1 segment" and
    // counted them here.
    await _pumpStoryViewerHarness(
      tester,
      story: story,
      segmentDurationOverride: const Duration(seconds: 30),
      onFetchViewers: (_) async => [
        StoryViewer(
          uid: 'riyana',
          name: 'Riyana',
          avatarLabel: 'R',
          accentColor: AppPalette.emerald,
          seenSegments: 3,
          viewedSegmentIds: const ['old-segment-a', 'old-segment-b'],
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('0 views'),
      findsOneWidget,
      reason: 'a viewer of a different story is being counted here',
    );

    // And someone who really did watch this item counts.
    await _pumpStoryViewerHarness(
      tester,
      story: story,
      segmentDurationOverride: const Duration(seconds: 30),
      onFetchViewers: (_) async => [
        StoryViewer(
          uid: 'riyana',
          name: 'Riyana',
          avatarLabel: 'R',
          accentColor: AppPalette.emerald,
          seenSegments: 1,
          viewedSegmentIds: const ['fresh-segment'],
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('open_viewer_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('1 view'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
