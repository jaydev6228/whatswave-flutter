import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/updates/presentation/media_status_composer_screen.dart';

import '../../../support/fake_video_player_platform.dart';

void main() {
  const playButton = Key('updates_media_video_play_pause_overlay');

  late Directory tempDir;
  late File clip;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('composer_video_test_');
    clip = File('${tempDir.path}/clip.mp4')..writeAsBytesSync(<int>[0, 1, 2]);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<FakeVideoPlayerPlatform> pumpComposer(
    WidgetTester tester, {
    Duration latency = Duration.zero,
  }) async {
    final fake = FakeVideoPlayerPlatform.install(latency: latency);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaStatusComposerScreen(
          type: StatusStoryType.video,
          localMediaPath: clip.path,
        ),
      ),
    );
    await tester.pump();
    fake.emitInitialized(1);
    await tester.pump();
    await tester.pump();
    return fake;
  }

  testWidgets('a picked video opens paused, showing the play button',
      (tester) async {
    await pumpComposer(tester);
    expect(find.byKey(playButton), findsOneWidget);
  });

  testWidgets('the play button comes back only once the video has reset',
      (tester) async {
    // With latency, the pause and the seek that VideoPlayerController chains
    // on end-of-clip land in different frames -- which is the only way the
    // ordering between them is observable at all.
    final fake =
        await pumpComposer(tester, latency: const Duration(milliseconds: 50));

    await tester.tap(find.byKey(playButton));
    await tester.pump();
    // Past the simulated platform latency on play().
    await tester.pump(const Duration(milliseconds: 100));
    expect(fake.playing[1], isTrue);
    expect(find.byKey(playButton), findsNothing);

    // The window, not the whole scrubber -- the scrubber's rect also spans
    // the mute toggle beside the strip.
    final strip = find.byKey(const Key('updates_media_trim_window'));
    final playhead = find.byKey(const Key('updates_media_trim_playhead'));

    // Run the clip most of the way through, so the playhead is far right.
    fake.positions[1] = const Duration(seconds: 5);
    // One pump for the controller's own 100ms position poll, another for
    // the playhead's coast to the new spot.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(playhead).left,
        greaterThan(tester.getRect(strip).left + 20));

    // The clip runs out. VideoPlayerController answers by pausing and then
    // seeking, so the pause lands first: the play button used to appear on
    // that frame while the rewind arrived a couple of frames later, and the
    // playhead crawled back across the strip in between. Catch the exact
    // frame the button returns and check the reset has already happened.
    fake.emitCompleted(1);

    double? playheadWhenButtonAppeared;
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byKey(playButton).evaluate().isNotEmpty) {
        playheadWhenButtonAppeared = tester.getRect(playhead).left;
        break;
      }
    }

    // Let the controller's own chained pause/seek finish before teardown.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(playheadWhenButtonAppeared, isNotNull,
        reason: 'the play button never came back');
    expect(
      playheadWhenButtonAppeared,
      closeTo(tester.getRect(strip).left, 3),
      reason: 'the play button appeared before the video had reset',
    );
  });

  testWidgets('a player that stops on its own brings the play button back',
      (tester) async {
    final fake = await pumpComposer(tester);

    await tester.tap(find.byKey(playButton));
    await tester.pump();
    expect(find.byKey(playButton), findsNothing);

    // Stopped without being asked -- an interrupted audio session, an error.
    // Nothing told the UI, so the flag stayed stuck at "playing".
    fake.emitPlayingStateChanged(1, isPlaying: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(playButton), findsOneWidget);
  });

  testWidgets('the play button works again after the clip has ended',
      (tester) async {
    final fake = await pumpComposer(tester);

    await tester.tap(find.byKey(playButton));
    await tester.pump();
    fake.emitCompleted(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(playButton));
    await tester.pump();

    expect(fake.playing[1], isTrue);
  });
}
