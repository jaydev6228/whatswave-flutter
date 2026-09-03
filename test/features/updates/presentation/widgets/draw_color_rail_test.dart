import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/updates/presentation/widgets/draw_tools.dart';

const _white = Colors.white;
const _green = Color(0xFF34C759);

Future<void> _pumpRail(
  WidgetTester tester, {
  required Color selected,
  ValueChanged<Color>? onSelect,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme(),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            height: 400,
            child: DrawColorRail(
              keyPrefix: 'rail',
              selectedColor: selected,
              isEraserMode: false,
              onSelectColor: onSelect ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

double _thumbCentre(WidgetTester tester) =>
    tester.getCenter(find.byKey(const Key('rail_color_thumb'))).dy;

void main() {
  testWidgets('the thumb sits where the selected colour lives on the bar',
      (tester) async {
    // Its position used to be independent state starting at the top, so
    // anything that rebuilt the rail with a colour already chosen -- paging
    // to the next photo, re-entering draw mode -- left the thumb on white
    // while the pen drew green.
    await _pumpRail(tester, selected: _white);
    final atWhite = _thumbCentre(tester);

    await _pumpRail(tester, selected: _green);
    final atGreen = _thumbCentre(tester);

    expect(atGreen, greaterThan(atWhite + 100));
  });

  testWidgets('a colour chosen elsewhere moves the thumb', (tester) async {
    await _pumpRail(tester, selected: _white);
    final before = _thumbCentre(tester);

    // Same widget, rebuilt with a different colour -- the didUpdateWidget
    // path, which is the one paging a photo actually takes.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              height: 400,
              child: DrawColorRail(
                keyPrefix: 'rail',
                selectedColor: _green,
                isEraserMode: false,
                onSelectColor: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_thumbCentre(tester), greaterThan(before + 100));
  });

  testWidgets('dragging shows a preview swatch clear of the finger',
      (tester) async {
    Color? picked;
    await _pumpRail(tester, selected: _white, onSelect: (c) => picked = c);

    // Nothing to preview until a finger is down.
    expect(find.byKey(const Key('rail_color_preview')), findsNothing);

    final bar = tester.getRect(find.byKey(const Key('rail_color_bar')));
    final gesture = await tester.startGesture(Offset(bar.center.dx, bar.top + 8));
    // Several moves, not one: a single move inside the touch slop never
    // becomes a drag, so onVerticalDragStart would not fire at all.
    for (var step = 1; step <= 4; step++) {
      await gesture.moveTo(
        Offset(bar.center.dx, bar.top + 8 + bar.height * 0.1 * step),
      );
      await tester.pump();
    }

    expect(find.byKey(const Key('rail_color_preview')), findsOneWidget);
    // Clear of the rail, not under the hand choosing the colour.
    expect(
      tester.getRect(find.byKey(const Key('rail_color_preview'))).right,
      lessThanOrEqualTo(bar.left + 1),
    );
    expect(picked, isNotNull);

    await gesture.up();
    await tester.pump();
    expect(find.byKey(const Key('rail_color_preview')), findsNothing);
  });
}
