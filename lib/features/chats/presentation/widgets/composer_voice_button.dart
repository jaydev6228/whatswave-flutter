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
                child: HoldRecordingBar(
                  samples: samples,
                  elapsed: _elapsed,
                  cancelPending: _cancelPending,
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
        offset:
            Offset(_longPressActive ? _dragOffsetX.clamp(-96.0, 0.0) : 0, 0),
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

/// The bar shown over the composer while hold-to-record is active.
///
/// Extracted so its layout can be exercised directly: it only ever appears
/// behind a live microphone session, which a widget test has no way to
/// stand up.
class HoldRecordingBar extends StatelessWidget {
  const HoldRecordingBar({
    required this.samples,
    required this.elapsed,
    required this.cancelPending,
    super.key,
  });

  final List<double> samples;
  final Duration elapsed;
  final bool cancelPending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Glass, not an opaque elevated panel: this floats directly over the
    // conversation, and a filled surface slab read as a different design
    // from the composer chrome right underneath it. Tinted heavier than the
    // default so the timer and hint stay legible over a busy wallpaper.
    return LiquidGlassSurface(
      borderRadius: BorderRadius.circular(18),
      tintOpacityLight: 0.82,
      tintOpacityDark: 0.62,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Icon(
              cancelPending
                  ? Icons.delete_outline_rounded
                  : Icons.mic_rounded,
              color: cancelPending
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            // Timer and hint sit *inside* the flexible column rather than
            // beside it. A Row lays its non-flex children out at their
            // natural width first and gives Expanded whatever is left, so
            // the hint -- as a plain sibling Text -- claimed its full
            // width and overflowed the bar into black-and-yellow stripes
            // on an Android display set to a zoomed size (smaller logical
            // width, larger text scale). Nothing here has a natural width
            // to claim any more, and the hint ellipsises rather than
            // pushing.
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
                  Row(
                    children: [
                      Text(
                        formatVoiceNoteDuration(elapsed),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          cancelPending
                              ? 'Release to cancel'
                              : 'Release to send',
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.64),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
