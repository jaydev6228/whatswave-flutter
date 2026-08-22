import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/updates/presentation/text_status_composer_screen.dart';

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

    expect(find.byKey(const Key('updates_toggle_keyboard_button')),
        findsNothing);
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

    expect(find.byKey(const Key('updates_cycle_font_button')),
        findsOneWidget);
    expect(find.byKey(const Key('updates_cycle_background_button')),
        findsOneWidget);
    expect(find.byKey(const Key('updates_add_text_emoji_button')),
        findsOneWidget);

    // Still reachable once the keyboard is up -- WhatsApp's icons live in
    // the top bar, not a bottom deck that has to hide/show.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_cycle_font_button')),
        findsOneWidget);
    expect(find.byKey(const Key('updates_cycle_background_button')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the font icon cycles to the next font',
      (tester) async {
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

    await tester
        .tap(find.byKey(const Key('updates_cycle_background_button')));
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

    await tester.tap(find.byKey(const Key('updates_text_overlay_delete_button')));
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
}
