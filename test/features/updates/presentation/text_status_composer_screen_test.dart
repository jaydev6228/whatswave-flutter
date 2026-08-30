import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/presentation/text_status_composer_screen.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_chrome.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_text_editing_tools.dart';
import 'package:whatswave/features/updates/presentation/widgets/text_status_canvas.dart';

import '../../../support/device_matrix.dart';

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

    // The sheet carries no title -- the button that opened it already
    // said what it is -- so the grid is what proves it opened.
    expect(
        find.byKey(const Key('updates_media_emoji_option_0')), findsOneWidget);

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
    // Bare canvas: below the editor card, above the font row -- the gap a
    // real "tap away from the text" lands in.
    final cardRect = tester.getRect(find.byType(StatusTextEditorCard));
    await tester.tapAt(
      Offset(canvasWithoutKeyboard.center.dx, cardRect.bottom + 20),
    );
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
    await tester.tapAt(
      Offset(canvasWithoutKeyboard.center.dx, cardRect.bottom + 20),
    );
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
    await tester.tapAt(Offset(canvas.center.dx, canvas.bottom - 140));
    await tester.pumpAndSettle();

    // Keyboard down: the canvas owns the text again, so the panel is back.
    expect(
      tester.widget<TextStatusCanvas>(find.byType(TextStatusCanvas)).showText,
      isTrue,
    );
    expect(find.text('Ffffffff'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the editor renders in the posted style -- same font size while typing '
      'as after the keyboard goes down', (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('updates_composer_field')),
      'Dxxdxdddd',
    );
    await tester.pumpAndSettle();

    final editingSize = tester
        .widget<TextField>(find.byKey(const Key('updates_composer_field')))
        .style
        ?.fontSize;
    expect(editingSize, isNotNull);

    final cardRect = tester.getRect(find.byType(StatusTextEditorCard));
    await tester.tapAt(Offset(cardRect.center.dx, cardRect.bottom + 20));
    await tester.pumpAndSettle();

    final postedSize =
        tester.widget<Text>(find.text('Dxxdxdddd')).style?.fontSize;
    expect(postedSize, isNotNull);
    expect(
      editingSize,
      closeTo(postedSize!, 0.5),
      reason: 'typing and the posted story must use one size',
    );
  });

  testWidgets(
      'size and weight controls change the posted text, and weight beats the '
      "font look's own default", (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('updates_composer_field')),
      'Sized',
    );
    await tester.pumpAndSettle();

    TextStyle? editorStyle() => tester
        .widget<TextField>(find.byKey(const Key('updates_composer_field')))
        .style;

    final beforeSize = editorStyle()?.fontSize;
    final beforeWeight = editorStyle()?.fontWeight;

    // Drag the size slider up.
    await tester.drag(
      find.byKey(const Key('updates_text_size_slider')),
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();
    expect(editorStyle()?.fontSize, greaterThan(beforeSize!));

    // Cycle the weight round to the lightest option. Deliberately not just
    // one tap: the next weight up happens to match what some font looks
    // apply themselves, so a single step cannot tell "the user's choice
    // won" apart from "the look's default happened to agree".
    await tester.tap(find.byKey(const Key('updates_text_weight_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updates_text_weight_button')));
    await tester.pumpAndSettle();
    final afterWeight = editorStyle()?.fontWeight;
    expect(afterWeight, isNot(beforeWeight));
    expect(afterWeight, kStatusTextFontWeights.first);

    // Both survive into the posted rendering.
    final cardRect = tester.getRect(find.byType(StatusTextEditorCard));
    await tester.tapAt(Offset(cardRect.center.dx, cardRect.bottom + 20));
    await tester.pumpAndSettle();

    final posted = tester.widget<Text>(find.text('Sized')).style;
    expect(posted?.fontWeight, afterWeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the size slider reaches genuinely small text -- the bottom of the '
      'track lands on the 10pt floor rather than being clamped away',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('updates_composer_field')),
      'Tiny',
    );
    await tester.pumpAndSettle();

    // Drag the slider hard to the left -- the smallest size on offer.
    final slider = find.byKey(const Key('updates_text_size_slider'));
    await tester.drag(slider, const Offset(-500, 0));
    await tester.pumpAndSettle();

    final editorSize = tester
        .widget<TextField>(find.byKey(const Key('updates_composer_field')))
        .style
        ?.fontSize;
    expect(
      editorSize,
      closeTo(kStatusTextMinFontSize, 0.5),
      reason: 'the slider floor must actually reach 10pt',
    );

    // And it survives into the posted rendering, not just the editor.
    final cardRect = tester.getRect(find.byType(StatusTextEditorCard));
    await tester.tapAt(Offset(cardRect.center.dx, cardRect.bottom + 20));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text('Tiny')).style?.fontSize,
      closeTo(kStatusTextMinFontSize, 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the colour rail clears the top chrome, so its whole track is '
      'draggable rather than the top being swallowed by Share', (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    final rail =
        tester.getRect(find.byKey(const Key('updates_text_color_rail')));
    final share =
        tester.getRect(find.byKey(const Key('updates_share_status_button')));
    expect(
      rail.overlaps(share),
      isFalse,
      reason: 'Share sits on top of the rail and wins the hit test there',
    );

    // The very top of the track responds: a drag there really recolours.
    final bar = tester.getRect(find.byKey(const Key('updates_text_color_bar')));
    await tester.tapAt(Offset(bar.center.dx, bar.top + 2));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StatusTextEditorCard>(find.byType(StatusTextEditorCard))
          .textStyleModel
          .textColorValue,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'styling buttons restyle without ending editing -- shuffling the look '
      'keeps the keyboard and the editor exactly where they were',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('updates_composer_field')),
      'Keep me',
    );
    await tester.pumpAndSettle();
    expect(find.byType(StatusTextEditorCard), findsOneWidget);

    for (final key in <String>[
      'updates_randomize_text_style_button',
      'updates_cycle_background_button',
      'updates_cycle_font_button',
      'updates_text_decoration_button',
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      expect(
        find.byType(StatusTextEditorCard),
        findsOneWidget,
        reason: '$key must not end editing',
      );
      expect(
        find.byKey(const Key('updates_composer_field')),
        findsOneWidget,
        reason: '$key must keep the text field',
      );
    }

    // The text survived all of it.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('updates_composer_field')))
          .controller
          ?.text,
      'Keep me',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'shuffling keeps a deliberately picked text colour, and the rail thumb '
      'never disagrees with the colour actually rendered', (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    // Pick a colour partway down the rail.
    final bar = tester.getRect(find.byKey(const Key('updates_text_color_bar')));
    await tester.tapAt(Offset(bar.center.dx, bar.top + bar.height * 0.55));
    await tester.pumpAndSettle();

    StatusTextStyle model() => tester
        .widget<StatusTextEditorCard>(find.byType(StatusTextEditorCard))
        .textStyleModel;

    final picked = model().textColorValue;
    expect(picked, isNotNull);

    await tester.tap(
      find.byKey(const Key('updates_randomize_text_style_button')),
    );
    await tester.pumpAndSettle();

    // The chosen colour survives the shuffle rather than snapping back.
    expect(
      model().textColorValue,
      picked,
      reason: 'shuffle changes the look, not choices the user made',
    );

    // And the thumb still shows the colour actually being rendered -- the
    // give-away of the old bug was a green thumb over white text.
    final rail = tester.widget<StatusTextColorRail>(
      find.byType(StatusTextColorRail),
    );
    expect(rail.selectedColor, model().textColor);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rail thumb follows a colour set from outside the rail',
      (tester) async {
    // Derived, not independently held: a thumb keeping its own position
    // sits on a stale colour the moment anything else sets one.
    const green = Color(0xFF34C759);
    final position = statusTextBarPositionForColor(green);
    expect(position, greaterThan(0));
    expect(
      statusTextColorForBarPosition(position),
      green,
      reason: 'the mapping must round-trip an exact stop colour',
    );
  });

  testWidgets(
      'the editor starts as bare text -- no outline, no plate -- and the fill '
      'button is what adds a background when the user wants one',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    InputDecoration decoration() => tester
        .widget<TextField>(find.byKey(const Key('updates_composer_field')))
        .decoration!;

    // No outline in any state -- the theme's focusedBorder used to draw a
    // green ring around the text the moment the field took focus.
    expect(decoration().border, InputBorder.none);
    expect(decoration().focusedBorder, InputBorder.none);
    expect(decoration().enabledBorder, InputBorder.none);

    // The placeholder wraps instead of running off the edge.
    expect(decoration().hintMaxLines, isNotNull);
    expect(decoration().hintMaxLines, greaterThan(1));

    BoxDecoration cardDecoration() => tester
        .widget<Container>(
          find.descendant(
            of: find.byType(StatusTextEditorCard),
            matching: find.byKey(const Key('updates_composer_text_card')),
          ),
        )
        .decoration! as BoxDecoration;

    // Transparent to begin with.
    expect(cardDecoration().color, Colors.transparent);

    // The existing fill button is the opt-in -- no new control needed.
    await tester.tap(find.byKey(const Key('updates_text_decoration_button')));
    await tester.pumpAndSettle();

    final filled = cardDecoration().color;
    expect(filled, isNotNull);
    expect(
      filled!.a,
      greaterThan(0),
      reason: 'the fill button must actually put a plate behind the text',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'no plate appears behind the text just because the keyboard went down '
      '-- the fill control is the only thing that adds one', (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('updates_composer_field')),
      'Plate check',
    );
    await tester.pumpAndSettle();

    final cardRect = tester.getRect(find.byType(StatusTextEditorCard));
    Future<void> toggleEditing() async {
      await tester.tapAt(Offset(cardRect.center.dx, cardRect.bottom + 20));
      await tester.pumpAndSettle();
    }

    // Anything painting a visible fill directly around the posted text.
    bool textHasPlate() => tester
            .widgetList<Container>(
          find.ancestor(
            of: find.text('Plate check'),
            matching: find.byType(Container),
          ),
        )
            .any((container) {
          final decoration = container.decoration;
          return decoration is BoxDecoration && (decoration.color?.a ?? 0) > 0;
        });

    await toggleEditing();
    expect(
      textHasPlate(),
      isFalse,
      reason: 'the editor showed bare text, so the preview must too',
    );

    // Fill is the opt-in, and it reaches the posted rendering.
    await toggleEditing();
    await tester.tap(find.byKey(const Key('updates_text_decoration_button')));
    await tester.pumpAndSettle();
    await toggleEditing();

    expect(textHasPlate(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the editor card hugs its text, so tapping beside a short status '
      'dismisses the keyboard instead of landing on an oversized card',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('updates_composer_field')),
      'R',
    );
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byType(StatusTextEditorCard));
    final style = tester
        .widget<TextField>(find.byKey(const Key('updates_composer_field')))
        .style!;
    final glyph = TextPainter(
      text: TextSpan(text: 'R', style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    // Padding only -- not the width of the whole editing area. A TextField
    // takes every pixel offered, which is what made a one-letter status
    // swallow taps across the canvas.
    expect(
      card.width,
      lessThan(glyph.width + 40),
      reason: 'the card must hug the text, not fill the row',
    );
    expect(card.height, lessThan(glyph.height + 40));
    glyph.dispose();

    // So a tap just beside the letter reaches the canvas and dismisses.
    await tester.tapAt(Offset(card.right + 40, card.center.dy));
    await tester.pumpAndSettle();

    expect(find.byType(StatusTextEditorCard), findsNothing);
    expect(find.text('R'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the send button is pinned to the bottom like the media composer and '
      'does not ride up with the keyboard', (tester) async {
    final size = iphoneProProfile.size;
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    Rect sendButton() =>
        tester.getRect(find.byKey(const Key('updates_share_status_button')));

    // Bottom-right, not a label in the top chrome where it had to survive
    // on top of whatever background the user picked.
    final editing = sendButton();
    expect(editing.right, closeTo(size.width - 16, 1));
    expect(editing.bottom, closeTo(size.height - 16, 1));
    // A real tap target, not a text label.
    expect(editing.width, greaterThanOrEqualTo(44));
    expect(editing.height, greaterThanOrEqualTo(44));

    // It clears every control that shares the bottom of the screen rather
    // than sitting on top of them.
    for (final other in <String>[
      'updates_text_font_row',
      'updates_text_size_slider',
      'updates_text_color_rail',
    ]) {
      expect(
        editing.overlaps(tester.getRect(find.byKey(Key(other)))),
        isFalse,
        reason: '$other sits under the send button',
      );
    }

    // Dismissing the keyboard removes the styling rows -- the button must
    // not move, so it never floats mid-story with the preview behind it.
    await tester.tapAt(Offset(size.width / 2, size.height * 0.25));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('updates_text_font_row')), findsNothing);

    expect(
      sendButton(),
      editing,
      reason: 'the send button moved when the styling rows went away',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'every floating chrome button is the shared glass button both '
      'composers use, at a 44pt tap target', (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    // Close plus the five styling tools. Bare IconButtons put naked glyphs
    // straight onto the background with nothing behind them; the media
    // composer never did that, and now neither does this one.
    for (final key in <String>[
      'updates_close_composer_button',
      'updates_cycle_font_button',
      'updates_text_decoration_button',
      'updates_cycle_background_button',
      'updates_add_text_emoji_button',
      'updates_randomize_text_style_button',
    ]) {
      final button = find.byKey(Key(key));
      expect(
        button,
        findsOneWidget,
        reason: '$key is missing from the chrome',
      );
      expect(
        tester.widget(button),
        isA<StatusChromeButton>(),
        reason: '$key is not the shared glass button',
      );
      // Floor guard rather than a fix for anything: Material already
      // expands these to 48x48. It catches a future change that wraps or
      // shrinks them below the platform minimum.
      expect(
        tester.getRect(button).shortestSide,
        greaterThanOrEqualTo(44),
        reason: '$key is under the 44pt minimum tap target',
      );
    }

    // Even on the narrowest phone they all fit without overflow.
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cycling the background colour keeps the text plate the user turned on',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    StatusTextStyle currentStyle() => tester
        .widget<StatusTextEditorCard>(find.byType(StatusTextEditorCard))
        .textStyleModel;

    expect(currentStyle().useSolidBackground, isFalse);

    // Turn the plate on with the fill button.
    await tester.tap(find.byKey(const Key('updates_text_decoration_button')));
    await tester.pumpAndSettle();
    expect(currentStyle().useSolidBackground, isTrue);

    // Then pick a different background colour. Only the canvas should
    // change -- the plate is a separate choice and must survive.
    final before = currentStyle().backgroundId;
    await tester.tap(find.byKey(const Key('updates_cycle_background_button')));
    await tester.pumpAndSettle();

    expect(currentStyle().backgroundId, isNot(before));
    expect(
      currentStyle().useSolidBackground,
      isTrue,
      reason: 'cycling the background switched the text plate off',
    );

    // And again, to be sure it is not just the first cycle that spares it.
    await tester.tap(find.byKey(const Key('updates_cycle_background_button')));
    await tester.pumpAndSettle();
    expect(currentStyle().useSolidBackground, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the editor card is tall enough for descenders under every font look, '
      'so typed text is never sliced off', (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    // "Ggg" -- a cap plus two descenders, the case that showed the bug.
    await tester.enterText(
      find.byKey(const Key('updates_composer_field')),
      'Ggg',
    );
    await tester.pumpAndSettle();

    for (final look in kTextStatusFontLooks) {
      // The row scrolls horizontally, so the later looks start off-screen;
      // tapping blind there misses and drops the keyboard instead.
      final option = find.byKey(Key('updates_text_font_option_${look.id}'));
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();

      expect(
        find.byType(StatusTextEditorCard),
        findsOneWidget,
        reason: 'picking the ${look.id} look ended editing',
      );
      // The field's own box, not the card's: the card adds vertical
      // padding that masks a short field, but it is the field that scrolls
      // and therefore clips.
      final field =
          tester.getRect(find.byKey(const Key('updates_composer_field')));
      final style = tester
          .widget<TextField>(find.byKey(const Key('updates_composer_field')))
          .style!;
      // Lay the same text out with the look's `height` multiplier removed,
      // so the face's own metrics decide the box. That is the real extent
      // of the ink; a multiplier under the natural ratio (cinema 0.92,
      // impact 0.94) makes the styled box shorter than it, and the card
      // clips the difference.
      final natural = TextPainter(
        text: TextSpan(
          text: 'Ggg',
          style: TextStyle(
            fontFamily: style.fontFamily,
            fontFamilyFallback: style.fontFamilyFallback,
            fontSize: style.fontSize,
            fontWeight: style.fontWeight,
            fontStyle: style.fontStyle,
            letterSpacing: style.letterSpacing,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final ink = natural.height;
      natural.dispose();

      expect(
        field.height,
        // Half-point slack: the widget probes the face with a fixed glyph
        // set so the card does not jitter as you type, and that differs
        // from this text by hundredths of a point.
        greaterThanOrEqualTo(ink - 0.5),
        reason: 'the ${look.id} look clips its descenders',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the send button reads as disabled until there is text to send',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();

    double sendOpacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byKey(const Key('updates_share_status_button')),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    // Empty status: the button is inert, so it must not look live.
    expect(sendOpacity(), lessThan(1));

    await tester.enterText(
      find.byKey(const Key('updates_composer_field')),
      'Hello',
    );
    await tester.pumpAndSettle();
    expect(sendOpacity(), 1);

    // Whitespace alone is still nothing to send.
    await tester.enterText(
      find.byKey(const Key('updates_composer_field')),
      '   ',
    );
    await tester.pumpAndSettle();
    expect(sendOpacity(), lessThan(1));
    expect(tester.takeException(), isNull);
  });
}
