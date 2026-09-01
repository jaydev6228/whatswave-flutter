import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/shared/widgets/liquid_glass.dart';

void main() {
  late ThemeData theme;

  Future<void> pumpDialog(WidgetTester tester) async {
    theme = ThemeData.dark();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: LiquidGlassDialog(
            title: const Text('Delete status?'),
            content: const Text('This cannot be undone.'),
            actions: [
              TextButton(onPressed: () {}, child: const Text('Cancel')),
              LiquidGlassDialogAction(
                label: 'Delete',
                isDestructive: true,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The colour the label is actually painted in.
  Color? labelColour(WidgetTester tester, String label) {
    return tester
        .widget<RichText>(
          find.descendant(
              of: find.text(label), matching: find.byType(RichText)),
        )
        .text
        .style
        ?.color;
  }

  Color? fill(WidgetTester tester, String label) {
    return tester
        .widget<TextButton>(
          find.ancestor(
              of: find.text(label), matching: find.byType(TextButton)),
        )
        .style
        ?.backgroundColor
        ?.resolve(const <WidgetState>{});
  }

  testWidgets('a destructive action is a red label, not a filled slab',
      (tester) async {
    await pumpDialog(tester);

    expect(labelColour(tester, 'Delete'), theme.colorScheme.error);
    // No fill of its own: the emphasis is entirely in the label, so a
    // destructive action no longer dominates the dialog it sits in.
    expect(fill(tester, 'Delete'), isNot(theme.colorScheme.error));
  });

  testWidgets('a normal action is a plain label on an outlined capsule',
      (tester) async {
    await pumpDialog(tester);

    expect(labelColour(tester, 'Cancel'), theme.colorScheme.onSurface);
    expect(fill(tester, 'Cancel'), isNot(theme.colorScheme.error));
  });
}
