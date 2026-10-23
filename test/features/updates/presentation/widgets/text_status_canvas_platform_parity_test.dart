import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/presentation/status_story_viewer_screen.dart';
import 'package:whatswave/features/updates/presentation/text_status_composer_screen.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_story_media_surface.dart';
import 'package:whatswave/features/updates/presentation/widgets/text_status_canvas.dart';

import '../../../../support/device_matrix.dart';

/// A text status with an emoji placed a quarter of the way down, which is
/// the arrangement that broke: composed on a tall iPhone, the emoji sat
/// above the words; viewed on a shorter Android it landed on top of them.
const _emoji = '🔥';
const _overlayDx = 0.5;
const _overlayDy = 0.25;

const _placedOverlay = StatusMediaOverlayItem(
  id: 'overlay-emoji',
  type: StatusMediaOverlayType.emoji,
  label: _emoji,
  positionDx: _overlayDx,
  positionDy: _overlayDy,
);

const _textSegment = StatusStorySegment(
  id: 'text-segment',
  type: StatusStoryType.text,
  previewText: 'selfi time',
  textStyle: StatusTextStyle(
    fontId: 'serif',
    backgroundId: 'sunset_glow',
  ),
  overlayItems: <StatusMediaOverlayItem>[_placedOverlay],
);

const _textStory = StatusStory(
  id: 'parity-story',
  name: 'Jay',
  avatarLabel: 'JD',
  previewText: 'selfi time',
  timeLabel: 'Just now',
  accentColor: AppPalette.emerald,
  type: StatusStoryType.text,
  totalSegments: 1,
  seenSegments: 0,
  segments: <StatusStorySegment>[_textSegment],
);

Future<void> _pumpViewer(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: const StatusStoryViewerScreen(
        story: _textStory,
        onStoryViewed: _ignoreStoryViewed,
        segmentDurationOverride: Duration(seconds: 10),
      ),
    ),
  );
  await pumpForAsyncUi(tester);
}

Future<void> _pumpComposer(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      home: const TextStatusComposerScreen(
        initialDraft: TextStatusComposerDraft(
          caption: 'selfi time',
          textStyle: StatusTextStyle(fontId: 'serif'),
          overlayItems: <StatusMediaOverlayItem>[_placedOverlay],
        ),
      ),
    ),
  );
  await pumpForAsyncUi(tester);
}

void _ignoreStoryViewed(StatusStory story) {}

/// Where the placed emoji sits as a fraction of the canvas it is anchored
/// to.
Offset _emojiFractionWithinCanvas(WidgetTester tester) {
  final canvas = tester.getRect(find.byType(TextStatusCanvas).first);
  final emoji = tester.getCenter(find.text(_emoji));
  return Offset(
    (emoji.dx - canvas.left) / canvas.width,
    (emoji.dy - canvas.top) / canvas.height,
  );
}

/// The gap between the emoji and the top of the words, as a fraction of
/// the canvas height.
///
/// Measured to the text's edge, not its centre: the text block is centred
/// in the canvas, so centre-to-centre is equal on any screen and proves
/// nothing. The gap to the edge is what the author sees as "the emoji is
/// above the words", and it is what moved when the canvas took the shape of
/// the device -- the type scales with the canvas width while a fraction of
/// the height stays put, so the two drift apart as the ratio changes.
double _emojiGapAboveText(WidgetTester tester) {
  final canvas = tester.getRect(find.byType(TextStatusCanvas).first);
  final emoji = tester.getCenter(find.text(_emoji));
  final text = tester.getRect(
    find.byKey(const Key('updates_text_status_canvas_text')).first,
  );
  return (text.top - emoji.dy) / canvas.height;
}

/// How much of the canvas the words themselves take up. Uniform scaling is
/// the whole promise of a fixed-ratio canvas: every part of the
/// composition keeps its share of it.
double _textHeightFractionOfCanvas(WidgetTester tester) {
  final canvas = tester.getRect(find.byType(TextStatusCanvas).first);
  final text = tester.getRect(
    find.byKey(const Key('updates_text_status_canvas_text')).first,
  );
  return text.height / canvas.height;
}

