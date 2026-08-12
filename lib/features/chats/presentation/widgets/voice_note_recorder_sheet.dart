import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../domain/chat_attachment.dart';
import 'voice_note_recording_session.dart';

/// Opens a modal recording flow for a voice-note attachment: recording
/// starts immediately, a live waveform + duration timer count up, and the
/// user either sends (returns the finished [ChatAttachment]) or discards it
/// (returns null and deletes the recorded file).
Future<ChatAttachment?> showVoiceNoteRecorderSheet(
  BuildContext context, {
  required String threadId,
}) {
  return showModalBottomSheet<ChatAttachment>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    builder: (sheetContext) => _VoiceNoteRecorderSheet(threadId: threadId),
  );
}

enum _RecorderStage { starting, permissionDenied, recording, paused, error }

class _VoiceNoteRecorderSheet extends StatefulWidget {
  const _VoiceNoteRecorderSheet({required this.threadId});

  final String threadId;

  @override
  State<_VoiceNoteRecorderSheet> createState() =>
      _VoiceNoteRecorderSheetState();
}

class _VoiceNoteRecorderSheetState extends State<_VoiceNoteRecorderSheet> {
  final VoiceNoteRecordingSession _session = VoiceNoteRecordingSession();
  _RecorderStage _stage = _RecorderStage.starting;
  Timer? _uiTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startRecording());
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    unawaited(_session.dispose());
    super.dispose();
  }

  Future<void> _startRecording() async {
    final started = await _session.start();
    if (!mounted) {
      return;
    }
    if (!started) {
      setState(() => _stage = _RecorderStage.permissionDenied);
      return;
    }
    _uiTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted &&
          (_stage == _RecorderStage.recording ||
              _stage == _RecorderStage.paused)) {
        setState(() {});
      }
    });
    setState(() => _stage = _RecorderStage.recording);
  }

  Future<void> _togglePause() async {
    if (_stage == _RecorderStage.recording) {
      await _session.pause();
      if (mounted) {
        setState(() => _stage = _RecorderStage.paused);
      }
      return;
    }
    if (_stage == _RecorderStage.paused) {
      await _session.resume();
      if (mounted) {
        setState(() => _stage = _RecorderStage.recording);
      }
    }
  }

  Future<void> _stopAndSend() async {
    _uiTicker?.cancel();
    final attachment = await _session.finish(
      threadId: widget.threadId,
      elapsed: _session.elapsed,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(attachment);
  }

  Future<void> _discard() async {
    _uiTicker?.cancel();
    await _session.discard();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = _stage == _RecorderStage.recording ||
        _stage == _RecorderStage.paused;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_stage == _RecorderStage.permissionDenied) ...[
              const Icon(Icons.mic_off_rounded, size: 40, color: AppPalette.rose),
              const SizedBox(height: 12),
              Text('Microphone access needed', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Allow microphone access in Settings to record a voice note.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('voice_recorder_close_button'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ] else if (_stage == _RecorderStage.error) ...[
              const Icon(Icons.error_outline_rounded, size: 40, color: AppPalette.rose),
              const SizedBox(height: 12),
              Text('Could not start recording', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Check your device storage and try again.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('voice_recorder_close_button'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ] else ...[
              Row(
                children: [
                  IconButton.filledTonal(
                    key: const Key('voice_recorder_discard_button'),
                    onPressed: isActive ? _discard : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                    iconSize: 24,
                    tooltip: 'Discard',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 36,
                          child: _RecordingWaveform(samples: _session.samples),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          formatVoiceNoteDuration(_session.elapsed),
                          key: const Key('voice_recorder_timer'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_stage == _RecorderStage.recording ||
                      _stage == _RecorderStage.paused)
                    IconButton.filledTonal(
                      key: const Key('voice_recorder_pause_button'),
                      onPressed: _togglePause,
                      icon: Icon(
                        _stage == _RecorderStage.paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                      ),
                      iconSize: 24,
                      tooltip: _stage == _RecorderStage.paused
                          ? 'Resume'
                          : 'Pause',
                    ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('voice_recorder_send_button'),
                    onPressed: isActive ? _stopAndSend : null,
                    icon: const Icon(Icons.send_rounded),
                    iconSize: 22,
                    tooltip: 'Send',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _stage == _RecorderStage.paused
                    ? 'Paused'
                    : _stage == _RecorderStage.recording
                        ? 'Recording…'
                        : 'Starting…',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecordingWaveform extends StatelessWidget {
  const _RecordingWaveform({required this.samples});

  final List<double> samples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = theme.colorScheme.primary;

    return CustomPaint(
      painter: _WaveformPainter(
        samples: samples,
        color: barColor,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
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
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.samples != samples || oldDelegate.color != color;
  }
}
