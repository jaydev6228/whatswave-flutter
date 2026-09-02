import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/presentation/status_motion.dart';

void main() {
  // A column of [switcher, marker] -- exactly the shape the media composer's
  // top chrome uses, where the trim filmstrip sits directly beneath the
  // switching toolbar. The marker stands in for that filmstrip.
  Widget harness(double childHeight) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusModeSwitcher(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    key: ValueKey(childHeight),
                    height: childHeight,
                    width: 200,
                  ),
                ),
                const SizedBox(
                  key: Key('marker'),
                  height: 10,
                  width: 200,
                ),
              ],
            ),
          ),
        ),
      );

  double markerTop(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(const Key('marker'))).dy;

  testWidgets('siblings below do not shift while a taller child fades out',
      (tester) async {
    await tester.pumpWidget(harness(60));
    await tester.pumpAndSettle();
    final tallMarker = markerTop(tester);

    // Switch to a shorter child, as leaving the text tool does.
    await tester.pumpWidget(harness(40));
    await tester.pump();
    final settledMarker = tallMarker - 20;

    // Mid-crossfade, both children are alive. The marker must already sit at
    // the shorter child's position -- previously the outgoing 60pt child kept
    // sizing the Stack, so the marker hung 20pt low for the whole 300ms and
    // then snapped up when the fade ended.
    await tester.pump(const Duration(milliseconds: 150));
    expect(markerTop(tester), settledMarker);

    await tester.pumpAndSettle();
    expect(markerTop(tester), settledMarker);
  });

  testWidgets('the outgoing child keeps its own size while it fades',
      (tester) async {
    await tester.pumpWidget(harness(60));
    await tester.pumpAndSettle();

    await tester.pumpWidget(harness(40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // Align, not a bare Positioned.fill: the departing child must not be
    // stretched to the incoming child's box on its way out.
    expect(
      tester.getSize(find.byKey(const ValueKey<double>(60))).height,
      60,
    );
  });

  testWidgets('the outgoing chrome is gone before the incoming arrives',
      (tester) async {
    Widget host(String label) => MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: StatusModeSwitcher(
                alignment: Alignment.topCenter,
                child: Text(label, key: ValueKey<String>(label)),
              ),
            ),
          ),
        );

    await tester.pumpWidget(host('crop'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host('tools'));
    await tester.pump();

    double opacityOf(String label) {
      final finder = find.ancestor(
        of: find.byKey(ValueKey<String>(label)),
        matching: find.byType(FadeTransition),
      );
      if (finder.evaluate().isEmpty) {
        return 0;
      }
      return tester.widgetList<FadeTransition>(finder).first.opacity.value;
    }

    // Walked across the whole transition: these rows put round buttons in
    // the same corners, so any frame where both are visible shows two
    // controls superimposed -- which is what read as a ripple over the
    // toolbar capsule.
    var worstOverlap = 0.0;
    for (var i = 0; i < 20; i++) {
      await tester.pump(kStatusMotionDuration ~/ 20);
      final both = opacityOf('crop') * opacityOf('tools');
      if (both > worstOverlap) {
        worstOverlap = both;
      }
    }

    expect(
      worstOverlap,
      lessThan(0.02),
      reason: 'the two chrome sets were visible at the same time',
    );
    await tester.pumpAndSettle();
  });
}