void main() {
  test('no font look names a generic platform alias', () {
    // The regression that started this: 'serif' and 'monospace' are
    // platform aliases, resolved to Times on iOS and Noto Serif on Android.
    for (final look in kTextStatusFontLooks) {
      final resolved = buildTextStatusTextStyle(
        theme: ThemeData.light(),
        style: StatusTextStyle(fontId: look.id),
        accentColor: AppPalette.emerald,
        shortestSide: 393,
        textLength: 10,
      );
      expect(
        resolved.fontFamily,
        isNot(anyOf('serif', 'monospace')),
        reason: 'the ${look.id} look resolves a platform alias, so it '
            'renders in a different typeface on iOS than on Android',
      );
    }
  });

  test('the serif and mono looks resolve to the bundled families', () {
    TextStyle styleFor(String fontId) => buildTextStatusTextStyle(
          theme: ThemeData.light(),
          style: StatusTextStyle(fontId: fontId),
          accentColor: AppPalette.emerald,
          shortestSide: 393,
          textLength: 10,
        );

    expect(styleFor('serif').fontFamily, 'StorySerif');
    expect(styleFor('italic').fontFamily, 'StorySerif');
    expect(styleFor('editorial').fontFamily, 'StorySerif');
    expect(styleFor('journal').fontFamily, 'StorySerif');
    expect(styleFor('luxe').fontFamily, 'StorySerif');
    expect(styleFor('mono').fontFamily, 'StoryMono');
    expect(styleFor('capsule').fontFamily, 'StoryMono');
    expect(styleFor('signal').fontFamily, 'StoryMono');
  });

  testWidgets('the canvas renders its text in the bundled family it resolved',
      (tester) async {
    for (final probe in const <List<String>>[
      <String>['serif', 'StorySerif'],
      <String>['mono', 'StoryMono'],
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: TextStatusCanvas(
              text: 'selfi time',
              style: StatusTextStyle(fontId: probe.first),
              accentColor: AppPalette.emerald,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(
        find.byKey(const Key('updates_text_status_canvas_text')),
      );
      expect(text.style?.fontFamily, probe.last);
    }
  });

  testWidgets(
      'a placed emoji keeps the same position within the canvas on screens '
      'of very different shapes', (tester) async {
    // The two extremes the suite already tests against: a tall phone and a
    // tablet, whose aspect ratios are nothing alike.
    const devices = <TestDeviceProfile>[iphoneProProfile, tabletProfile];
    final gapsAboveText = <double>[];
    final textHeights = <double>[];

    for (final device in devices) {
      await _pumpViewer(tester, device.size);
      final viewed = _emojiFractionWithinCanvas(tester);
      expect(
        viewed.dx,
        closeTo(_overlayDx, 0.005),
        reason: '${device.name} moved the emoji horizontally',
      );
      expect(
        viewed.dy,
        closeTo(_overlayDy, 0.005),
        reason: '${device.name} moved the emoji vertically',
      );
      gapsAboveText.add(_emojiGapAboveText(tester));
      textHeights.add(_textHeightFractionOfCanvas(tester));

      // And the composer anchors it to the same place, so what the author
      // arranges is what the story shows.
      await _pumpComposer(tester, device.size);
      final composed = _emojiFractionWithinCanvas(tester);
      expect(composed.dx, closeTo(viewed.dx, 0.005));
      expect(composed.dy, closeTo(viewed.dy, 0.005));
    }

    expect(
      gapsAboveText.last,
      closeTo(gapsAboveText.first, 0.005),
      reason: '${devices.last.name} put the emoji a different distance above '
          'the words than ${devices.first.name} did',
    );
    expect(
      textHeights.last,
      closeTo(textHeights.first, 0.005),
      reason: 'the words take a different share of the canvas on '
          '${devices.last.name} than on ${devices.first.name}',
    );
  });

  testWidgets(
      'the story canvas holds 9:16 on a tall narrow and a short wide '
      'screen', (tester) async {
    final sizes = <Size>[
      smallestPhoneProfile.size,
      // The matrix's widest viewport, laid on its side: the one shape where
      // the canvas has to give up width instead of height.
      Size(tabletProfile.size.height, tabletProfile.size.width),
    ];

    for (final size in sizes) {
      await _pumpViewer(tester, size);
      final canvas = tester.getRect(find.byType(TextStatusCanvas).first);

      expect(
        canvas.width / canvas.height,
        closeTo(kStatusStoryCanvasAspectRatio, 0.001),
        reason: '$size did not letterbox the canvas to 9:16',
      );
      expect(canvas.width, lessThanOrEqualTo(size.width + 0.01));
      expect(canvas.height, lessThanOrEqualTo(size.height + 0.01));
    }
  });

  testWidgets('nothing overflows at the smallest size in the matrix',
      (tester) async {
    await _pumpViewer(tester, smallestPhoneProfile.size);
    expect(tester.takeException(), isNull);

    await _pumpComposer(tester, smallestPhoneProfile.size);
    expect(tester.takeException(), isNull);
  });
}
