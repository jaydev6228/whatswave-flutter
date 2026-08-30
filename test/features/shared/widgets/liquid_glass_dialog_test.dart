import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/shared/widgets/liquid_glass.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required Widget dialog}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showDialog<void>(context: context, builder: (_) => dialog),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the dialog blurs what is behind it, unlike a themed AlertDialog',
      (tester) async {
    await pump(
      tester,
      dialog: const LiquidGlassDialog(
        title: Text('Delete status?'),
        content: Text('This removes it from My status.'),
        actions: [Text('Cancel'), Text('Delete')],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Delete status?'), findsOneWidget);
    expect(find.text('This removes it from My status.'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // The whole point of the widget: DialogTheme can carry shape, border
    // and elevation, but it cannot add a BackdropFilter, so a themed
    // AlertDialog stays an opaque panel.
    expect(
      find.descendant(
        of: find.byType(LiquidGlassDialog),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
      reason: 'the dialog is an opaque panel, not glass',
    );
  });

  testWidgets('title-only and content-only dialogs both lay out',
      (tester) async {
    await pump(tester,
        dialog: const LiquidGlassDialog(title: Text('Just a title')));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Just a title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long content scrolls instead of pushing the actions off screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pump(
      tester,
      dialog: LiquidGlassDialog(
        title: const Text('Terms'),
        content: Text(List.generate(200, (i) => 'line $i').join('\n')),
        actions: const [Text('OK')],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Actions stay on screen; the body is what gives.
    final actions = tester.getRect(find.text('OK'));
    expect(actions.bottom, lessThanOrEqualTo(640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('actions render as capsules without the call site asking',
      (tester) async {
    await pump(
      tester,
      dialog: const LiquidGlassDialog(
        title: Text('Delete status?'),
        actions: [
          // Exactly what the call sites write -- no styling of their own.
          TextButton(onPressed: null, child: Text('Cancel')),
          FilledButton(onPressed: null, child: Text('Delete')),
        ],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Scoped to the dialog: the harness's own "open" button is a TextButton
    // too, and it is not themed by the dialog.
    Finder inDialog(Type type) => find.descendant(
          of: find.byType(LiquidGlassDialog),
          matching: find.byType(type),
        );

    OutlinedBorder? shapeOf(Type type, {required bool isText}) {
      final element = tester.element(inDialog(type));
      final style = isText
          ? TextButtonTheme.of(element).style
          : FilledButtonTheme.of(element).style;
      return style?.shape?.resolve(<WidgetState>{});
    }

    expect(
      shapeOf(TextButton, isText: true),
      isA<StadiumBorder>(),
      reason: 'dialog actions are not capsules',
    );
    expect(shapeOf(FilledButton, isText: false), isA<StadiumBorder>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tint is light enough for the blur to read', (tester) async {
    await pump(
      tester,
      dialog: const LiquidGlassDialog(title: Text('Anything')),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final surface = tester.widget<LiquidGlassSurface>(
      find
          .descendant(
            of: find.byType(LiquidGlassDialog),
            matching: find.byType(LiquidGlassSurface),
          )
          .first,
    );
    // At sheet weight (0.86) the fill was so close to opaque that the glass
    // was invisible -- it read as a flat rounded panel.
    expect(
      surface.tintOpacityDark,
      lessThan(0.7),
      reason: 'the tint is heavy enough to hide the blur entirely',
    );
  });
}
