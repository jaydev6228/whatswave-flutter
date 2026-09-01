import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// An in-memory stand-in for the `video_player` plugin.
///
/// The real plugin needs a platform channel, so until now anything that
/// created a [VideoPlayerController] simply could not be covered (see the
/// note at the top of voice_note_bubble_test.dart). This makes playback
/// behaviour -- looping a trimmed range, a clip reaching its end, a player
/// that stops on its own -- testable without a device.
///
/// Install it with [install]; it restores the previous platform on teardown.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  FakeVideoPlayerPlatform({
    this.duration = const Duration(seconds: 6),
    this.size = const Size(1080, 1920),
    this.latency = Duration.zero,
  });

  final Duration duration;
  final Size size;

  /// How long play/pause/seek take to come back.
  ///
  /// Zero by default. Set it to model a real platform channel: the calls a
  /// controller chains together then land in *different* frames, which is
  /// how ordering bugs between them become visible to a user at all.
  final Duration latency;

  Future<void> _afterLatency() => latency == Duration.zero
      ? Future<void>.value()
      : Future<void>.delayed(latency);

  final Map<int, StreamController<VideoEvent>> _events =
      <int, StreamController<VideoEvent>>{};

  /// Where each player currently is; the controller polls this.
  final Map<int, Duration> positions = <int, Duration>{};

  /// Whether each player is running. Mirrors what play/pause were told.
  final Map<int, bool> playing = <int, bool>{};

  final List<Duration> seeks = <Duration>[];
  int _nextId = 1;

  static FakeVideoPlayerPlatform install({
    Duration duration = const Duration(seconds: 6),
    Duration latency = Duration.zero,
  }) {
    final previous = VideoPlayerPlatform.instance;
    final fake = FakeVideoPlayerPlatform(duration: duration, latency: latency);
    VideoPlayerPlatform.instance = fake;
    addTearDown(() {
      VideoPlayerPlatform.instance = previous;
      fake.closeAll();
    });
    return fake;
  }

  /// Announces the player is ready, which is what unblocks `initialize()`.
  void emitInitialized(int playerId) {
    _events[playerId]?.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: duration,
        size: size,
      ),
    );
  }

  /// The clip reaching its natural end. The real plugin stops the player
  /// here, and so does [VideoPlayerController] on receiving this.
  void emitCompleted(int playerId) {
    positions[playerId] = duration;
    playing[playerId] = false;
    _events[playerId]?.add(VideoEvent(eventType: VideoEventType.completed));
  }

  /// The player starting or stopping of its own accord.
  void emitPlayingStateChanged(int playerId, {required bool isPlaying}) {
    playing[playerId] = isPlaying;
    _events[playerId]?.add(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: isPlaying,
      ),
    );
  }

  void closeAll() {
    for (final controller in _events.values) {
      controller.close();
    }
    _events.clear();
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }

  @override
  Future<int?> create(DataSource dataSource) async => _create();

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      _create();

  int _create() {
    final id = _nextId++;
    _events[id] = StreamController<VideoEvent>.broadcast();
    positions[id] = Duration.zero;
    playing[id] = false;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      _events[playerId]?.stream ?? const Stream<VideoEvent>.empty();

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {
    await _afterLatency();
    playing[playerId] = true;
  }

  @override
  Future<void> pause(int playerId) async {
    await _afterLatency();
    playing[playerId] = false;
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    await _afterLatency();
    seeks.add(position);
    positions[playerId] = position;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.shrink();

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}
