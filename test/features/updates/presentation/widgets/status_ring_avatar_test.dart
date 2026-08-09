import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_ring_avatar.dart';

void main() {
  testWidgets('shows avatar initials on the happy path', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusRingAvatar(
            label: 'Ava',
            color: Colors.green,
            totalSegments: 3,
            seenSegments: 0,
          ),
        ),
      ),
    );

    expect(find.text('AV'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('keeps a visible gap between the ring and avatar content',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusRingAvatar(
            label: 'Ava',
            color: Colors.green,
            totalSegments: 4,
            seenSegments: 1,
          ),
        ),
      ),
    );

    final paddings = tester.widgetList<Padding>(
      find.descendant(
        of: find.byType(StatusRingAvatar),
        matching: find.byType(Padding),
      ),
    );
    final padding = paddings.firstWhere(
      (widget) => (widget.padding as EdgeInsets).left > 3,
    );

    expect((padding.padding as EdgeInsets).left, greaterThan(3));
  });

  testWidgets('falls back to a placeholder when the label is empty',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusRingAvatar(
            label: '',
            color: Colors.green,
            totalSegments: 0,
            seenSegments: 0,
          ),
        ),
      ),
    );

    expect(find.text('?'), findsOneWidget);
  });
}
