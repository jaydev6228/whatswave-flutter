import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/widgets/liquid_glass.dart';
import '../../domain/chat_attachment.dart';
import 'voice_note_recording_session.dart';
import 'voice_note_recorder_sheet.dart';

/// Mic button in the composer: tap opens the recorder sheet, hold starts an
/// inline recording overlay (release to send, slide left to cancel).
class ComposerVoiceButton extends StatefulWidget {
  const ComposerVoiceButton({
    required this.threadId,
    required this.enabled,
    required this.onRecorded,
    super.key,
  });

  final String threadId;
  final bool enabled;
  final ValueChanged<ChatAttachment> onRecorded;

  @override
  State<ComposerVoiceButton> createState() => _ComposerVoiceButtonState();
}

class _ComposerVoiceButtonState extends State<ComposerVoiceButton> {
  static const double _cancelSlideThreshold = 72;

  VoiceNoteRecordingSession? _session;
  OverlayEntry? _overlayEntry;
  Timer? _uiTicker;
  bool _longPressActive = false;
  bool _suppressTap = false;
  bool _cancelPending = false;
  double _dragOffsetX = 0;
  Duration _elapsed = Duration.zero;

  @override
  void dispose() {
    _removeOverlay();
    unawaited(_session?.dispose());
    super.dispose();
  }

  Future<void> _openRecorderSheet() async {
    if (!widget.enabled) {
      return;
    }
    final recorded = await showVoiceNoteRecorderSheet(
      context,
      threadId: widget.threadId,
    );
    if (!mounted || recorded == null) {
      return;
    }
    widget.onRecorded(recorded);
  }

  Future<void> _beginHoldRecording() async {
    if (!widget.enabled || _longPressActive) {
      return;
    }
    _longPressActive = true;
    _cancelPending = false;
    _dragOffsetX = 0;
    _session = VoiceNoteRecordingSession();
    final started = await _session!.start();
    if (!mounted) {
      return;
    }
    if (!started) {
      _longPressActive = false;
      await _session?.dispose();
      _session = null;
      return;
    }
    _elapsed = Duration.zero;
    _showOverlay();
    _uiTicker?.cancel();
    _uiTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _session == null) {
        return;
      }
      setState(() => _elapsed = _session!.elapsed);
      _overlayEntry?.markNeedsBuild();
    });
  }

  Future<void> _finishHoldRecording({required bool cancelled}) async {
    if (!_longPressActive) {
      return;
    }
    _longPressActive = false;
    _uiTicker?.cancel();
    _removeOverlay();

    final session = _session;
    _session = null;
    if (session == null) {
      return;
    }

    if (cancelled) {
      await session.discard();
      await session.dispose();
      return;
    }

    final attachment = await session.finish(
      threadId: widget.threadId,
      elapsed: _elapsed,
    );
    await session.dispose();
    if (!mounted || attachment == null) {
      return;
    }
    widget.onRecorded(attachment);
  }

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final theme = Theme.of(overlayContext);
        final samples = _session?.samples ?? const <double>[];
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12 + MediaQuery.paddingOf(overlayContext).bottom,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(18),
                  color: theme.colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      children: [
                        Icon(
                          _cancelPending
                              ? Icons.delete_outline_rounded
                              : Icons.mic_rounded,
                          color: _cancelPending
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: 32,
                                child: _HoldRecordingWaveform(samples: samples),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                formatVoiceNoteDuration(_elapsed),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _cancelPending ? 'Release to cancel' : 'Release to send',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.64),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_suppressTap || _longPressActive) {
          return;
        }
        unawaited(_openRecorderSheet());
      },
      onLongPressStart: (_) {
        _suppressTap = true;
        unawaited(_beginHoldRecording());
      },
      onLongPressMoveUpdate: (details) {
        if (!_longPressActive) {
          return;
        }
        final offset = details.offsetFromOrigin.dx;
        setState(() {
          _dragOffsetX = offset;
          _cancelPending = offset < -_cancelSlideThreshold;
        });
        _overlayEntry?.markNeedsBuild();
      },
      onLongPressEnd: (_) {
        unawaited(
          _finishHoldRecording(cancelled: _cancelPending),
        );
        setState(() {
          _dragOffsetX = 0;
          _cancelPending = false;
        });
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          _suppressTap = false;
        });
      },
      onLongPressCancel: () {
        unawaited(_finishHoldRecording(cancelled: true));
        setState(() {
          _dragOffsetX = 0;
          _cancelPending = false;
        });
        _suppressTap = false;
      },
      child: Transform.translate(
        offset: Offset(_longPressActive ? _dragOffsetX.clamp(-96.0, 0.0) : 0, 0),
        child: IgnorePointer(
          child: LiquidGlassIconButton(
            icon: Icons.mic_rounded,
            tooltip: 'Voice message',
            actionKey: const Key('conversation_voice_button_icon'),
            size: 44,
            iconSize: 20,
            blurred: false,
            color: widget.enabled
                ? theme.colorScheme.surface
                : theme.colorScheme.surface.withValues(alpha: 0.82),
            borderColor:
                theme.colorScheme.outlineVariant.withValues(alpha: 0.34),
            iconColor: widget.enabled
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withValues(alpha: 0.34),
            onTap: null,
          ),
        ),
      ),
    );
  }
}

class _HoldRecordingWaveform extends StatelessWidget {
  const _HoldRecordingWaveform({required this.samples});

  final List<double> samples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _HoldWaveformPainter(
        samples: samples,
        color: theme.colorScheme.primary,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _HoldWaveformPainter extends CustomPainter {
  _HoldWaveformPainter({
    required this.samples,
    required this.color,
  });

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 3.0;
    const gap = 2.0;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round;

    if (samples.isEmpty) {
      final midY = size.height / 2;
      for (var x = 0.0; x < size.width; x += barWidth + gap) {
        paint.strokeWidth = barWidth;
        canvas.drawLine(
          Offset(x + barWidth / 2, midY - 2),
          Offset(x + barWidth / 2, midY + 2),
          paint,
        );
      }
      return;
    }

    final startX = math.max(
      0.0,
      size.width - samples.length * (barWidth + gap),
    );
    for (var index = 0; index < samples.length; index++) {
      final amplitude = samples[index];
      final x = startX + index * (barWidth + gap);
      final barHeight = math.max(4.0, amplitude * size.height);
      final top = (size.height - barHeight) / 2;
      paint.strokeWidth = barWidth;
      canvas.drawLine(
        Offset(x + barWidth / 2, top),
        Offset(x + barWidth / 2, top + barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HoldWaveformPainter oldDelegate) {
    return oldDelegate.samples != samples || oldDelegate.color != color;
  }
}
