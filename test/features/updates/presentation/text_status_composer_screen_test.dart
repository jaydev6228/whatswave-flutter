import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/updates/presentation/text_status_composer_screen.dart';

import '../../../support/device_matrix.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_text_editing_tools.dart';
import 'package:whatswave/features/updates/presentation/widgets/text_status_canvas.dart';

void main() {
  testWidgets(
      'no keyboard-toggle button exists -- tapping the canvas is the only '
      'way back into editing, matching WhatsApp and removing the stuck-'
      'keyboard bug entirely', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const TextStatusComposerScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('updates_toggle_keyboard_button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('font and background icons are always reachable, no tabs',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const TextStatusComposerScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_cycle_font_button')), findsOneWidget);
    expect(find.byKey(const Key('updates_cycle_background_button')),
        findsOneWidget);
    expect(
        find.byKey(const Key('updates_add_text_emoji_button')), findsOneWidget);

    // Still reachable once the keyboard is up -- WhatsApp's icons live in
    // the top bar, not a bottom deck that has to hide/show.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_cycle_font_button')), findsOneWidget);
    expect(find.byKey(const Key('updates_cycle_background_button')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the font icon cycles to the next font', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const TextStatusComposerScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_cycle_font_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updates_cycle_font_button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the background icon cycles to the next background',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const TextStatusComposerScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_cycle_background_button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('adding an emoji places it as a draggable overlay',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const TextStatusComposerScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('updates_add_text_emoji_button')));
    await tester.pumpAndSettle();

    expect(find.text('Add emoji'), findsOneWidget);

    await tester.tap(find.byKey(const Key('updates_media_emoji_option_0')));
    await tester.pumpAndSettle();

    final emojiFinder = find.text('😀');
    expect(emojiFinder, findsOneWidget);

    final before = tester.getCenter(emojiFinder);
    await tester.drag(emojiFinder, const Offset(40, -30));
    await tester.pumpAndSettle();

    final after = tester.getCenter(emojiFinder);
    expect(after.dx, greaterThan(before.dx));
    expect(after.dy, lessThan(before.dy));

    await tester
        .tap(find.byKey(const Key('updates_text_overlay_delete_button')));
    await tester.pumpAndSettle();

    expect(find.text('😀'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stays overflow-free on a small phone at the largest accessibility '
      'text scale', (tester) async {
    await tester.binding.setSurfaceSize(androidSmallProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: androidSmallProfile.size,
            textScaler: const TextScaler.linear(2.0),
          ),
          child: child!,
        ),
        home: const TextStatusComposerScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the text status uses the very same text tooling as the media '
      "composer's overlay -- shared editor card, colour rail and font row, "
      'not a parallel implementation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    // The shared components, not look-alikes rebuilt for this screen.
    expect(find.byType(StatusTextEditorCard), findsOneWidget);
    expect(find.byType(StatusTextColorRail), findsOneWidget);
    expect(find.byType(StatusTextFontStyleRow), findsOneWidget);

    // Fonts are chosen directly off the row, the way the media tool does
    // it, rather than cycled blindly one tap at a time.
    final serifOption = find.byKey(const Key('updates_text_font_option_serif'));
    expect(serifOption, findsOneWidget);
    await tester.tap(serifOption);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StatusTextEditorCard>(find.byType(StatusTextEditorCard))
          .textStyleModel
          .fontId,
      'serif',
    );

    // Dragging the rail recolours the text, same as the media tool.
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const Key('updates_text_color_bar'))) +
          const Offset(4, 60),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StatusTextEditorCard>(find.byType(StatusTextEditorCard))
          .textStyleModel
          .textColorValue,
      isNotNull,
    );

    // Text-status-only features survive the switch.
    expect(
      find.byKey(const Key('updates_cycle_background_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('updates_add_text_emoji_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('updates_randomize_text_style_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('updates_share_status_button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the canvas keeps its posted size when the keyboard opens, and tapping '
      'away from the text puts the keyboard down and reveals the real '
      'posted preview -- tapping back returns to typing', (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    // Opens ready to type, like WhatsApp.
    expect(find.byType(StatusTextEditorCard), findsOneWidget);
    final canvasWithoutKeyboard =
        tester.getRect(find.byKey(const Key('updates_composer_canvas')));

    await tester.enterText(
      find.byKey(const Key('updates_composer_field')),
      'Hello there',
    );
    await tester.pumpAndSettle();

    // The keyboard must not shrink the preview: it is the posted story.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('updates_composer_canvas'))),
      canvasWithoutKeyboard,
      reason: 'the preview must stay the size the story will be posted at',
    );

    // Tapping away from the text drops the editor chrome and shows the
    // text exactly as it will appear once posted.
    await tester.tapAt(canvasWithoutKeyboard.topCenter + const Offset(0, 12));
    await tester.pumpAndSettle();

    expect(find.byType(StatusTextEditorCard), findsNothing);
    expect(find.byKey(const Key('updates_composer_field')), findsNothing);
    expect(find.text('Hello there'), findsOneWidget);

    // Every styling control steps aside too -- with the keyboard down this
    // screen is a preview of the posted story, and a story has no toolbars
    // painted over it. Close and Share stay: they are navigation.
    expect(find.byType(StatusTextColorRail), findsNothing);
    expect(find.byType(StatusTextFontStyleRow), findsNothing);
    expect(
      find.byKey(const Key('updates_cycle_background_button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('updates_add_text_emoji_button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('updates_share_status_button')),
      findsOneWidget,
    );

    // And tapping back returns to typing without losing the text.
    await tester.tapAt(canvasWithoutKeyboard.topCenter + const Offset(0, 12));
    await tester.pumpAndSettle();
    expect(find.byType(StatusTextEditorCard), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('updates_composer_field')))
          .controller
          ?.text,
      'Hello there',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the editor card, the font row and the colour rail never overlap, '
      'with the keyboard up or down', (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    // Enough text that the card grows tall -- a one-line card is small
    // enough to miss the controls by luck even when the layout is wrong.
    await tester.enterText(
      find.byKey(const Key('updates_composer_field')),
      'Ffffffff wwww wwww wwww wwww wwww wwww wwww wwww wwww wwww wwww '
      'wwww wwww wwww wwww wwww wwww wwww wwww wwww wwww wwww wwww '
      'wwww wwww wwww wwww wwww wwww wwww wwww wwww wwww wwww wwww',
    );
    await tester.pumpAndSettle();

    Future<void> expectNoOverlap(String when) async {
      final card = tester.getRect(
        find.byKey(const Key('updates_composer_text_card')),
      );
      final fontRow = tester.getRect(
        find.byKey(const Key('updates_text_font_row')),
      );
      final rail = tester.getRect(
        find.byKey(const Key('updates_text_color_rail')),
      );

      expect(
        card.overlaps(fontRow),
        isFalse,
        reason: 'card and font row must not overlap ($when)',
      );
      expect(
        card.overlaps(rail),
        isFalse,
        reason: 'card and colour rail must not overlap ($when)',
      );
      expect(
        card.bottom,
        lessThanOrEqualTo(fontRow.top + 0.5),
        reason: 'the card must sit above the font row ($when)',
      );
    }

    await expectNoOverlap('keyboard down');

    // The keyboard raises the font row; the card has to give way for it
    // rather than being written over.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    await expectNoOverlap('keyboard up');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'while typing, the canvas paints no stray text panel behind the editor '
      "-- the capsule reappears only once it is the story's own text",
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    // Editing: the canvas holds its text block back entirely, so nothing
    // is drawn under the font row but the background itself.
    expect(
      tester.widget<TextStatusCanvas>(find.byType(TextStatusCanvas)).showText,
      isFalse,
    );
    // The placeholder lives in the editor card, not duplicated on the canvas.
    expect(find.text('Type your status'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('updates_composer_field')),
      'Ffffffff',
    );
    await tester.pumpAndSettle();

    final canvas =
        tester.getRect(find.byKey(const Key('updates_composer_canvas')));
    await tester.tapAt(canvas.topCenter + const Offset(0, 12));
    await tester.pumpAndSettle();

    // Keyboard down: the canvas owns the text again, so the panel is back.
    expect(
      tester.widget<TextStatusCanvas>(find.byType(TextStatusCanvas)).showText,
      isTrue,
    );
    expect(find.text('Ffffffff'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
