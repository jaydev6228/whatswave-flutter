import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/presentation/media_status_composer_screen.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_story_media_surface.dart';

import '../../../support/device_matrix.dart';

void main() {
  testWidgets('keeps the post action low and opens inline text editing cleanly',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shareTop = tester
        .getRect(find.byKey(const Key('updates_share_media_status_button')))
        .top;
    expect(shareTop, greaterThan(iphoneSeProfile.size.height * 0.7));
    expect(
      find.text(
        'Add text, emoji, music, or stickers, then place them on the story.',
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('updates_media_add_music_button')));
    await tester.pumpAndSettle();

    expect(find.text('Add music'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('updates_media_music_option_0')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_panel_fonts')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_media_inline_text_field')),
        findsOneWidget);
    expect(find.byKey(const Key('updates_media_text_editing_tray')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a typed caption is separate from the rich text overlay and takes '
      'priority over it when sharing', (tester) async {
    MediaStatusComposerDraft? capturedDraft;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open_composer_button'),
                onPressed: () async {
                  capturedDraft = await Navigator.of(context)
                      .push<MediaStatusComposerDraft>(
                    MaterialPageRoute<MediaStatusComposerDraft>(
                      builder: (_) => const MediaStatusComposerScreen(
                        type: StatusStoryType.photo,
                        localMediaPath: '/missing/photo.jpg',
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open_composer_button')));
    await tester.pumpAndSettle();

    // The plain caption field is a separate input from the rich "Add
    // text" overlay tool -- it's visible on the default toolbar without
    // needing to enter any tool first.
    expect(find.byKey(const Key('updates_media_caption_field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('updates_media_caption_field')),
      'Golden hour vibes',
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('updates_share_media_status_button')));
    await tester.pumpAndSettle();

    expect(capturedDraft, isNotNull);
    expect(capturedDraft!.caption, 'Golden hour vibes');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'text editing tray mirrors the text-status composer: single-tap-cycle '
      'font/color icons, no chip strips or size buttons',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_panel_fonts')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_media_cycle_font_button')),
        findsOneWidget);
    expect(find.byKey(const Key('updates_media_cycle_tone_button')),
        findsOneWidget);
    expect(
        find.byKey(const Key('updates_media_toggle_text_background_button')),
        findsOneWidget);
    expect(find.byKey(const Key('updates_media_cycle_alignment_button')),
        findsOneWidget);

    // The old chip-strip/S-M-L size buttons are gone -- size is now a pinch
    // gesture on the placed overlay, same as every other overlay type.
    expect(find.text('S'), findsNothing);
    expect(find.text('M'), findsNothing);
    expect(find.text('L'), findsNothing);

    await tester.tap(find.byKey(const Key('updates_media_cycle_font_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updates_media_cycle_tone_button')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const Key('updates_media_toggle_text_background_button')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('updates_media_cycle_alignment_button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'never shows a placement-guide border while placing/editing text -- '
      'only crop mode still shows a frame outline -- and a background tap '
      'commits and exits editing', (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_media_overlay_guide')), findsNothing);

    await tester.tap(find.byKey(const Key('updates_media_panel_fonts')));
    await tester.pumpAndSettle();

    // No border/guide appears just from placing or editing text -- WhatsApp
    // doesn't show one either, and it used to be inaccurate/duplicated once
    // overlays became free to move across the whole frame.
    expect(find.byKey(const Key('updates_media_overlay_guide')), findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('updates_media_inline_text_field')), findsNothing);
    expect(find.byKey(const Key('updates_media_overlay_guide')), findsNothing);
  });

  testWidgets('adds an emoji overlay and allows dragging it on the canvas',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_add_emoji_button')));
    await tester.pumpAndSettle();

    await _tapEmojiOption(tester, 0);

    final overlayFinder = find.byKey(const Key('updates_overlay_item_emoji-0'));
    expect(overlayFinder, findsOneWidget);
    final emojiFinder = find.text('😀').last;

    final before = tester.getCenter(emojiFinder);
    await tester.drag(emojiFinder, const Offset(48, -36));
    await tester.pumpAndSettle();

    final after = tester.getCenter(emojiFinder);
    expect(after.dx, greaterThan(before.dx));
    expect(after.dy, lessThan(before.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('emoji picker offers far more than a dozen glyphs, grouped by '
      'category', (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_add_emoji_button')));
    await tester.pumpAndSettle();

    // The "Smileys" header now sits below the stickers section (WhatsApp's
    // own ordering), so it isn't necessarily built/visible immediately --
    // scroll it into view first.
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('updates_media_sticker_emoji_list')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(find.text('Smileys'), 300,
        scrollable: scrollable);
    expect(find.text('Smileys'), findsOneWidget);
    // Far beyond the old 12-emoji cap -- option indices run well past it.
    expect(find.byKey(const Key('updates_media_emoji_option_100')),
        findsNothing, reason: 'not yet scrolled into view');
    await tester.scrollUntilVisible(
      find.byKey(const Key('updates_media_emoji_option_100')),
      300,
      scrollable: scrollable,
    );
    expect(find.byKey(const Key('updates_media_emoji_option_100')),
        findsOneWidget);
  });

  testWidgets(
      'sticker search in the combined sticker+emoji sheet narrows the '
      'flowing chip list',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('updates_media_add_emoji_button')));
    await tester.pumpAndSettle();

    expect(find.text('Weekend'), findsOneWidget);
    expect(find.text('Tokyo'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('updates_media_sticker_search_field')),
      'tokyo',
    );
    await tester.pumpAndSettle();

    expect(find.text('Weekend'), findsNothing);
    expect(find.text('Tokyo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'settles a dragged overlay back inside the frame after release, even '
      'when the drag traveled well past the frame edge', (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_add_emoji_button')));
    await tester.pumpAndSettle();

    await _tapEmojiOption(tester, 0);

    final emojiFinder = find.text('😀').last;
    await tester.drag(emojiFinder, const Offset(0, -480));
    await tester.pumpAndSettle();

    // The drag itself is unclamped -- deliberately, so the overlay can
    // travel down to the delete target -- but once released without
    // deleting it, it settles back within the frame instead of staying
    // stuck off-screen.
    final emojiRect = tester.getRect(emojiFinder);
    expect(emojiRect.top, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('drags a selected overlay into delete and removes it',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_add_emoji_button')));
    await tester.pumpAndSettle();

    await _tapEmojiOption(tester, 0);

    final overlayFinder = find.byKey(const Key('updates_overlay_item_emoji-0'));
    final deleteFinder =
        find.byKey(const Key('updates_media_delete_overlay_button'));
    final deleteVisibilityFinder =
        find.byKey(const Key('updates_media_delete_overlay_visibility'));
    final emojiFinder = find.text('😀').last;
    expect(overlayFinder, findsOneWidget);
    expect(deleteFinder, findsOneWidget);
    expect(
      tester.widget<AnimatedOpacity>(deleteVisibilityFinder).opacity,
      0,
    );

    final overlayCenter = tester.getCenter(emojiFinder);
    final gesture = await tester.createGesture();
    await gesture.down(overlayCenter);
    await tester.pump();
    expect(
      tester.widget<AnimatedOpacity>(deleteVisibilityFinder).opacity,
      0,
    );
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      tester.widget<AnimatedOpacity>(deleteVisibilityFinder).opacity,
      1,
    );
    final deleteCenter = tester.getCenter(deleteFinder);
    await gesture.moveTo(deleteCenter);
    await tester.pump(const Duration(milliseconds: 16));

    // The overlay itself must visually follow the finger all the way down
    // to the delete target, not just satisfy a hit-test computed from the
    // raw pointer position while staying visually clamped up near the top
    // of the frame. (emojiFinder, not overlayFinder -- the wrapper widget's
    // own layout box is the full frame regardless of drag position, since
    // Transform only affects paint; the glyph inside it is what actually
    // moves on screen.)
    final draggedOverlayCenter = tester.getCenter(emojiFinder);
    expect((draggedOverlayCenter - deleteCenter).distance, lessThan(60));

    await gesture.up();
    await tester.pumpAndSettle();

    expect(overlayFinder, findsNothing);
    expect(find.text('😀'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'keeps media transform locked while a selected overlay is being dragged',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
          initialSourceSizeHint: Size(240, 120),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_add_emoji_button')));
    await tester.pumpAndSettle();

    await _tapEmojiOption(tester, 0);

    var mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    final initialTransform = mediaSurface.mediaTransform;
    expect(mediaSurface.onScaleStart, isNull);
    expect(mediaSurface.onScaleUpdate, isNull);
    expect(mediaSurface.onScaleEnd, isNull);

    final emojiFinder = find.text('😀').last;
    await tester.drag(emojiFinder, const Offset(72, -48));
    await tester.pumpAndSettle();

    mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(mediaSurface.mediaTransform.scale, closeTo(initialTransform.scale, 0.0001));
    expect(mediaSurface.mediaTransform.offsetDx,
        closeTo(initialTransform.offsetDx, 0.0001));
    expect(mediaSurface.mediaTransform.offsetDy,
        closeTo(initialTransform.offsetDy, 0.0001));
    expect(
      mediaSurface.mediaTransform.frameAspectRatio,
      closeTo(initialTransform.frameAspectRatio!, 0.0001),
    );

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Deselecting the emoji does NOT re-enable panning/zooming the media --
    // that's only ever available inside the crop tool now, matching
    // WhatsApp, where you can't drift the photo around during ordinary
    // editing at all.
    mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(mediaSurface.onScaleStart, isNull);
    expect(mediaSurface.onScaleUpdate, isNull);
    expect(mediaSurface.onScaleEnd, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'keeps an overlay visually anchored when selection chrome toggles',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_add_emoji_button')));
    await tester.pumpAndSettle();

    await _tapEmojiOption(tester, 0);

    final emojiFinder = find.text('😀').last;
    await tester.drag(emojiFinder, const Offset(120, -180));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final unselectedCenter = tester.getCenter(emojiFinder);

    await tester.tap(emojiFinder);
    await tester.pumpAndSettle();
    final selectedCenter = tester.getCenter(emojiFinder);

    expect(selectedCenter.dx, closeTo(unselectedCenter.dx, 0.1));
    expect(selectedCenter.dy, closeTo(unselectedCenter.dy, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'rotate lives in the crop-or-rotate tray, matching WhatsApp\'s real '
      'explicit crop step, and inverts the auto-fitted frame to match the '
      'rotated content',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
          // 2:1 landscape source -- the composer auto-fits the frame to
          // this ratio on load; there's no separate aspect-ratio picker to
          // select it through anymore.
          initialSourceSizeHint: Size(240, 120),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(mediaSurface.mediaTransform.frameAspectRatio, closeTo(2, 0.0001));
    expect(mediaSurface.mediaTransform.rotationQuarterTurns, 0);

    // The toolbar pill scrolls horizontally on narrow screens now that it
    // holds all 7 of WhatsApp's real tools -- ensure the last one is
    // actually scrolled into view before tapping it.
    await tester.ensureVisible(
      find.byKey(const Key('updates_media_crop_rotate_button')),
    );
    await tester
        .tap(find.byKey(const Key('updates_media_crop_rotate_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_media_rotate_button')),
        findsOneWidget);
    expect(find.byKey(const Key('updates_media_crop_aspect_ratio_button')),
        findsOneWidget);
    expect(find.byKey(const Key('updates_media_crop_done_button')),
        findsOneWidget);

    // Crop mode shows exactly one frame outline (from the media surface
    // itself) -- not a second, separately-inset placement-guide border on
    // top of it, which used to render as a confusing "double corner
    // border" once both were active at the same time.
    expect(find.byKey(const Key('updates_media_overlay_guide')), findsNothing);
    expect(
      tester
          .widget<StatusStoryMediaSurface>(
            find.byType(StatusStoryMediaSurface),
          )
          .showFrameOutline,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('updates_media_rotate_button')));
    await tester.pumpAndSettle();

    mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(mediaSurface.mediaTransform.rotationQuarterTurns, 1);
    // The frame must flip to portrait along with the content -- a stale
    // landscape frame would force-crop the now-portrait content, exactly
    // the bug this regression guards against.
    expect(mediaSurface.mediaTransform.frameAspectRatio, closeTo(0.5, 0.0001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a crop aspect ratio applies it to the frame',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('updates_media_crop_rotate_button')),
    );
    await tester
        .tap(find.byKey(const Key('updates_media_crop_rotate_button')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('updates_media_crop_aspect_ratio_button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_crop_aspect_Square')));
    await tester.pumpAndSettle();

    final mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(mediaSurface.mediaTransform.frameAspectRatio, closeTo(1, 0.0001));

    await tester.tap(find.byKey(const Key('updates_media_crop_done_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_media_rotate_button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Fit to screen" clears the aspect ratio constraint',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('updates_media_crop_rotate_button')),
    );
    await tester
        .tap(find.byKey(const Key('updates_media_crop_rotate_button')));
    await tester.pumpAndSettle();

    // First pick Square so there's a real constraint to clear.
    await tester.tap(
      find.byKey(const Key('updates_media_crop_aspect_ratio_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updates_media_crop_aspect_Square')));
    await tester.pumpAndSettle();

    var mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(mediaSurface.mediaTransform.frameAspectRatio, isNotNull);

    await tester.tap(
      find.byKey(const Key('updates_media_crop_aspect_ratio_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('updates_media_crop_aspect_Fit to screen')),
    );
    await tester.pumpAndSettle();

    mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(mediaSurface.mediaTransform.frameAspectRatio, isNull);
    // "Original" also clears the ratio to null when the source aspect is
    // unresolved, so the ratio button must remember which of the two was
    // actually picked rather than always reporting "Original" back.
    expect(find.text('Fit to screen'), findsOneWidget);
    expect(find.text('Original'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dragging a free-form crop corner reshapes the frame to a custom ratio',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('updates_media_crop_rotate_button')),
    );
    await tester
        .tap(find.byKey(const Key('updates_media_crop_rotate_button')));
    await tester.pumpAndSettle();

    final beforeSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    final ratioBefore = beforeSurface.mediaTransform.frameAspectRatio;
    final frameSizeBefore =
        tester.getSize(find.byKey(const Key('updates_media_story_frame')));

    final bottomRightHandle = find.byKey(
      const Key('updates_media_crop_corner_bottomRight'),
    );
    expect(bottomRightHandle, findsOneWidget);
    // Drag the bottom-right corner inward -- shrinks both width and height
    // symmetrically (the frame stays centered), producing a new ratio.
    await tester.drag(bottomRightHandle, const Offset(-60, 0));
    await tester.pumpAndSettle();

    final afterSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    final ratioAfter = afterSurface.mediaTransform.frameAspectRatio;
    expect(ratioAfter, isNotNull);
    expect(ratioAfter, isNot(ratioBefore));

    // Regression guard: an inward drag must shrink the frame the user
    // actually sees, not snap it back up to the largest rectangle of the
    // new ratio -- that mismatch is what made a small corner drag look
    // like it grew the media instead of cropping it.
    final frameSizeAfter =
        tester.getSize(find.byKey(const Key('updates_media_story_frame')));
    expect(frameSizeAfter.width, lessThan(frameSizeBefore.width));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'media pan/zoom gestures are only available inside the crop tool, '
      'and Reset undoes them without touching rotation or aspect ratio',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    var mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(mediaSurface.onScaleStart, isNull,
        reason: 'no crop mode active yet -- the media must not be '
            'draggable during ordinary editing');

    await tester.ensureVisible(
      find.byKey(const Key('updates_media_crop_rotate_button')),
    );
    await tester
        .tap(find.byKey(const Key('updates_media_crop_rotate_button')));
    await tester.pumpAndSettle();

    mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(mediaSurface.onScaleStart, isNotNull,
        reason: 'crop mode is the one place panning/zooming is allowed');
    expect(find.byKey(const Key('updates_media_crop_reset_button')),
        findsNothing,
        reason: 'nothing to reset before any pan/zoom has happened');

    await tester.drag(
      find.byType(StatusStoryMediaSurface),
      const Offset(40, 30),
    );
    await tester.pumpAndSettle();

    mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    final panned = mediaSurface.mediaTransform;
    expect(
      panned.offsetDx != 0 || panned.offsetDy != 0,
      isTrue,
      reason: 'the drag should have actually moved the media',
    );
    final rotationAfterPan = panned.rotationQuarterTurns;

    final resetButton =
        find.byKey(const Key('updates_media_crop_reset_button'));
    expect(resetButton, findsOneWidget);
    await tester.tap(resetButton);
    await tester.pumpAndSettle();

    mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(mediaSurface.mediaTransform.scale, 1);
    expect(mediaSurface.mediaTransform.offsetDx, 0);
    expect(mediaSurface.mediaTransform.offsetDy, 0);
    // Reset only undoes pan/zoom -- rotation (a deliberate, separate
    // choice made via its own button) is left alone.
    expect(mediaSurface.mediaTransform.rotationQuarterTurns,
        rotationAfterPan);
    expect(find.byKey(const Key('updates_media_crop_reset_button')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the blur slider blurs the media surface',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    var mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(mediaSurface.mediaTransform.blurSigma, 0);

    await tester.ensureVisible(
      find.byKey(const Key('updates_media_blur_button')),
    );
    await tester.tap(find.byKey(const Key('updates_media_blur_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_media_blur_editing_tray')),
        findsOneWidget);

    final slider = find.byKey(const Key('updates_media_blur_slider'));
    await tester.drag(slider, const Offset(80, 0));
    await tester.pumpAndSettle();

    mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(mediaSurface.mediaTransform.blurSigma, greaterThan(0));

    await tester.tap(find.byKey(const Key('updates_media_blur_done_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_media_blur_editing_tray')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the selected image in its natural fitted frame first',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
          initialSourceSizeHint: Size(240, 120),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final frameRect =
        tester.getRect(find.byKey(const Key('updates_media_story_frame')));
    expect(frameRect.width, closeTo(iphoneSeProfile.size.width, 1));
    expect(
      frameRect.height,
      closeTo(iphoneSeProfile.size.width / 2, 2),
    );
    expect(
      frameRect.height,
      lessThan(iphoneSeProfile.size.height * 0.7),
    );
    expect(tester.takeException(), isNull);
  });

  for (final device in compactDeviceMatrix) {
    testWidgets(
      'keeps the media status composer compact and overflow-free on ${device.name}',
      (tester) async {
        await tester.binding.setSurfaceSize(device.size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme(),
            darkTheme: AppTheme.darkTheme(),
            home: const MediaStatusComposerScreen(
              type: StatusStoryType.photo,
              localMediaPath: '/missing/photo.jpg',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('updates_media_composer_screen')),
          findsOneWidget,
        );
        expect(
          find.text('Weekend mood'),
          findsNothing,
        );
        expect(
          find.text('See you soon'),
          findsNothing,
        );
        expect(
          find.byKey(const Key('updates_media_panel_fonts')),
          findsOneWidget,
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              '${device.name} should render the media composer without overflow or layout exceptions.',
        );
      },
    );
  }

  testWidgets('draw button replaces the toolbar with the draw tray',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_media_draw_editing_tray')),
        findsNothing);

    await tester.tap(find.byKey(const Key('updates_media_draw_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_media_draw_editing_tray')),
        findsOneWidget);
    expect(find.byKey(const Key('updates_media_rotate_button')), findsNothing,
        reason: 'the normal toolbar should be replaced, not layered');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'drawing a stroke reaches the shared media surface, and undo clears it',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_draw_button')));
    await tester.pumpAndSettle();

    final drawSurface = find.byKey(const Key('updates_media_draw_surface'));
    expect(drawSurface, findsOneWidget);

    await tester.dragFrom(
      tester.getCenter(drawSurface) - const Offset(40, 40),
      const Offset(80, 80),
    );
    await tester.pumpAndSettle();

    final surfaceAfterDraw = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(surfaceAfterDraw.drawingStrokes, isNotEmpty);
    expect(surfaceAfterDraw.drawingStrokes.single.points.length, greaterThan(1));

    await tester.tap(find.byKey(const Key('updates_media_draw_undo_button')));
    await tester.pumpAndSettle();

    final surfaceAfterUndo = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(surfaceAfterUndo.drawingStrokes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the draw color bar picks a color off it',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_draw_button')));
    await tester.pumpAndSettle();

    final colorBar = find.byKey(const Key('updates_media_draw_color_bar'));
    expect(colorBar, findsOneWidget);
    // Midway down the bar is deep into the hue spectrum, well clear of the
    // white top -- the default draw color -- so tapping here confirms the
    // tap actually changed it.
    final barTopLeft = tester.getTopLeft(colorBar);
    final barHeight = tester.getSize(colorBar).height;
    await tester.tapAt(barTopLeft + Offset(10, barHeight / 2));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_media_draw_surface')),
        findsOneWidget,
        reason: 'draw mode should still be active after picking a color');

    final drawSurface = find.byKey(const Key('updates_media_draw_surface'));
    await tester.dragFrom(
      tester.getCenter(drawSurface) - const Offset(30, 0),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();

    final surface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(surface.drawingStrokes.single.colorValue, isNot(0xFFFFFFFF));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'toggling the eraser draws strokes that clear ink instead of adding '
      'it, and picking a color afterward switches back to the pen',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_draw_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_draw_eraser_button')));
    await tester.pumpAndSettle();

    final drawSurface = find.byKey(const Key('updates_media_draw_surface'));
    await tester.dragFrom(
      tester.getCenter(drawSurface) - const Offset(30, 0),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();

    var surface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(surface.drawingStrokes.single.isEraser, isTrue);

    // Picking any color again should exit eraser mode -- the next stroke
    // is ink, not an eraser stroke.
    final colorBar = find.byKey(const Key('updates_media_draw_color_bar'));
    final colorBarTopLeft = tester.getTopLeft(colorBar);
    final colorBarHeight = tester.getSize(colorBar).height;
    await tester.tapAt(colorBarTopLeft + Offset(10, colorBarHeight / 2));
    await tester.pumpAndSettle();
    await tester.dragFrom(
      tester.getCenter(drawSurface) - const Offset(30, 40),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();

    surface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(surface.drawingStrokes.last.isEraser, isFalse);
    expect(surface.drawingStrokes.last.colorValue, isNot(0xFFFFFFFF));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dragging along the draw color bar picks a color partway down it',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_draw_button')));
    await tester.pumpAndSettle();

    final colorBar = find.byKey(const Key('updates_media_draw_color_bar'));
    expect(colorBar, findsOneWidget);

    // Tap partway down the bar -- somewhere in the hue spectrum, away from
    // the white top and black bottom -- and confirm the thumb updates live
    // with no separate confirm step.
    final barTopLeft = tester.getTopLeft(colorBar);
    final barHeight = tester.getSize(colorBar).height;
    await tester.tapAt(barTopLeft + Offset(10, barHeight / 2));
    await tester.pump();

    final thumb = tester.widget<Container>(
      find.byKey(const Key('updates_media_draw_color_thumb')),
    );
    final thumbColor = (thumb.decoration! as BoxDecoration).color;
    expect(thumbColor, isNot(Colors.white));
    expect(thumbColor, isNot(Colors.black));

    final drawSurface = find.byKey(const Key('updates_media_draw_surface'));
    await tester.dragFrom(
      tester.getCenter(drawSurface) - const Offset(30, 0),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();

    final surface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(surface.drawingStrokes.single.colorValue, thumbColor!.toARGB32());
    expect(tester.takeException(), isNull);
  });
}

/// The combined sticker+emoji sheet shows stickers above the emoji grid
/// (matching WhatsApp), so an emoji option can start out below the fold --
/// scroll it into view before tapping instead of assuming it's already on
/// screen right after the sheet opens.
Future<void> _tapEmojiOption(WidgetTester tester, int index) async {
  final key = Key('updates_media_emoji_option_$index');
  await tester.scrollUntilVisible(
    find.byKey(key),
    300,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('updates_media_sticker_emoji_list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}
