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
}
