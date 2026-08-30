import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_media_decoration_overlay.dart';

Future<void> _pump(WidgetTester tester, StatusStorySegment segment) {
  return tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      home: Scaffold(
        body: SizedBox.expand(
          child: StatusMediaDecorationOverlay(
            segment: segment,
            accentColor: AppPalette.emerald,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'a typed caption and a separately placed rich overlay both render, '
      'like WhatsApp shows both at once', (tester) async {
    final segment = StatusStorySegment(
      id: 'segment-1',
      type: StatusStoryType.photo,
      previewText: 'Golden hour vibes',
      localMediaPath: '/missing/photo.jpg',
      overlayItems: const [
        StatusMediaOverlayItem(
          id: 'overlay-emoji',
          type: StatusMediaOverlayType.emoji,
          label: '🔥',
        ),
      ],
    );

    await _pump(tester, segment);
    await tester.pump();

    expect(find.text('Golden hour vibes'), findsOneWidget);
    expect(find.text('🔥'), findsOneWidget);
  });

  testWidgets(
      'a typed caption still renders alongside a separate rich text overlay '
      'with its own different text', (tester) async {
    final segment = StatusStorySegment(
      id: 'segment-2',
      type: StatusStoryType.photo,
      previewText: 'Golden hour vibes',
      localMediaPath: '/missing/photo.jpg',
      overlayItems: const [
        StatusMediaOverlayItem(
          id: 'overlay-text',
          type: StatusMediaOverlayType.text,
          label: 'Look up!',
        ),
      ],
    );

    await _pump(tester, segment);
    await tester.pump();

    expect(find.text('Golden hour vibes'), findsOneWidget);
    expect(find.text('Look up!'), findsOneWidget);
  });

  testWidgets(
      "the caption card is always plain, never the segment's own rich-text "
      '-overlay style -- that field describes the primary overlay (e.g. a '
      'bold custom look), not this separately typed caption', (tester) async {
    // Mirrors what the composer actually sends: segment.textStyle is the
    // *primary text overlay's* style (draft.textStyle = the "Gg" overlay's
    // look here), while previewText is the independently typed caption.
    const overlayStyle = StatusTextStyle(
      fontId: 'poster',
      textColorValue: 0xFFFF3B30,
    );
    final segment = StatusStorySegment(
      id: 'segment-4',
      type: StatusStoryType.photo,
      previewText: 'ggggg',
      localMediaPath: '/missing/photo.jpg',
      textStyle: overlayStyle,
      overlayItems: const [
        StatusMediaOverlayItem(
          id: 'overlay-text',
          type: StatusMediaOverlayType.text,
          label: 'Gg',
          textStyle: overlayStyle,
        ),
      ],
    );

    await _pump(tester, segment);
    await tester.pump();

    final captionStyle = tester
        .widget<Text>(find.byKey(const Key('updates_media_caption_text')))
        .style;
    // The 'poster' look is uppercase/weight-900/wide-tracking/red -- none of
    // that should leak onto the caption.
    expect(captionStyle?.fontWeight, isNot(FontWeight.w900));
    expect(captionStyle?.letterSpacing, isNot(1.8));
    expect(captionStyle?.color, isNot(const Color(0xFFFF3B30)));
    expect(find.text('ggggg'), findsOneWidget);
  });

  testWidgets(
      'a legacy segment whose caption was synthesized into a single text '
      'overlay item does not show the caption card too', (tester) async {
    final segment = StatusStorySegment(
      id: 'segment-3',
      type: StatusStoryType.photo,
      previewText: 'Golden hour vibes',
      localMediaPath: '/missing/photo.jpg',
      overlayItems: const [
        StatusMediaOverlayItem(
          id: 'overlay-caption',
          type: StatusMediaOverlayType.text,
          label: 'Golden hour vibes',
          positionDy: 0.82,
        ),
      ],
    );

    await _pump(tester, segment);
    await tester.pump();

    expect(find.text('Golden hour vibes'), findsOneWidget);
  });

  testWidgets('an unmeaningful auto-generated caption never renders',
      (tester) async {
    final segment = StatusStorySegment(
      id: 'segment-4',
      type: StatusStoryType.photo,
      previewText: 'Shared a new photo update',
      localMediaPath: '/missing/photo.jpg',
      overlayItems: const [
        StatusMediaOverlayItem(
          id: 'overlay-emoji',
          type: StatusMediaOverlayType.emoji,
          label: '🌊',
        ),
      ],
    );

    await _pump(tester, segment);
    await tester.pump();

    expect(find.text('Shared a new photo update'), findsNothing);
    expect(find.text('🌊'), findsOneWidget);
  });

  testWidgets(
      'a long text overlay stays readable on the posted story -- it uses the '
      'whole screen rather than being shrunk to fit inside the media frame, '
      'and scrolls once it outgrows even that', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final longLabel = 'Overlay words that keep going and going. ' * 20;
    final segment = StatusStorySegment(
      id: 'long-overlay-segment',
      type: StatusStoryType.photo,
      previewText: 'Shared a new photo update',
      localMediaPath: '/missing/media/long-overlay.jpg',
      // A wide frame inside a tall screen, so the media frame is much
      // shorter than the screen -- the case that made long text tiny.
      mediaTransform: const StatusMediaTransform(frameAspectRatio: 2),
      overlayItems: <StatusMediaOverlayItem>[
        StatusMediaOverlayItem(
          id: 'overlay-long',
          type: StatusMediaOverlayType.text,
          label: longLabel,
        ),
      ],
    );

    await _pump(tester, segment);
    await tester.pumpAndSettle();

    final overlayText = find.text(longLabel);
    expect(overlayText, findsOneWidget);

    // Every character is still there -- nothing dropped or ellipsised.
    final textWidget = tester.widget<Text>(overlayText);
    expect(textWidget.data, longLabel);
    expect(textWidget.overflow, isNot(TextOverflow.ellipsis));

    // Readable rather than shrunk-to-fit: no scale-down FittedBox on the
    // full-size path, and it is allowed to run past the media frame.
    expect(
      find.ancestor(
        of: overlayText,
        matching: find.byWidgetPredicate(
          (widget) => widget is FittedBox && widget.fit == BoxFit.scaleDown,
        ),
      ),
      findsNothing,
    );

    // Overflow is absorbed by scrolling -- and it really scrolls, which is
    // the part an IgnorePointer around the overlay would silently kill.
    final scrollable = find.ancestor(
      of: overlayText,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'the long overlay should have somewhere to scroll to',
    );
    // Drag the viewport, not the Text: the text is taller than the
    // viewport, so its own centre sits off-screen.
    await tester.drag(scrollable, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(0),
      reason: 'dragging the overlay must actually scroll its text',
    );

    // It uses the screen, not just the short media frame: the visible
    // window is taller than the 2:1 media frame it sits on, which is
    // exactly what stopped the text being shrunk into that frame.
    final viewport = tester.getRect(scrollable);
    const mediaFrameHeight = 390 / 2;
    expect(
      viewport.height,
      greaterThan(mediaFrameHeight),
      reason: 'long text should spill onto the bars rather than shrink',
    );
    // ...while still staying inside the screen itself.
    expect(viewport.width, lessThanOrEqualTo(390 + 0.5));
    expect(viewport.height, lessThanOrEqualTo(844 + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the text overlay keeps clear of the story chrome -- it never runs '
      'under the header row or the bottom controls drawn over the media',
      (tester) async {
    const screen = Size(390, 844);
    await tester.binding.setSurfaceSize(screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final longLabel = 'Overlay words that keep going and going. ' * 20;
    final segment = StatusStorySegment(
      id: 'chrome-overlap-segment',
      type: StatusStoryType.photo,
      previewText: 'Shared a new photo update',
      localMediaPath: '/missing/media/chrome.jpg',
      overlayItems: <StatusMediaOverlayItem>[
        StatusMediaOverlayItem(
          id: 'overlay-long',
          type: StatusMediaOverlayType.text,
          label: longLabel,
        ),
      ],
    );

    await _pump(tester, segment);
    await tester.pumpAndSettle();

    final viewport = tester.getRect(
      find.ancestor(
        of: find.text(longLabel),
        matching: find.byType(Scrollable),
      ),
    );
    final allowed = statusOverlayTextBoundsFor(screen);

    // The reserved bands at top and bottom are exactly what stops the text
    // colliding with the author row, the volume/delete/close buttons and
    // the caption beneath.
    expect(viewport.height, lessThanOrEqualTo(allowed.height + 0.5));
    expect(viewport.width, lessThanOrEqualTo(allowed.width + 0.5));
    expect(
      viewport.top,
      greaterThan(0),
      reason: 'text must not start at the very top, under the header',
    );
    expect(
      viewport.bottom,
      lessThan(screen.height),
      reason: 'text must not reach the bottom controls',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'overlay text that outgrows the screen shows a scroll hint, which '
      'goes away for good once the end is reached', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final segment = StatusStorySegment(
      id: 'segment-long',
      type: StatusStoryType.photo,
      previewText: '',
      localMediaPath: '/missing/photo.jpg',
      overlayItems: [
        StatusMediaOverlayItem(
          id: 'overlay-text',
          type: StatusMediaOverlayType.text,
          label: List.generate(120, (i) => 'line $i').join(' '),
        ),
      ],
    );

    await _pump(tester, segment);
    await tester.pumpAndSettle();

    const hint = Key('updates_overlay_text_more_below');
    double opacity() => tester
        .widget<AnimatedOpacity>(find.ancestor(
          of: find.byKey(hint),
          matching: find.byType(AnimatedOpacity),
        ))
        .opacity;

    // There is more text below, so say so.
    expect(opacity(), 1, reason: 'no hint that the text continues below');

    final scrollable = find.descendant(
      of: find.byType(StatusMediaDecorationOverlay),
      matching: find.byType(Scrollable),
    );
    final controller = tester.widget<Scrollable>(scrollable.first).controller!;

    // Tapping it pages down.
    await tester.tap(find.byKey(hint));
    await tester.pumpAndSettle();
    expect(
      controller.position.pixels,
      greaterThan(0),
      reason: 'the hint does not scroll when tapped',
    );

    // Read to the end and it goes away...
    await tester.drag(scrollable.first, const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(opacity(), 0, reason: 'the hint outstayed the end of the text');

    // ...and stays away, even after scrolling back up.
    await tester.drag(scrollable.first, const Offset(0, 4000));
    await tester.pumpAndSettle();
    expect(
      opacity(),
      0,
      reason: 'the hint came back after the reader had already seen the end',
    );
    expect(tester.takeException(), isNull);
  });
}
