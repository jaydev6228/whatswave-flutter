import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/presentation/media_status_composer_screen.dart';
import 'package:whatswave/features/updates/presentation/status_story_viewer_screen.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_story_media_surface.dart';

import '../../../support/device_matrix.dart';

const _emoji = '🔥';

/// A quarter of the way down the picture -- the arrangement that has to
/// survive the trip to another phone.
const _overlayDx = 0.5;
const _overlayDy = 0.25;

/// Real notch/home-indicator insets, which is what made the viewer's
/// SafeArea'd overlay layer disagree with the full-bleed media beside it.
/// A widget test has no insets unless it is given some, so without these
/// the asymmetry simply cannot show up.
const _iphoneInsets = EdgeInsets.only(top: 59, bottom: 34);
const _androidInsets = EdgeInsets.only(top: 24);

void _ignoreStoryViewed(StatusStory story) {}

StatusStory _photoStory({double? frameAspectRatio}) {
  return StatusStory(
    id: 'media-parity-story',
    name: 'Jay',
    avatarLabel: 'JD',
    previewText: 'Shared a new photo update',
    timeLabel: 'Just now',
    accentColor: AppPalette.emerald,
    type: StatusStoryType.photo,
    totalSegments: 1,
    seenSegments: 0,
    segments: <StatusStorySegment>[
      StatusStorySegment(
        id: 'media-parity-segment',
        type: StatusStoryType.photo,
        previewText: 'Shared a new photo update',
        localMediaPath: '/missing/photo.jpg',
        mediaTransform: StatusMediaTransform(
          frameAspectRatio: frameAspectRatio,
        ),
        overlayItems: const <StatusMediaOverlayItem>[
          StatusMediaOverlayItem(
            id: 'overlay-emoji',
            type: StatusMediaOverlayType.emoji,
            label: _emoji,
            positionDx: _overlayDx,
            positionDy: _overlayDy,
          ),
        ],
      ),
    ],
  );
}

Future<void> _pumpViewer(
  WidgetTester tester, {
  required TestDeviceProfile device,
  required EdgeInsets insets,
  double? frameAspectRatio,
}) async {
  await tester.binding.setSurfaceSize(device.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: device.size,
          viewPadding: insets,
          padding: insets,
        ),
        child: StatusStoryViewerScreen(
          story: _photoStory(frameAspectRatio: frameAspectRatio),
          onStoryViewed: _ignoreStoryViewed,
          segmentDurationOverride: const Duration(seconds: 10),
        ),
      ),
    ),
  );
  await pumpForAsyncUi(tester);
}

