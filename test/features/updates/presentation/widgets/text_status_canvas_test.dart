import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/presentation/widgets/text_status_canvas.dart';

void main() {
  testWidgets(
      'the canvas background is the gradient and nothing else, in every '
      'layout', (tester) async {
    const topInset = 59.0; // Dynamic Island.
    const size = Size(393, 852);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Renders `child` full screen and returns its raw pixels.
    Future<Uint8List> pixelsOf(Widget child) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: size,
            viewPadding: EdgeInsets.only(top: topInset),
            padding: EdgeInsets.only(top: topInset),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: const Key('canvas_boundary'),
              child: child,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('canvas_boundary')),
      );
      // toImageSync + runAsync: the plain async toImage()/toByteData() pair
      // never completes under the widget tester's fake async zone.
      final image = boundary.toImageSync();
      final data = await tester.runAsync(
        () => image.toByteData(format: ImageByteFormat.rawRgba),
      );
      image.dispose();
      final all = data!.buffer.asUint8List();
      // The whole canvas, all four channels.
      return Uint8List.fromList(all);
    }

    // The background gradient on its own. Decorative shapes used to be
    // painted over it -- orbs, tape strips, dot clusters -- which collided
    // with the OS status bar, then with the story's own chrome, and read as
    // stray artifacts rather than design. They are gone: a text status is
    // the gradient, the way WhatsApp's is.
    const style = StatusTextStyle();
    final background = resolveTextStatusBackgroundForStyle(
      style,
      AppPalette.green,
    );
    final bareGradient = await pixelsOf(
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: background.colors,
            begin: background.begin,
            end: background.end,
          ),
        ),
      ),
    );

    for (final layout in StatusTextLayout.values) {
      expect(
        await pixelsOf(
          TextStatusCanvas(
            text: '',
            style: StatusTextStyle(layout: layout),
            accentColor: AppPalette.green,
            borderRadius: BorderRadius.zero,
            showFrame: false,
            showText: false,
          ),
        ),
        orderedEquals(bareGradient),
        reason: '${layout.name} paints something over the gradient',
      );
    }

    expect(bareGradient.any((byte) => byte != 0), isTrue);
  });
}
