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
      'shows the placement guide while editing text and hides it on background tap',
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

    expect(find.byKey(const Key('updates_media_overlay_guide')), findsNothing);

    await tester.tap(find.byKey(const Key('updates_media_panel_fonts')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('updates_media_overlay_guide')), findsOneWidget);
    final guideRect =
        tester.getRect(find.byKey(const Key('updates_media_overlay_guide')));
    expect(guideRect.top, greaterThan(60));

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

    await tester.tap(find.byKey(const Key('updates_media_emoji_option_0')));
    await tester.pumpAndSettle();

    final overlayFinder = find.byKey(const Key('updates_overlay_item_emoji-0'));
    expect(overlayFinder, findsOneWidget);
    final emojiFinder = find.text('🔥').last;

    final before = tester.getCenter(emojiFinder);
    await tester.drag(emojiFinder, const Offset(48, -36));
    await tester.pumpAndSettle();

    final after = tester.getCenter(emojiFinder);
    expect(after.dx, greaterThan(before.dx));
    expect(after.dy, lessThan(before.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps dragged overlays inside the preview-safe story area',
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

    await tester.tap(find.byKey(const Key('updates_media_emoji_option_0')));
    await tester.pumpAndSettle();

    final emojiFinder = find.text('🔥').last;
    await tester.drag(emojiFinder, const Offset(0, -480));
    await tester.pumpAndSettle();

    final emojiRect = tester.getRect(emojiFinder);
    expect(emojiRect.top, greaterThan(60));
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

    await tester.tap(find.byKey(const Key('updates_media_emoji_option_0')));
    await tester.pumpAndSettle();

    final overlayFinder = find.byKey(const Key('updates_overlay_item_emoji-0'));
    final deleteFinder =
        find.byKey(const Key('updates_media_delete_overlay_button'));
    final deleteVisibilityFinder =
        find.byKey(const Key('updates_media_delete_overlay_visibility'));
    final emojiFinder = find.text('🔥').last;
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
    await gesture.up();
    await tester.pumpAndSettle();

    expect(overlayFinder, findsNothing);
    expect(find.text('🔥'), findsNothing);
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

    await tester.tap(find.byKey(const Key('updates_media_emoji_option_0')));
    await tester.pumpAndSettle();

    var mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    final initialTransform = mediaSurface.mediaTransform;
    expect(mediaSurface.onScaleStart, isNull);
    expect(mediaSurface.onScaleUpdate, isNull);
    expect(mediaSurface.onScaleEnd, isNull);

    final emojiFinder = find.text('🔥').last;
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

    mediaSurface = tester.widget<StatusStoryMediaSurface>(
      find.byType(StatusStoryMediaSurface),
    );
    expect(mediaSurface.onScaleStart, isNotNull);
    expect(mediaSurface.onScaleUpdate, isNotNull);
    expect(mediaSurface.onScaleEnd, isNotNull);
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

    await tester.tap(find.byKey(const Key('updates_media_emoji_option_0')));
    await tester.pumpAndSettle();

    final emojiFinder = find.text('🔥').last;
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

  testWidgets('opens the inline frame tray and applies custom mode in place',
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

    await tester.tap(find.byKey(const Key('updates_media_frame_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('updates_media_frame_editing_tray')),
      findsOneWidget,
    );
    expect(find.text('Adjust frame'), findsNothing);
    expect(
      find.byKey(const Key('updates_media_rotate_button')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('updates_media_frame_option_custom')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('updates_media_frame_option_custom')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('updates_media_frame_custom_slider')),
      findsOneWidget,
    );
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

  testWidgets('lets the user cancel frame editing without closing the composer',
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

    await tester.tap(find.byKey(const Key('updates_media_frame_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('updates_media_frame_editing_tray')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('updates_media_done_frame_editing_button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('updates_done_frame_editing_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('updates_share_media_status_button')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('updates_media_cancel_frame_editing_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('updates_media_frame_editing_tray')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('updates_share_media_status_button')),
      findsOneWidget,
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
}