Future<void> _pumpComposer(
  WidgetTester tester, {
  required TestDeviceProfile device,
  required EdgeInsets insets,
}) async {
  await tester.binding.setSurfaceSize(device.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: device.size,
          viewPadding: insets,
          padding: insets,
        ),
        child: const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The canvas the media is rendered into -- the reference the author is
/// actually looking at when they place something on the picture.
Rect _mediaCanvas(WidgetTester tester) =>
    tester.getRect(find.byType(StatusStoryMediaSurface).first);

/// Where the emoji sits on that canvas. Measured against the media's own
/// box, not against whatever box the overlay layer happens to be handed:
/// those two being different boxes is the bug.
Offset _emojiOnMedia(WidgetTester tester) {
  final canvas = _mediaCanvas(tester);
  final emoji = tester.getCenter(find.text(_emoji).last);
  return Offset(
    (emoji.dx - canvas.left) / canvas.width,
    (emoji.dy - canvas.top) / canvas.height,
  );
}

void main() {
  testWidgets(
      '"Fit to screen": a placed emoji lands on the same part of the picture '
      'on screens of different shapes and insets', (tester) async {
    await _pumpViewer(
      tester,
      device: iphoneProProfile,
      insets: _iphoneInsets,
    );
    final onIphone = _emojiOnMedia(tester);

    await _pumpViewer(
      tester,
      device: tabletProfile,
      insets: _androidInsets,
    );
    final onTablet = _emojiOnMedia(tester);

    expect(
      onIphone.dy,
      closeTo(onTablet.dy, 0.005),
      reason: 'the emoji sits at a different height on the picture on the '
          'two devices',
    );
    expect(onIphone.dx, closeTo(onTablet.dx, 0.005));

    // And at the place it was actually put, rather than merely agreeing on
    // some other place.
    expect(onIphone.dy, closeTo(_overlayDy, 0.005));
    expect(onIphone.dx, closeTo(_overlayDx, 0.005));
  });

  testWidgets(
      'an explicit frame ratio was no safer: a square frame put the emoji at '
      'a different height on the picture too', (tester) async {
    await _pumpViewer(
      tester,
      device: iphoneProProfile,
      insets: _iphoneInsets,
      frameAspectRatio: 1,
    );
    final onIphone = _emojiOnMedia(tester);

    await _pumpViewer(
      tester,
      device: tabletProfile,
      insets: _androidInsets,
      frameAspectRatio: 1,
    );
    final onTablet = _emojiOnMedia(tester);

    expect(
      onIphone.dy,
      closeTo(onTablet.dy, 0.005),
      reason: 'a ratio-locked frame still drifted, because the overlay layer '
          'was measured against the safe area and the media was not',
    );
    expect(onIphone.dx, closeTo(onTablet.dx, 0.005));
  });

  testWidgets(
      'the media story canvas holds 9:16 on a tall narrow and a short wide '
      'screen', (tester) async {
    final cases = <TestDeviceProfile>[
      smallestPhoneProfile,
      // The matrix's widest viewport on its side: the one shape where the
      // canvas has to give up width rather than height.
      TestDeviceProfile(
        name: 'Tablet (landscape)',
        size: Size(tabletProfile.size.height, tabletProfile.size.width),
      ),
    ];

    for (final device in cases) {
      await _pumpViewer(tester, device: device, insets: _androidInsets);
      final canvas = _mediaCanvas(tester);

      expect(
        canvas.width / canvas.height,
        closeTo(kStatusStoryCanvasAspectRatio, 0.001),
        reason: '${device.name} did not letterbox the media canvas to 9:16',
      );
      expect(canvas.width, lessThanOrEqualTo(device.size.width + 0.01));
      expect(canvas.height, lessThanOrEqualTo(device.size.height + 0.01));
    }
  });

  testWidgets(
      'the composer puts the media on the same fixed-ratio canvas the viewer '
      'renders it on', (tester) async {
    await _pumpViewer(
      tester,
      device: iphoneProProfile,
      insets: _iphoneInsets,
    );
    final viewerCanvas = _mediaCanvas(tester).size;

    await _pumpComposer(
      tester,
      device: iphoneProProfile,
      insets: _iphoneInsets,
    );
    final composerCanvas = _mediaCanvas(tester).size;

    // The composer used to preview on the whole screen, so a fraction meant
    // one thing while composing and another once posted on a phone of a
    // different shape.
    expect(
      composerCanvas.width / composerCanvas.height,
      closeTo(kStatusStoryCanvasAspectRatio, 0.001),
    );
    expect(composerCanvas.width, closeTo(viewerCanvas.width, 0.5));
    expect(composerCanvas.height, closeTo(viewerCanvas.height, 0.5));

    // A newly placed item is centred in the composer's own chrome-reserved
    // rect rather than on the picture -- deliberate, and unchanged here, so
    // it is asserted rather than left to look like a regression later.
    await tester.tap(find.byKey(const Key('updates_media_add_emoji_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updates_media_emoji_option_0')));
    await tester.pumpAndSettle();

    final canvas = _mediaCanvas(tester);
    final placed = tester.getCenter(
      find.descendant(
        of: find.byKey(const Key('updates_overlay_item_emoji-0')),
        matching: find.byType(Text),
      ),
    );
    expect(canvas.contains(placed), isTrue);
  });

  testWidgets('nothing overflows at the smallest size in the matrix',
      (tester) async {
    await _pumpViewer(
      tester,
      device: smallestPhoneProfile,
      insets: _androidInsets,
    );
    expect(tester.takeException(), isNull);

    await _pumpComposer(
      tester,
      device: smallestPhoneProfile,
      insets: _androidInsets,
    );
    expect(tester.takeException(), isNull);
  });
}
