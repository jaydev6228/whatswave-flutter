import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/presentation/media_status_composer_screen.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_chrome.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_media_decoration_overlay.dart';
import 'package:whatswave/features/updates/presentation/status_motion.dart';
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

    // The sheet no longer carries a title -- tapping the music button is
    // already the label -- so the track list is what proves it opened.
    expect(
        find.byKey(const Key('updates_media_music_option_0')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('updates_media_music_option_0')));
    await tester.pumpAndSettle();

    // Picking a track leaves the music overlay selected, which swaps the
    // tool toolbar out for the selection bar. Tap the canvas to deselect
    // and get the tools back -- the music tray used to carry its own
    // duplicate "Add text" button for this, which read as a stray icon
    // floating above the style chips.
    await tester.tapAt(const Offset(30, 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_panel_fonts')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_media_inline_text_field')),
        findsOneWidget);
    expect(
        find.byKey(const Key('updates_media_text_font_row')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the media frame stays put when the keyboard opens for text editing, '
      'like WhatsApp -- it never shrinks or shifts up', (tester) async {
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

    final frameRectBeforeKeyboard =
        tester.getRect(find.byKey(const Key('updates_media_story_frame')));

    await tester.tap(find.byKey(const Key('updates_media_panel_fonts')));
    await tester.pumpAndSettle();

    // Simulate the system keyboard opening for the inline text field, the
    // same way real text entry would raise it.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final frameRectWithKeyboard =
        tester.getRect(find.byKey(const Key('updates_media_story_frame')));
    expect(frameRectWithKeyboard, frameRectBeforeKeyboard);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the caption field and share button step aside while editing text, '
      'like WhatsApp -- only the text tray and keyboard show', (tester) async {
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
        find.byKey(const Key('updates_media_caption_field')), findsOneWidget);
    expect(find.byKey(const Key('updates_share_media_status_button')),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('updates_media_panel_fonts')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('updates_media_text_font_row')), findsOneWidget);
    expect(find.byKey(const Key('updates_media_caption_field')), findsNothing);
    expect(find.byKey(const Key('updates_share_media_status_button')),
        findsNothing);

    await tester.tap(find.byKey(const Key('updates_media_text_done_button')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('updates_media_caption_field')), findsOneWidget);
    expect(find.byKey(const Key('updates_share_media_status_button')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the text tool matches WhatsApp: font row and color rail while '
      'typing, alignment/decoration icons in the top bar, and the card '
      'stays centered above the keyboard rather than wherever it was '
      'dragged', (tester) async {
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

    // Simulate the keyboard, the same way real text entry would raise it.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('updates_media_text_font_row')), findsOneWidget);
    expect(
        find.byKey(const Key('updates_media_text_color_rail')), findsOneWidget);
    expect(find.byKey(const Key('updates_media_text_align_button')),
        findsOneWidget);
    expect(find.byKey(const Key('updates_media_text_decoration_button')),
        findsOneWidget);

    // The editing card is horizontally centered on screen, and sits above
    // the font row -- not wherever the overlay's own stored position is,
    // and not overlapped by the keyboard chrome below it.
    final screenCenterX = tester
        .getCenter(find.byKey(const Key('updates_media_composer_screen')))
        .dx;
    final cardCenter = tester
        .getCenter(find.byKey(const Key('updates_media_inline_text_editor')));
    expect(cardCenter.dx, closeTo(screenCenterX, 1));
    final fontRowTop = tester
        .getRect(find.byKey(const Key('updates_media_text_font_row')))
        .top;
    expect(cardCenter.dy, lessThan(fontRowTop));

    // Tapping a different font swatch and dragging the color rail don't
    // throw -- direct tap-to-select, not the old single-tap cycle button.
    await tester.tap(
      find.byKey(const Key('updates_media_text_font_option_serif')),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const Key('updates_media_text_color_bar'))) +
          const Offset(4, 40),
    );
    await tester.pumpAndSettle();

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
    expect(
        find.byKey(const Key('updates_media_caption_field')), findsOneWidget);
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
      'once text editing ends, it fully reverts to the plain default '
      'toolbar -- no lingering quick-tools tray, matching WhatsApp -- and '
      'tapping the placed text reopens the redesigned editing view',
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

    // An empty text overlay is discarded on commit, so type something first
    // -- otherwise "Done" would remove it entirely rather than leaving it
    // placed on the canvas.
    await tester.enterText(
      find.byKey(const Key('updates_media_inline_text_field')),
      'Hello',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_text_done_button')));
    await tester.pumpAndSettle();

    // No special chrome survives Done -- the plain default toolbar (add
    // text/emoji/music/draw/blur/crop) is back, exactly as if nothing were
    // selected, not a leftover tray hovering above the caption row.
    expect(find.byKey(const Key('updates_media_panel_fonts')), findsOneWidget);
    expect(
        find.byKey(const Key('updates_media_text_align_button')), findsNothing);
    expect(find.byKey(const Key('updates_media_text_decoration_button')),
        findsNothing);
    expect(find.byKey(const Key('updates_media_text_font_row')), findsNothing);
    expect(
        find.byKey(const Key('updates_media_text_color_rail')), findsNothing);
    expect(find.text('Hello'), findsOneWidget);

    // Tapping the placed text goes straight back into the redesigned
    // editing view -- one tap, not a select-then-edit two-step.
    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('updates_media_text_font_row')), findsOneWidget);
    expect(
        find.byKey(const Key('updates_media_text_color_rail')), findsOneWidget);
    expect(find.byKey(const Key('updates_media_inline_text_field')),
        findsOneWidget);
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

  testWidgets(
      'emoji picker offers far more than a dozen glyphs, grouped by '
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
    expect(
        find.byKey(const Key('updates_media_emoji_option_100')), findsNothing,
        reason: 'not yet scrolled into view');
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
      'flowing chip list', (tester) async {
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

    final emojiFinder = find.text('😀').last;
    await tester.drag(emojiFinder, const Offset(72, -48));
    await tester.pumpAndSettle();

    mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(mediaSurface.mediaTransform.scale,
        closeTo(initialTransform.scale, 0.0001));
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
    // Sideways and only a little up: -180 parked it under the tool
    // toolbar, so the "tap to select" below hit the crop button instead
    // and the overlay vanished with the rest of them.
    await tester.drag(emojiFinder, const Offset(120, -60));
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
      'rotated content', (tester) async {
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
    await tester.tap(find.byKey(const Key('updates_media_crop_rotate_button')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('updates_media_rotate_button')), findsOneWidget);
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
    await tester.tap(find.byKey(const Key('updates_media_crop_rotate_button')));
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
    await tester.tap(find.byKey(const Key('updates_media_crop_rotate_button')));
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
      'crop mode opens on the full, unmodified frame with draggable corner '
      'handles -- dragging a corner resizes the crop window (never the '
      'media itself), dragging inside repositions it, and Reset undoes it',
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
    await tester.tap(find.byKey(const Key('updates_media_crop_rotate_button')));
    await tester.pumpAndSettle();

    // Crop mode opens on the full, uncropped frame -- matches WhatsApp's
    // own crop tool, which starts with nothing cropped away yet.
    final opened = tester
        .widget<StatusStoryMediaSurface>(find.byType(StatusStoryMediaSurface))
        .mediaTransform;
    expect(opened.frameAspectRatio, isNull);
    expect(opened.scale, 1);

    // All four corner handles exist and are draggable -- this is how you
    // resize the crop window (unlike the earlier plain-grid-only design).
    for (final corner in ['topLeft', 'topRight', 'bottomLeft', 'bottomRight']) {
      expect(
          find.byKey(Key('updates_media_crop_corner_$corner')), findsOneWidget);
    }

    // No Reset button yet -- nothing to reset before any drag has happened.
    expect(
        find.byKey(const Key('updates_media_crop_reset_button')), findsNothing);

    // Dragging the bottom-right corner handle inward shrinks the crop
    // window -- this crops in on the (never-moving) media, which shows up
    // as a real aspect ratio and a zoomed-in scale on the final transform.
    await tester.drag(
      find.byKey(const Key('updates_media_crop_corner_bottomRight')),
      const Offset(-120, -100),
    );
    await tester.pumpAndSettle();

    final resized = tester
        .widget<StatusStoryMediaSurface>(find.byType(StatusStoryMediaSurface))
        .mediaTransform;
    expect(resized.frameAspectRatio, isNotNull);
    expect(
      resized.scale,
      greaterThan(1),
      reason: 'shrinking the window should zoom the final crop in',
    );

    // Dragging inside the (now smaller-than-canvas) window repositions it
    // -- this is how you pick which part of the never-moving media the
    // resized window selects.
    await tester.drag(
      find.byType(StatusStoryMediaSurface),
      const Offset(40, 30),
    );
    await tester.pumpAndSettle();

    final panned = tester
        .widget<StatusStoryMediaSurface>(find.byType(StatusStoryMediaSurface))
        .mediaTransform;
    expect(
      panned.offsetDx != resized.offsetDx ||
          panned.offsetDy != resized.offsetDy,
      isTrue,
      reason: 'the drag should have moved the crop window',
    );
    // The move-only gesture never changes the zoom the corner drag set.
    expect(panned.scale, resized.scale);

    final resetButton =
        find.byKey(const Key('updates_media_crop_reset_button'));
    expect(resetButton, findsOneWidget);
    await tester.tap(resetButton);
    await tester.pumpAndSettle();

    final reset = tester
        .widget<StatusStoryMediaSurface>(find.byType(StatusStoryMediaSurface))
        .mediaTransform;
    expect(reset.scale, 1);
    expect(reset.offsetDx, 0);
    expect(reset.offsetDy, 0);
    expect(
        find.byKey(const Key('updates_media_crop_reset_button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the crop window stays inside the media it is cropping -- it can '
      'never be dragged out onto a letterbox bar -- and Reset restores the '
      "media's own original frame, not just the offsets", (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // A wide source on a tall screen letterboxes top and bottom, so there
    // is real empty space the window must refuse to enter.
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
          initialSourceSizeHint: Size(400, 200),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('updates_media_crop_rotate_button')),
    );
    await tester.tap(find.byKey(const Key('updates_media_crop_rotate_button')));
    await tester.pumpAndSettle();

    final original = tester
        .widget<StatusStoryMediaSurface>(find.byType(StatusStoryMediaSurface))
        .mediaTransform;
    expect(original.frameAspectRatio, closeTo(2, 0.0001));

    // Shrink the window so there is room to drag it around at all.
    await tester.drag(
      find.byKey(const Key('updates_media_crop_corner_bottomRight')),
      const Offset(-90, -40),
    );
    await tester.pumpAndSettle();

    // Now shove it far past the media's bottom edge, into the letterbox.
    await tester.drag(
      find.byType(StatusStoryMediaSurface),
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();

    final shoved = tester
        .widget<StatusStoryMediaSurface>(find.byType(StatusStoryMediaSurface))
        .mediaTransform;

    // Assert on the *stored* offset, not on a rect re-derived through
    // cropWindowRectFor -- that function re-clamps, so it would mask an
    // out-of-bounds value the composer had actually committed.
    final canvasSize =
        tester.getSize(find.byKey(const Key('updates_media_story_frame')));
    final mediaBounds =
        statusMediaBoundsFor(canvasSize, original.frameAspectRatio);
    final windowHeight =
        statusStoryFrameSizeFor(mediaBounds.size, shoved.frameAspectRatio)
                .height /
            shoved.scale;
    final maxOffsetDy =
        ((mediaBounds.height - windowHeight) / 2) / windowHeight;

    expect(
      shoved.offsetDy.abs(),
      lessThanOrEqualTo(maxOffsetDy + 0.001),
      reason: 'the crop window must never leave the media it is cropping',
    );

    // Reset puts the frame back on the media's own original ratio, not
    // merely zeroing the offsets while leaving a resized frame behind.
    await tester.tap(find.byKey(const Key('updates_media_crop_reset_button')));
    await tester.pumpAndSettle();

    final reset = tester
        .widget<StatusStoryMediaSurface>(find.byType(StatusStoryMediaSurface))
        .mediaTransform;
    expect(reset.scale, 1);
    expect(reset.offsetDx, 0);
    expect(reset.offsetDy, 0);
    expect(reset.frameAspectRatio, closeTo(2, 0.0001));
    expect(
        find.byKey(const Key('updates_media_crop_reset_button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '"Fit to screen" previews the real posted frame -- the crop window '
      'takes the full screen\'s shape, so a wide video shows the strip that '
      'will actually survive rather than pretending nothing is cropped',
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
          initialSourceSizeHint: Size(400, 200),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('updates_media_crop_rotate_button')),
    );
    await tester.tap(find.byKey(const Key('updates_media_crop_rotate_button')));
    await tester.pumpAndSettle();

    // The composer's media canvas is full-bleed, exactly like the viewer
    // renders a posted segment -- otherwise "fit to screen" would fit to a
    // shorter box than the screen it actually fills once posted.
    final canvasSize = tester.getSize(find.byType(StatusStoryMediaSurface));
    expect(canvasSize.height, closeTo(iphoneProProfile.size.height, 0.5));

    await tester.tap(
      find.byKey(const Key('updates_media_crop_aspect_ratio_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('updates_media_crop_aspect_Fit to screen')),
    );
    await tester.pumpAndSettle();

    final fitted = tester
        .widget<StatusStoryMediaSurface>(find.byType(StatusStoryMediaSurface))
        .mediaTransform;
    expect(fitted.frameAspectRatio, isNull);

    // A null frame ratio means "cover the whole canvas" in the posted
    // render, so the crop window must take the canvas's own shape -- not
    // fall back to the media's bounds and claim nothing gets cropped.
    final mediaBounds = statusMediaBoundsFor(canvasSize, 2);
    final window = cropWindowRectFor(
      mediaBounds,
      statusCropRatioFor(canvasSize, fitted.frameAspectRatio),
      fitted.scale,
      fitted.offsetDx,
      fitted.offsetDy,
    );

    expect(
      window.width / window.height,
      closeTo(canvasSize.width / canvasSize.height, 0.001),
      reason: 'fit to screen must preview the screen\'s own shape',
    );
    expect(
      window.width,
      lessThan(mediaBounds.width - 1),
      reason: 'a wide source really does lose its sides when it fills a '
          'tall screen -- the preview has to show that',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'neither the caption nor a placed text overlay is length-capped -- '
      'WhatsApp imposes no limit, so long text is handled by layout '
      '(wrapping, scrolling, show-more) rather than by refusing input',
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

    final captionField = find.byKey(const Key('updates_media_caption_field'));
    expect(captionField, findsOneWidget);
    expect(tester.widget<TextField>(captionField).maxLength, isNull);

    // A caption far past any previous cap is accepted verbatim.
    final longCaption = 'a very long caption. ' * 40;
    await tester.enterText(captionField, longCaption);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(captionField).controller?.text,
      longCaption,
    );

    // Same for the overlay's own text input.
    await tester.tap(find.byKey(const Key('updates_media_panel_fonts')));
    await tester.pumpAndSettle();

    final overlayField =
        find.byKey(const Key('updates_media_inline_text_field'));
    expect(overlayField, findsOneWidget);
    expect(tester.widget<TextField>(overlayField).maxLength, isNull);

    final longOverlayText = 'overlay words that keep going ' * 20;
    await tester.enterText(overlayField, longOverlayText);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(overlayField).controller?.text,
      longOverlayText,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'entering crop mode eases in rather than snapping -- the crop chrome '
      'and the toolbar cross-fade on the shared status timing', (tester) async {
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

    final cropOverlay =
        find.byKey(const Key('updates_media_crop_selection_overlay'));
    double overlayOpacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
              of: cropOverlay, matching: find.byType(AnimatedOpacity)),
        )
        .opacity;

    // Hidden, but present -- so it has something to animate from.
    expect(overlayOpacity(), 0);

    await tester.ensureVisible(
      find.byKey(const Key('updates_media_crop_rotate_button')),
    );
    await tester.tap(find.byKey(const Key('updates_media_crop_rotate_button')));

    // One frame in, the crop chrome is on its way in but not yet arrived:
    // the whole point of the change, versus popping to full opacity.
    await tester.pump();
    await tester.pump(kStatusMotionDuration ~/ 2);
    final midFade = tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.byKey(const Key('updates_media_crop_done_button')),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    expect(midFade, greaterThan(0));
    expect(midFade, lessThan(1));

    // And it settles fully within the shared duration.
    await tester.pumpAndSettle();
    expect(overlayOpacity(), 1);
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

    expect(
        find.byKey(const Key('updates_media_blur_editing_tray')), findsNothing);
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

  testWidgets(
      'the redesigned text tool (font row, color rail, top-bar icons, '
      'keyboard) renders without overflow on a compact iPhone SE screen',
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

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('updates_media_text_font_row')), findsOneWidget);
    expect(
        find.byKey(const Key('updates_media_text_color_rail')), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'iPhone SE should render the text tool without overflow or '
          'layout exceptions while the keyboard is up.',
    );
  });

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

    expect(
        find.byKey(const Key('updates_media_draw_editing_tray')), findsNothing);

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
    expect(
        surfaceAfterDraw.drawingStrokes.single.points.length, greaterThan(1));

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

    expect(find.byKey(const Key('updates_media_draw_surface')), findsOneWidget,
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

  testWidgets('dragging along the draw color bar picks a color partway down it',
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

  testWidgets(
      'a placed text overlay hugs its text instead of covering the canvas',
      (tester) async {
    const size = Size(393, 852);
    await tester.binding.setSurfaceSize(size);
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
    await tester.enterText(
      find.byKey(const Key('updates_media_inline_text_field')),
      'Trtttttt',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updates_media_text_done_button')));
    await tester.pumpAndSettle();

    final text = tester.getRect(find.text('Trtttttt').first);
    // The bordered shell inside the overlay. The overlay's own outermost
    // box is a Center and so always fills -- it is this container that
    // draws the selection border and takes the drag.
    final shell = tester.getRect(
      find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w.key.toString().contains('updates_overlay_item_'),
            ),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );

    // Padding around the glyphs, not the whole screen. Sized to the canvas
    // the border reads as a box drawn round the story, and the overlay
    // swallows every tap on it.
    expect(
      shell.width,
      lessThan(text.width + 60),
      reason: 'the overlay shell is far wider than its text',
    );
    expect(
      shell.height,
      lessThan(text.height + 60),
      reason: 'the overlay shell is far taller than its text',
    );
    expect(shell.width, lessThan(size.width));
    expect(shell.height, lessThan(size.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the colour rail stops above the styling rows instead of sitting on '
      'the weight button', (tester) async {
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

    await tester.tap(find.byKey(const Key('updates_media_panel_fonts')));
    await tester.pumpAndSettle();

    final rail =
        tester.getRect(find.byKey(const Key('updates_media_text_color_rail')));
    // Both rows the tray renders, not just the font row -- the rail
    // reserved a single row's height from when the tray had one, so its
    // lower stretch covered the weight button and would not take a drag.
    for (final key in <String>[
      'updates_media_text_weight_button',
      'updates_media_text_size_slider',
      'updates_media_text_font_row',
    ]) {
      expect(
        rail.overlaps(tester.getRect(find.byKey(Key(key)))),
        isFalse,
        reason: 'the colour rail sits on top of $key',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the draw tool hides the caption and share, the way the text and crop '
      'tools already do', (tester) async {
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

    expect(find.text('Add a caption...'), findsOneWidget);
    expect(
      find.byKey(const Key('updates_share_media_status_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('updates_media_draw_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Add a caption...'),
      findsNothing,
      reason: 'the caption still floats over the drawing canvas',
    );
    expect(
      find.byKey(const Key('updates_share_media_status_button')),
      findsNothing,
      reason: 'share still floats over the drawing canvas',
    );

    // And both come back when the tool is done.
    await tester.tap(find.byKey(const Key('updates_media_draw_done_button')));
    await tester.pumpAndSettle();
    expect(find.text('Add a caption...'), findsOneWidget);
    expect(
      find.byKey(const Key('updates_share_media_status_button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the caption field, send button, close and mute all sit on the same '
      'background as the tool capsule', (tester) async {
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

    // Every one of these renders through the shared surface. They used to
    // each pick their own fill -- a blurred glass here, a solid emerald
    // there -- so they read as different materials stacked on one screen.
    for (final key in <String>[
      'updates_media_caption_field',
      'updates_share_media_status_button',
      'updates_media_close_composer_button',
    ]) {
      final control = find.byKey(Key(key));
      expect(control, findsOneWidget, reason: '$key is missing');
      // Either direction: some of these carry their key on the surface's
      // wrapper, others on the control inside it.
      final onSurface = find
              .ancestor(of: control, matching: find.byType(StatusChromeSurface))
              .evaluate()
              .isNotEmpty ||
          find
              .descendant(
                  of: control, matching: find.byType(StatusChromeSurface))
              .evaluate()
              .isNotEmpty;
      expect(
        onSurface,
        isTrue,
        reason: '$key is not on the shared composer background',
      );
    }

    // And the surface really is the capsule's flat fill, not a blurred one.
    final surface = tester.widget<StatusChromeSurface>(
      find.byType(StatusChromeSurface).first,
    );
    final decoration = tester
        .widget<Container>(
          find
              .descendant(
                of: find.byWidget(surface),
                matching: find.byType(Container),
              )
              .first,
        )
        .decoration! as BoxDecoration;
    expect(decoration.color, StatusChromeSurface.fill);
    // The tool capsule itself is unblurred -- it sits over the scrim.
    // (The caption row and send do blur; see the crop/blur test.)
    expect(
      find.descendant(
        of: find.byKey(const Key('updates_media_panel_fonts')),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'adjacent chrome buttons share one capsule, and the sheets use the '
      'composer glass rather than a flat app panel', (tester) async {
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

    // Draw mode: undo and done sit together, not as two separate chips.
    await tester.tap(find.byKey(const Key('updates_media_draw_button')));
    await tester.pumpAndSettle();
    for (final key in <String>[
      'updates_media_draw_undo_button',
      'updates_media_draw_done_button',
    ]) {
      expect(
        find.ancestor(
          of: find.byKey(Key(key)),
          matching: find.byType(StatusChromeButtonGroup),
        ),
        findsOneWidget,
        reason: '$key is not grouped with the button beside it',
      );
    }
    await tester.tap(find.byKey(const Key('updates_media_draw_done_button')));
    await tester.pumpAndSettle();

    // The stickers/emoji sheet comes up on the composer's glass.
    await tester.tap(find.byKey(const Key('updates_media_add_emoji_button')));
    await tester.pumpAndSettle();
    expect(
      find.byType(StatusChromeSheet),
      findsOneWidget,
      reason: 'the sheet is still a flat app panel',
    );
    // Exactly one drag handle. The app theme turns Flutter's on globally
    // and it renders outside this sheet's glass, so the call site has to
    // switch it off or the sheet shows two bars.
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
      isFalse,
      reason: 'the sheet draws a second drag handle outside its glass',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the crop tool blurs behind its controls, since nothing scrims the '
      'media there', (tester) async {
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

    // The caption row and send blur behind themselves: a placed text
    // overlay can land right behind them, and they have to stay readable
    // against it.
    for (final key in <String>[
      'updates_media_caption_field',
      'updates_share_media_status_button',
    ]) {
      expect(
        find.ancestor(
          of: find.byKey(Key(key)),
          matching: find.byType(BackdropFilter),
        ),
        findsWidgets,
        reason: '$key does not separate itself from overlay text behind it',
      );
    }

    // The tool capsule does not -- it sits over the scrim, where a blur
    // only muddies it.
    expect(
      find.descendant(
        of: find.byKey(const Key('updates_media_panel_fonts')),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('updates_media_crop_rotate_button')));
    await tester.pumpAndSettle();

    for (final key in <String>[
      'updates_media_crop_cancel_button',
      'updates_media_crop_done_button',
      'updates_media_rotate_button',
      'updates_media_crop_aspect_ratio_button',
    ]) {
      // These keys sit on the wrapper, with the surface inside them, so
      // the blur is a descendant rather than an ancestor.
      expect(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(BackdropFilter),
        ),
        findsWidgets,
        reason: '$key sits unblurred straight on the media',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the music banner lands clear of the trim filmstrip so it can be '
      'dragged', (tester) async {
    const size = Size(393, 852);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const MediaStatusComposerScreen(
          type: StatusStoryType.video,
          localMediaPath: '/missing/video.mp4',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_media_add_music_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updates_media_music_option_0')));
    await tester.pumpAndSettle();

    // The shell that draws and takes the drag. The overlay's own outermost
    // box is a Center and always fills the canvas.
    final banner = tester.getRect(
      find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w.key.toString().contains('updates_overlay_item_music'),
            ),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );

    // Clear of the band the trim chrome occupies -- the tool row, the
    // duration label and the filmstrip. A banner dropped under the strip
    // cannot be dragged off it, because the strip takes the gesture.
    //
    // Asserted against the shared chrome constant rather than the strip
    // itself: the filmstrip needs a real video to render, so a test that
    // waited for it would simply never check anything.
    expect(
      banner.top,
      greaterThan(kStatusChromeReservedTop + 60),
      reason: 'the music banner landed under the trim filmstrip',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the crop tool shows the media alone, with no overlays on it',
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

    await tester.tap(find.byKey(const Key('updates_media_panel_fonts')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('updates_media_inline_text_field')),
      'Placed text',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updates_media_text_done_button')));
    await tester.pumpAndSettle();

    final overlays = find.byWidgetPredicate(
      (w) => w.key.toString().contains('updates_overlay_item_'),
    );
    expect(overlays, findsOneWidget);

    await tester.tap(find.byKey(const Key('updates_media_crop_rotate_button')));
    await tester.pumpAndSettle();

    // Long overlay text covers the frame, hiding what is being cropped and
    // getting in the way of the corner handles.
    expect(
      overlays,
      findsNothing,
      reason: 'overlays are still drawn over the crop tool',
    );

    // And they all come back on Done.
    await tester.tap(find.byKey(const Key('updates_media_crop_done_button')));
    await tester.pumpAndSettle();
    expect(overlays, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a selected text overlay draws no bounding box, while an emoji still '
      'does', (tester) async {
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

    await tester.tap(find.byKey(const Key('updates_media_panel_fonts')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('updates_media_inline_text_field')),
      'Placed text',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updates_media_text_done_button')));
    await tester.pumpAndSettle();

    Border? borderOf(String idFragment) {
      final shell = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byWidgetPredicate(
                (w) => w.key.toString().contains(idFragment),
              ),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      return (shell.decoration! as BoxDecoration).border as Border?;
    }

    // Select the text overlay.
    await tester.tap(find.text('Placed text').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Its box is clamped to the media frame, so on text taller than the
    // frame the border lands on the frame edges and reads as a crop
    // outline. Text never draws one.
    expect(
      borderOf('updates_overlay_item_')?.top.color,
      Colors.transparent,
      reason: 'a selected text overlay is drawing a bounding box',
    );
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
