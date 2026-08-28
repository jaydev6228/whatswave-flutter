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
      'no background decoration paints inside the status bar band, so the '
      'shuffle design cannot sit behind the clock, wifi or battery',
      (tester) async {
    const topInset = 59.0; // Dynamic Island.
    const size = Size(393, 852);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Renders `child` full screen and returns the raw pixels of the band
    // the OS status bar occupies.
    Future<Uint8List> statusBandOf(Widget child) async {
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
      // Every row above the inset, all four channels.
      return Uint8List.fromList(
        all.sublist(0, topInset.toInt() * size.width.toInt() * 4),
      );
    }

    // The absolute reference: the background gradient on its own, with no
    // decoration layer at all. Comparing layouts against each other cannot
    // catch a leak in whichever layout is the reference -- this can.
    const style = StatusTextStyle();
    final background = resolveTextStatusBackgroundForStyle(
      style,
      AppPalette.green,
    );
    final bareGradient = await statusBandOf(
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

    // Every layout decorates the top of the canvas differently -- `poster`
    // a solid rotated accent bar at `top: 26`, `banner` a 94pt circle,
    // `classic` a glow orb deliberately bleeding off the edge at
    // `top: -20`. None of them may put a pixel in the status bar band, so
    // each one's band must be exactly the bare gradient.
    for (final layout in StatusTextLayout.values) {
      expect(
        await statusBandOf(
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
        reason: '${layout.name} paints behind the OS status bar icons',
      );
    }

    expect(bareGradient.any((byte) => byte != 0), isTrue);
  });
}
