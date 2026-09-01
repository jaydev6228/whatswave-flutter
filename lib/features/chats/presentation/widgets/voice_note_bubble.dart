import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../updates/presentation/widgets/status_media_source.dart';
import 'voice_note_recording_session.dart';

/// Inline playable voice-note bubble: a bare (chrome-less) play/pause glyph
/// on the left, a waveform scrubber and duration/timestamp line in the
/// middle, and a small speed-toggle badge on the right, visible from the
/// start. Every color comes from [contentColor] -- the same text/icon color
/// the rest of the message bubble already uses -- rather than a separate
/// accent, so it reads as part of the bubble's own theme instead of a
/// mismatched one-off.
class VoiceNoteBubble extends StatefulWidget {
  const VoiceNoteBubble({
    required this.localMediaPath,
    required this.fallbackLabel,
    required this.contentColor,
    this.trailingMeta,
    super.key,
  });

  final String localMediaPath;
  final String fallbackLabel;
  final Color contentColor;

  /// The message's own time+ticks row, rendered inline at the end of the
  /// duration line (WhatsApp puts both on one line) instead of the caller
  /// adding a separate line below. Null when the caller is already placing
  /// its own meta row elsewhere (e.g. this voice note has a caption).
  final Widget? trailingMeta;

  @override
  State<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends State<VoiceNoteBubble> {
  static const List<double> _speedOptions = [1.0, 1.5, 2.0];

  VideoPlayerController? _controller;
  bool _isReady = false;
  bool _hasError = false;
  bool _isInitializing = false;
  int _speedIndex = 0;
  late final List<double> _waveform = _generateWaveform(widget.localMediaPath);

  @override
  void dispose() {
    _controller?.removeListener(_handleUpdate);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _ensureController() async {
    if (_controller != null || _isInitializing || _hasError) {
      return;
    }
    // A remote voice note (synced via Firebase) opens a network stream here,
    // not a local file -- can take a real, visible moment. Flip this via
    // setState (not a bare field write) so the play button can show a
    // loading spinner for that stretch instead of looking unresponsive.
    setState(() => _isInitializing = true);
    final controller =
        (await buildStatusMediaVideoControllerAsync(widget.localMediaPath))
          ..addListener(_handleUpdate);
    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      await controller.setPlaybackSpeed(_speedOptions[_speedIndex]);
      setState(() {
        _controller = controller;
        _isReady = true;
        _isInitializing = false;
      });
    } catch (_) {
      controller.dispose();
      if (mounted) {
        setState(() {
          _hasError = true;
          _isInitializing = false;
        });
      }
    }
  }

  void _handleUpdate() {
    if (!mounted) {
      return;
    }
    final controller = _controller;
    if (controller != null) {
      final value = controller.value;
      // video_player clears isPlaying once playback runs off the end but
      // leaves position sitting at duration -- without resetting it here,
      // the bubble stays parked looking "fully played" (dot at the far
      // end, waveform all lit) forever instead of going back to its
      // at-rest look, ready to play again from the start.
      if (!value.isPlaying &&
          value.duration > Duration.zero &&
          value.position >= value.duration) {
        unawaited(controller.seekTo(Duration.zero));
      }
    }
    setState(() {});
  }

  Future<void> _togglePlayback() async {
    await _ensureController();
    final controller = _controller;
    if (!_isReady || controller == null) {
      return;
    }
    final value = controller.value;
    if (value.isPlaying) {
      await controller.pause();
      return;
    }
    if (value.duration > Duration.zero && value.position >= value.duration) {
      await controller.seekTo(Duration.zero);
    }
    await controller.play();
  }

  Future<void> _cycleSpeed() async {
    await _ensureController();
    final controller = _controller;
    if (!_isReady || controller == null) {
      return;
    }
    setState(() {
      _speedIndex = (_speedIndex + 1) % _speedOptions.length;
    });
    await controller.setPlaybackSpeed(_speedOptions[_speedIndex]);
  }

  /// A short moving average over raw random samples reads as an actual
  /// speech amplitude envelope rather than uniform-random "equalizer"
  /// noise -- closer to what a real waveform looks like.
  List<double> _generateWaveform(String seed) {
    final random = math.Random(seed.hashCode);
    final raw = List<double>.generate(50, (_) => random.nextDouble());
    return List<double>.generate(raw.length, (index) {
      final previous = index > 0 ? raw[index - 1] : raw[index];
      final next = index < raw.length - 1 ? raw[index + 1] : raw[index];
      final smoothed = (previous + raw[index] * 2 + next) / 4;
      return 0.2 + smoothed * 0.7;
    });
  }

  String _formatClock(Duration duration) {
    return formatVoiceNoteDuration(duration);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final value = controller?.value;
    final duration = value?.duration ?? Duration.zero;
    final position = value?.position ?? Duration.zero;
    final progress = !_hasError && _isReady && duration > Duration.zero
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final isPlaying = value?.isPlaying ?? false;

    // A single duration label -- the total while at rest, the elapsed time
    // once playback has actually moved -- rather than concatenating both,
    // matching how WhatsApp's own voice notes read.
    final atRest = position <= Duration.zero && !isPlaying;
    final durationLabel = _hasError
        ? 'Voice note unavailable'
        : !_isReady
            ? widget.fallbackLabel
            : atRest
                ? _formatClock(duration)
                : _formatClock(position);

    final speedLabel = _speedOptions[_speedIndex] == 1.0
        ? '1x'
        : '${_speedOptions[_speedIndex].toStringAsFixed(1).replaceAll('.0', '')}x';

    // Every row height here is trimmed to just what its content actually
    // needs (16px waveform/duration rows, 36px play button -- down from
    // 20/20/48) so the bubble itself is as short as it can be, and every
    // piece is a plain Row/Column with crossAxisAlignment.center, which
    // measures out perfectly symmetric against this bubble's own 6/6
    // top/bottom padding in a widget test. In the real app (the actual
    // "Inter" font, not a test-harness fallback) the content still reads
    // as sitting slightly high, though -- font ascent/descent metrics can
    // shift where glyphs actually paint within their line-height box in
    // ways a synthetic test won't reproduce. Trusting that direct report
    // over the test: a small top-only inset, deliberately smaller than the
    // last one (3 vs 4) so it doesn't eat back into the height reduction.
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _PlayPauseButton(
            key: const Key('voice_note_play_pause_button'),
            isPlaying: isPlaying,
            isLoading: _isInitializing,
            hasError: _hasError,
            glyphColor: widget.contentColor,
            onTap: _hasError
                ? null
                : () {
                    unawaited(_togglePlayback());
                  },
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 16,
                  // Video-player position updates arrive in discrete
                  // ticks (roughly a few times a second, not per-frame);
                  // animating toward each new value rather than snapping
                  // to it turns that into continuous, un-choppy motion.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    builder: (context, animatedProgress, _) {
                      return _PlaybackWaveform(
                        samples: _waveform,
                        progress: animatedProgress,
                        playedColor: widget.contentColor.withValues(alpha: 0.9),
                        unplayedColor:
                            widget.contentColor.withValues(alpha: 0.3),
                        knobColor: theme.colorScheme.primary,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        durationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: widget.contentColor.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (widget.trailingMeta != null) ...[
                        const Spacer(),
                        widget.trailingMeta!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Visible from the start (not just once the note has been
          // opened) so the speed control reads as a permanent part of the
          // bubble's controls. Hidden only on a genuine load failure,
          // since there's nothing to change the speed of then.
          if (!_hasError) ...[
            const SizedBox(width: 8),
            _SpeedBadge(
              key: const Key('voice_note_speed_button'),
              label: speedLabel,
              onTap: () {
                unawaited(_cycleSpeed());
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Play/pause control: a bare glyph -- no button chrome (no circle, no
/// border, no fill) -- kept as compact as the bubble's own height budget
/// allows. Press feedback is a scale animation rather than a Material
/// ripple, since a ripple would itself paint a transient circular fill.
class _PlayPauseButton extends StatefulWidget {
  const _PlayPauseButton({
    required this.isPlaying,
    required this.isLoading,
    required this.hasError,
    required this.glyphColor,
    required this.onTap,
    super.key,
  });

  final bool isPlaying;

  /// True while a tapped-but-not-yet-ready note is opening its player --
  /// a remote (Firebase-synced) voice note streams over the network here,
  /// which can take a real, visible moment. Shows a small spinner in place
  /// of the play glyph so the tap doesn't look like it did nothing.
  final bool isLoading;
  final bool hasError;
  final Color glyphColor;
  final VoidCallback? onTap;

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton> {
  // Below the platform's usual 44/48pt tap-target minimum (see
  // docs/ui_layout_guidelines.md rule 7) -- a deliberate exception this app
  // already makes for controls inline in a compact message row (see the
  // header's own visualSize pattern), traded off here specifically because
  // shrinking the bubble's overall height was the explicit ask.
  static const double _tapSize = 36;
  static const double _iconSize = 24;

  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final glyphColor = widget.hasError
        ? widget.glyphColor.withValues(alpha: 0.5)
        : widget.glyphColor;

    return SizedBox(
      width: _tapSize,
      height: _tapSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
        onTap: widget.onTap,
        child: Center(
          child: AnimatedScale(
            scale: _pressed ? 0.88 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: widget.isLoading
                  ? SizedBox(
                      key: const ValueKey<String>('loading'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: glyphColor,
                      ),
                    )
                  : Icon(
                      widget.hasError
                          ? Icons.error_outline_rounded
                          : widget.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                      key: ValueKey<String>(
                        widget.hasError
                            ? 'error'
                            : widget.isPlaying
                                ? 'pause'
                                : 'play',
                      ),
                      size: _iconSize,
                      color: glyphColor,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "1x"/"1.5x"/"2x" playback-speed toggle, styled as a small solid dark
/// badge with white text -- matching WhatsApp's own (and this app's
/// existing "badge over content" idiom, e.g. the video-attachment duration
/// overlay) rather than tinting it to the bubble's own color, since a badge
/// needs to read the same way regardless of what's behind it.
class _SpeedBadge extends StatelessWidget {
  const _SpeedBadge({
    required this.label,
    required this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 30, minHeight: 20),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackWaveform extends StatelessWidget {
  const _PlaybackWaveform({
    required this.samples,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.knobColor,
  });

  final List<double> samples;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final Color knobColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PlaybackWaveformPainter(
        samples: samples,
        progress: progress,
        playedColor: playedColor,
        unplayedColor: unplayedColor,
        knobColor: knobColor,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PlaybackWaveformPainter extends CustomPainter {
  _PlaybackWaveformPainter({
    required this.samples,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.knobColor,
  });

  final List<double> samples;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;

  /// The scrubber dot's own color -- the app's theme accent, distinct from
  /// the bars, so it pops as the one "live control" on the waveform the
  /// same way WhatsApp's own blue playhead dot does against its grey bars.
  final Color knobColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) {
      return;
    }

    // Spread the fixed sample buffer evenly across the FULL given width
    // (rather than a fixed per-bar pixel pitch, which left padding on both
    // sides whenever the bar count didn't happen to fill the canvas) --
    // the waveform should start exactly where the duration text starts and
    // reach exactly as far as the row's real right edge, matching the
    // duration/timestamp line below it instead of floating centered with
    // gaps on either side.
    final pitch = size.width / samples.length;
    final barWidth = math.max(1.2, pitch * 0.55);
    final playheadX = size.width * progress;

    for (var index = 0; index < samples.length; index++) {
      final barCenterX = pitch * index + pitch / 2;
      final amplitude = samples[index];
      final barHeight = math.max(3, amplitude * size.height);
      final top = (size.height - barHeight) / 2;
      final paint = Paint()
        ..color = barCenterX <= playheadX ? playedColor : unplayedColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;
      canvas.drawLine(
        Offset(barCenterX, top),
        Offset(barCenterX, top + barHeight),
        paint,
      );
    }

    // A plain solid dot for the playhead -- flat, no shadow/glow -- in its
    // own accent color so it reads as the one live control on the bars.
    canvas.drawCircle(
      Offset(playheadX.clamp(0.0, size.width), size.height / 2),
      4.5,
      Paint()..color = knobColor,
    );
  }

  @override
  bool shouldRepaint(covariant _PlaybackWaveformPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.progress != progress ||
        oldDelegate.playedColor != playedColor ||
        oldDelegate.unplayedColor != unplayedColor ||
        oldDelegate.knobColor != knobColor;
  }
}
