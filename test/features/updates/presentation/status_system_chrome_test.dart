import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/presentation/media_status_composer_screen.dart';
import 'package:whatswave/features/updates/presentation/status_story_viewer_screen.dart';
import 'package:whatswave/features/updates/presentation/status_system_chrome.dart';
import 'package:whatswave/features/updates/presentation/text_status_composer_screen.dart';

import '../../../support/device_matrix.dart';

void main() {
  const story = StatusStory(
    id: 'ava-story',
    name: 'Ava',
    avatarLabel: 'AP',
    previewText: 'Late-night launch coffee',
    timeLabel: '15m ago',
    accentColor: AppPalette.green,
    type: StatusStoryType.photo,
    totalSegments: 1,
    seenSegments: 0,
  );

  Widget wrap(Widget home, {EdgeInsets viewPadding = EdgeInsets.zero}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: MediaQuery(
        data: MediaQueryData(viewPadding: viewPadding, padding: viewPadding),
        child: home,
      ),
    );
  }

  SystemUiOverlayStyle publishedStyle(WidgetTester tester) {
    return tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        )
        .value;
  }

  test(
      'the story overlay style asks for light system icons on both platforms, '
      'which needs opposite Brightness values', () {
    // iOS reads this as "the background behind the icons is dark", Android
    // reads its own field as "draw the icons light". They mean opposite
    // things, so they must not be tidied into agreeing.
    expect(kStatusStorySystemUiStyle.statusBarBrightness, Brightness.dark);
    expect(kStatusStorySystemUiStyle.statusBarIconBrightness, Brightness.light);
    expect(
      kStatusStorySystemUiStyle.systemNavigationBarIconBrightness,
      Brightness.light,
    );
    // Transparent bars, with Android's own auto-scrim off -- left on, it
    // lays a grey band over the top and bottom of the story.
    expect(kStatusStorySystemUiStyle.statusBarColor, Colors.transparent);
    expect(
      kStatusStorySystemUiStyle.systemNavigationBarColor,
      Colors.transparent,
    );
    expect(
      kStatusStorySystemUiStyle.systemNavigationBarContrastEnforced,
      isFalse,
    );
    expect(kStatusStorySystemUiStyle.systemStatusBarContrastEnforced, isFalse);
  });

  testWidgets('the text composer publishes the story system-bar style',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(const TextStatusComposerScreen()));
    await tester.pumpAndSettle();

    expect(publishedStyle(tester), kStatusStorySystemUiStyle);
  });

  testWidgets('the media composer publishes the story system-bar style',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        const MediaStatusComposerScreen(
          type: StatusStoryType.photo,
          localMediaPath: '/missing/photo.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(publishedStyle(tester), kStatusStorySystemUiStyle);
  });

  testWidgets('the viewer publishes the story system-bar style',
      (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        StatusStoryViewerScreen(
          story: story,
          onStoryViewed: (_) {},
          segmentDurationOverride: const Duration(seconds: 10),
        ),
      ),
    );
    await tester.pump();

    expect(publishedStyle(tester), kStatusStorySystemUiStyle);
  });

  testWidgets(
      'the status-bar scrim is measured from the device inset, so a notch, '
      'a Dynamic Island and a flat top each get the right cover',
      (tester) async {
    Future<double> scrimHeightFor(double topInset) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(viewPadding: EdgeInsets.only(top: topInset)),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topCenter,
              child: StatusStoryEdgeScrim(),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(StatusStoryEdgeScrim)).height;
    }

    // Dynamic Island covers more than a notch, which covers more than a
    // classic bar -- the scrim tracks each rather than guessing one number.
    final island = await scrimHeightFor(59);
    final notch = await scrimHeightFor(47);
    final classic = await scrimHeightFor(20);
    expect(island, greaterThan(notch));
    expect(notch, greaterThan(classic));
    expect(island, greaterThan(59));
    expect(notch, greaterThan(47));

    // A device that reports no inset still gets a usable band instead of a
    // zero-height no-op.
    expect(await scrimHeightFor(0), greaterThanOrEqualTo(44));
  });

  testWidgets(
      'the text composer and the viewer both scrim the status bar, so the '
      'preview and the posted story agree', (tester) async {
    await tester.binding.setSurfaceSize(iphoneProProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const insets = EdgeInsets.only(top: 59);

    await tester.pumpWidget(
      wrap(const TextStatusComposerScreen(), viewPadding: insets),
    );
    await tester.pumpAndSettle();
    final composerScrim = tester.getRect(
      find.byKey(const Key('updates_composer_status_bar_scrim')),
    );
    expect(composerScrim.top, 0);
    expect(composerScrim.left, 0);
    expect(composerScrim.width, iphoneProProfile.size.width);
    expect(composerScrim.height, greaterThan(59));

    await tester.pumpWidget(
      wrap(
        StatusStoryViewerScreen(
          story: story,
          onStoryViewed: (_) {},
          segmentDurationOverride: const Duration(seconds: 10),
        ),
        viewPadding: insets,
      ),
    );
    await tester.pump();
    final viewerScrim = tester.getRect(
      find.byKey(const Key('updates_story_viewer_status_bar_scrim')),
    );
    expect(viewerScrim, composerScrim);
  });
}
