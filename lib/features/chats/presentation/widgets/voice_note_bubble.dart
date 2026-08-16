import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../updates/presentation/widgets/status_media_source.dart';
import 'voice_note_recording_session.dart';

/// Inline playable voice-note bubble with a WhatsApp-style waveform scrubber,
/// playhead dot, elapsed/total time, and a 1x playback-speed toggle.
class VoiceNoteBubble extends StatefulWidget {
  const VoiceNoteBubble({
    required this.localMediaPath,
    required this.fallbackLabel,
    this.accentColor = AppPalette.purple,
    super.key,
  });

  final String localMediaPath;
  final String fallbackLabel;
  final Color accentColor;

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
    _isInitializing = true;
    final controller = buildStatusMediaVideoController(widget.localMediaPath)
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
      });
    } catch (_) {
      controller.dispose();
      if (mounted) {
        setState(() => _hasError = true);
      }
    } finally {
      _isInitializing = false;
    }
  }

  void _handleUpdate() {
    if (mounted) {
      setState(() {});
    }
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

  List<double> _generateWaveform(String seed) {
    final random = math.Random(seed.hashCode);
    return List<double>.generate(
      36,
      (_) => 0.18 + random.nextDouble() * 0.82,
    );
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
    final elapsedLabel = !_hasError && _isReady
        ? _formatClock(position)
        : widget.fallbackLabel;
    final totalLabel =
        !_hasError && _isReady ? _formatClock(duration) : null;
    final speedLabel = _speedOptions[_speedIndex] == 1.0
        ? '1x'
        : '${_speedOptions[_speedIndex].toStringAsFixed(1).replaceAll('.0', '')}x';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Compact circular play/pause, WhatsApp sized (~38 rather than the
        // 48 IconButton.filled defaults to) so the bubble stays short.
        Material(
          color: _hasError
              ? widget.accentColor.withValues(alpha: 0.5)
              : widget.accentColor,
          shape: const CircleBorder(),
          child: InkWell(
            key: const Key('voice_note_play_pause_button'),
            customBorder: const CircleBorder(),
            onTap: _hasError
                ? null
                : () {
                    unawaited(_togglePlayback());
                  },
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(
                _hasError
                    ? Icons.error_outline_rounded
                    : isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 22,
                child: _PlaybackWaveform(
                  samples: _waveform,
                  progress: progress,
                  accentColor: widget.accentColor,
                  mutedColor: widget.accentColor.withValues(alpha: 0.28),
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Text(
                    _hasError ? 'Voice note unavailable' : elapsedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (totalLabel != null) ...[
                    Text(
                      ' · $totalLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.52),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        TextButton(
          key: const Key('voice_note_speed_button'),
          onPressed: _hasError
              ? null
              : () {
                  unawaited(_cycleSpeed());
                },
          style: TextButton.styleFrom(
            minimumSize: const Size(30, 26),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            foregroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            backgroundColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.55),
          ),
          child: Text(speedLabel),
        ),
      ],
    );
  }
}

class _PlaybackWaveform extends StatelessWidget {
  const _PlaybackWaveform({
    required this.samples,
    required this.progress,
    required this.accentColor,
    required this.mutedColor,
  });

  final List<double> samples;
  final double progress;
  final Color accentColor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PlaybackWaveformPainter(
        samples: samples,
        progress: progress,
        playedColor: accentColor,
        unplayedColor: mutedColor,
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
  });

  final List<double> samples;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) {
      return;
    }

    const barWidth = 3.0;
    const gap = 2.0;
    final totalWidth = samples.length * (barWidth + gap) - gap;
    final startX = math.max(0.0, (size.width - totalWidth) / 2);
    final playheadX = startX + totalWidth * progress;

    for (var index = 0; index < samples.length; index++) {
      final x = startX + index * (barWidth + gap);
      final barCenterX = x + barWidth / 2;
      final amplitude = samples[index];
      final barHeight = math.max(4.0, amplitude * size.height);
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

    final dotPaint = Paint()..color = playedColor;
    canvas.drawCircle(
      Offset(playheadX.clamp(startX, startX + totalWidth), size.height / 2),
      5,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PlaybackWaveformPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.progress != progress ||
        oldDelegate.playedColor != playedColor ||
        oldDelegate.unplayedColor != unplayedColor;
  }
}
