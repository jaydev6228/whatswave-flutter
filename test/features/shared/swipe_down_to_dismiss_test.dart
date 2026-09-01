import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/shared/swipe_down_to_dismiss.dart';

void main() {
  Future<void> pushViewer(WidgetTester tester, {bool enabled = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: SwipeDownToDismiss(
                      enabled: enabled,
                      child: const SizedBox.expand(
                        child: Text('viewer'),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('viewer'), findsOneWidget);
  }

  testWidgets('a long downward drag dismisses the viewer', (tester) async {
    await pushViewer(tester);

    await tester.drag(find.text('viewer'), const Offset(0, 200));
    await tester.pumpAndSettle();

    expect(find.text('viewer'), findsNothing);
  });

  testWidgets('a short drag springs back instead of dismissing',
      (tester) async {
    await pushViewer(tester);

    // Well under kSwipeDismissDistance, released slowly so velocity cannot
    // carry it either.
    await tester.timedDrag(
      find.text('viewer'),
      const Offset(0, 40),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();

    expect(find.text('viewer'), findsOneWidget);
    // Back at rest, not left hanging part-way down.
    expect(tester.getTopLeft(find.text('viewer')).dy, 0);
  });

  testWidgets('a fast downward flick dismisses even over a short distance',
      (tester) async {
    await pushViewer(tester);

    await tester.fling(find.text('viewer'), const Offset(0, 60), 2000);
    await tester.pumpAndSettle();

    expect(find.text('viewer'), findsNothing);
  });

  testWidgets('dragging upward never dismisses and never lifts the child',
      (tester) async {
    await pushViewer(tester);

    await tester.drag(find.text('viewer'), const Offset(0, -300));
    await tester.pump();

    expect(find.text('viewer'), findsOneWidget);
    expect(tester.getTopLeft(find.text('viewer')).dy, 0);
  });

  testWidgets('disabled, the gesture is inert', (tester) async {
    await pushViewer(tester, enabled: false);

    await tester.drag(find.text('viewer'), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(find.text('viewer'), findsOneWidget);
  });

  testWidgets('a horizontal drag is left to whatever pages sideways',
      (tester) async {
    await pushViewer(tester);

    await tester.drag(find.text('viewer'), const Offset(300, 0));
    await tester.pumpAndSettle();

    expect(find.text('viewer'), findsOneWidget);
  });
}
