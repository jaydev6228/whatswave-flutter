import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_chrome.dart';
import 'package:whatswave/features/updates/presentation/widgets/video_trim_scrubber.dart';

void main() {
  Future<void> pump(WidgetTester tester, {double? position}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: VideoTrimScrubber(
                videoPath: '/missing/video.mp4',
                fullDurationSeconds: 20,
                trimStartSeconds: 5,
                trimEndSeconds: 15,
                minTrimSeconds: 1,
                maxTrimSeconds: 20,
                onScrubStart: () {},
                onScrubUpdate: (_, __) {},
                onScrubEnd: () {},
                positionSeconds: position,
              ),
            ),
          ),
        ),
      ),
    );
  }

  const playhead = Key('updates_media_trim_playhead');

  testWidgets('the filmstrip marks where playback has reached', (tester) async {
    await pump(tester, position: 10);
    await tester.pump();

    expect(find.byKey(playhead), findsOneWidget);

    // Halfway through a 20s video on a 300pt strip.
    final strip = tester.getRect(find.byType(VideoTrimScrubber));
    final marker = tester.getRect(find.byKey(playhead));
    expect(marker.left - strip.left, closeTo(150, 1));

    // It tracks the position rather than sitting still.
    await pump(tester, position: 14);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(playhead)).left - strip.left,
      closeTo(210, 1),
    );
  });

  testWidgets('the playhead coasts between position updates', (tester) async {
    // `video_player` reports its position only every 100ms, so a playhead
    // that jumps straight to each new value visibly lurches ten times a
    // second. It has to travel the gap instead of teleporting across it.
    await pump(tester, position: 10);
    await tester.pumpAndSettle();
    final strip = tester.getRect(find.byType(VideoTrimScrubber));
    expect(tester.getRect(find.byKey(playhead)).left - strip.left,
        closeTo(150, 1));

    await pump(tester, position: 14);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Mid-gap: strictly between the old spot and the new one, having covered
    // roughly half the distance.
    final midway = tester.getRect(find.byKey(playhead)).left - strip.left;
    expect(midway, greaterThan(151));
    expect(midway, lessThan(209));

    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(playhead)).left - strip.left,
        closeTo(210, 1));
  });

  testWidgets('no playhead outside the trimmed window, or with no position',
      (tester) async {
    // Before the window.
    await pump(tester, position: 2);
    await tester.pump();
    expect(find.byKey(playhead), findsNothing);

    // After it.
    await pump(tester, position: 18);
    await tester.pump();
    expect(find.byKey(playhead), findsNothing);

    // And when nothing is playing at all.
    await pump(tester);
    await tester.pump();
    expect(find.byKey(playhead), findsNothing);
  });

  testWidgets(
      'a leading control sits beside the strip, leaving the duration label '
      'on its own line above', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: VideoTrimScrubber(
                videoPath: '/missing/video.mp4',
                fullDurationSeconds: 20,
                trimStartSeconds: 5,
                trimEndSeconds: 15,
                minTrimSeconds: 1,
                maxTrimSeconds: 20,
                onScrubStart: () {},
                onScrubUpdate: (_, __) {},
                onScrubEnd: () {},
                // Matches the real mute toggle: as tall as the strip, so
                // the shared surface has no band above or below it.
                leading: const SizedBox(
                  key: Key('leading'),
                  width: 44,
                  height: 40,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final label = tester.getRect(
      find.byKey(const Key('updates_media_trim_duration_label')),
    );
    final leading = tester.getRect(find.byKey(const Key('leading')));
    final strip =
        tester.getRect(find.byKey(const Key('updates_media_trim_window')));

    // One surface holds the leading control and the strip together, and
    // the label is outside it -- the label is not part of the group.
    final surface = find.byType(StatusChromeSurface);
    expect(surface, findsOneWidget);
    expect(
      find.descendant(of: surface, matching: find.byKey(const Key('leading'))),
      findsOneWidget,
      reason: 'the leading control is not inside the strip surface',
    );
    expect(
      find.descendant(
        of: surface,
        matching: find.byKey(const Key('updates_media_trim_duration_label')),
      ),
      findsNothing,
      reason: 'the duration label was pulled into the strip surface',
    );

    // The surface is exactly as tall as the strip -- no band above or
    // below it.
    final surfaceRect = tester.getRect(surface);
    final stripRect =
        tester.getRect(find.byKey(const Key('updates_media_trim_window')));
    expect(
      surfaceRect.height,
      // The surface's own hairline border adds a point top and bottom;
      // anything beyond that is vertical padding, which is what made the
      // background stand taller than the strip it wraps.
      closeTo(stripRect.height + 2, 0.5),
      reason: 'the surface is padded taller than the filmstrip',
    );

    // And the strip runs right up to the surface's edge. The surface's
    // fill is translucent, so any band of it beside the strip shows the
    // story through -- most visibly on the right, where nothing covers it.
    final barFinder = find.byKey(const Key('updates_media_trim_dim_after'));
    final barRight = tester.getRect(barFinder).right;
    expect(
      surfaceRect.right - barRight,
      lessThanOrEqualTo(1.5),
      reason: 'a band of translucent surface is showing beside the strip',
    );

    // Label above, on its own -- it is not part of the control group.
    expect(label.bottom, lessThanOrEqualTo(leading.top));
    // Leading and strip share a row, side by side.
    expect(leading.right, lessThanOrEqualTo(strip.left));
    expect(
      leading.center.dy,
      closeTo(strip.center.dy, 2),
      reason: 'the leading control is not aligned with the strip',
    );
    expect(tester.takeException(), isNull);
  });

  group('filmstrip coverage', () {
    test('every frame is sampled inside the clip, never at its very end', () {
      const durationMs = 27000;
      const frameCount = 10;
      final stamps = [
        for (var i = 0; i < frameCount; i++)
          filmstripFrameTimeMs(i, durationMs, frameCount: frameCount),
      ];

      // Slice midpoints, so each thumbnail represents the band it fills.
      expect(stamps.first, 1350);
      expect(stamps.last, 25650);

      // The old formula asked for durationMs exactly, which decodes to
      // nothing and left the end of the strip blank.
      expect(stamps.every((ms) => ms < durationMs), isTrue);
      expect(stamps.every((ms) => ms >= 0), isTrue);
      // Strictly increasing -- the strip reads left to right in time.
      for (var i = 1; i < stamps.length; i++) {
        expect(stamps[i], greaterThan(stamps[i - 1]));
      }
    });

    test('a one-frame-long clip still yields a valid timestamp', () {
      expect(filmstripFrameTimeMs(0, 0, frameCount: 10), 0);
      expect(filmstripFrameTimeMs(9, 1, frameCount: 10), 0);
    });

    test('a failed extraction borrows its nearest neighbour', () {
      final a = Uint8List.fromList([1]);
      final b = Uint8List.fromList([2]);

      // Gap at the end -- the case that showed the story through the strip.
      expect(fillFilmstripGaps([a, b, null]), [a, b, b]);
      // Gap at the start, and in the middle.
      expect(fillFilmstripGaps([null, a, b]), [a, a, b]);
      expect(fillFilmstripGaps([a, null, b]), [a, a, b]);
      // Nothing to borrow: left alone rather than faked.
      expect(fillFilmstripGaps([null, null]), [null, null]);
    });
  });
}
