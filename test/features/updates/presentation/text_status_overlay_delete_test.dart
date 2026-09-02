import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/presentation/text_status_composer_screen.dart';
import 'package:whatswave/features/updates/presentation/widgets/overlay_delete_target.dart';

void main() {
  const deleteTarget = Key('updates_text_delete_overlay_button');

  Future<void> pumpComposer(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: TextStatusComposerScreen()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> addEmoji(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('updates_add_text_emoji_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updates_media_emoji_option_0')));
    await tester.pumpAndSettle();
  }

  testWidgets('the delete target is the same one the media composer uses',
      (tester) async {
    await pumpComposer(tester);
    await addEmoji(tester);

    // Present but hidden until a drag starts -- so it has something to
    // animate in from, and never sits over the story unprompted.
    expect(find.byType(StatusOverlayDeleteTarget), findsOneWidget);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.byKey(deleteTarget),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity,
      0,
    );
  });

  testWidgets('dragging an emoji onto the target removes it', (tester) async {
    await pumpComposer(tester);
    await addEmoji(tester);

    double opacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byKey(deleteTarget),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    final emoji = find.byKey(const Key('updates_text_overlay_resize_handle'));
    expect(emoji, findsOneWidget, reason: 'the emoji was never added');

    // Drag it down onto the target. The text composer previously offered
    // only the small badge on a selected item -- a different interaction
    // from the media composer's drag target for the same job.
    final start = tester.getCenter(find.byType(StatusOverlayDeleteTarget));
    // A new emoji lands at 0.5 x 0.3 of the canvas, so the drag has to begin
    // there rather than at the screen's centre.
    final screen = tester.getRect(find.byType(TextStatusComposerScreen));
    final gesture = await tester.startGesture(
      Offset(screen.center.dx, screen.top + screen.height * 0.3),
    );
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await gesture.moveTo(
        Offset(start.dx, start.dy - 120 + (i + 1) * 30),
      );
      await tester.pump();
    }
    expect(opacity(), 1, reason: 'the target never appeared while dragging');

    await gesture.moveTo(start);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(emoji, findsNothing, reason: 'the emoji was not deleted');
  });

  testWidgets('a selected emoji offers a resize handle, not a close badge',
      (tester) async {
    await pumpComposer(tester);
    await addEmoji(tester);

    // Deleting is the drag-to-target gesture now, so the item itself only
    // needs the affordance that was missing: something to grab and resize.
    expect(
      find.byKey(const Key('updates_text_overlay_resize_handle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('updates_text_overlay_delete_button')),
      findsNothing,
    );
  });

  testWidgets('dragging the handle outward grows the emoji', (tester) async {
    await pumpComposer(tester);
    await addEmoji(tester);

    final handle = find.byKey(const Key('updates_text_overlay_resize_handle'));
    final before = tester.getRect(handle);

    await tester.drag(handle, const Offset(60, 60));
    await tester.pumpAndSettle();

    // The handle rides the item's scale, so it moving further from centre
    // is the item having grown.
    expect(
      tester.getRect(handle).center.dx,
      greaterThan(before.center.dx),
      reason: 'the emoji did not grow',
    );
  });
}
