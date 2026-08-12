import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../app/theme/app_palette.dart';
import '../../domain/chat_attachment.dart';

/// A minimum-viable recording length -- anything shorter almost certainly
/// means an accidental tap rather than an intended voice note, so it's
/// discarded quietly instead of sending a near-silent blip.
const Duration _minimumVoiceNoteDuration = Duration(milliseconds: 500);

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
  final AudioRecorder _recorder = AudioRecorder();
  _RecorderStage _stage = _RecorderStage.starting;
  Timer? _ticker;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  Duration _elapsed = Duration.zero;
  String? _recordingPath;
  final List<double> _waveformSamples = <double>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startRecording());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_amplitudeSubscription?.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _startRecording() async {
    bool hasPermission;
    try {
      hasPermission = await _recorder.hasPermission();
    } catch (_) {
      hasPermission = false;
    }
    if (!mounted) {
      return;
    }
    if (!hasPermission) {
      setState(() => _stage = _RecorderStage.permissionDenied);
      return;
    }

    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final voiceNotesDirectory =
          Directory('${documentsDirectory.path}/voice_notes');
      await voiceNotesDirectory.create(recursive: true);
      final path =
          '${voiceNotesDirectory.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) {
        return;
      }
      _recordingPath = path;
      _elapsed = Duration.zero;
      _waveformSamples.clear();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted && _stage == _RecorderStage.recording) {
          setState(() => _elapsed += const Duration(milliseconds: 200));
        }
      });
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((amplitude) {
        if (!mounted || _stage != _RecorderStage.recording) {
          return;
        }
        final normalized = _normalizeAmplitude(amplitude.current);
        setState(() {
          _waveformSamples.add(normalized);
          if (_waveformSamples.length > 48) {
            _waveformSamples.removeAt(0);
          }
        });
      });
      setState(() => _stage = _RecorderStage.recording);
    } catch (_) {
      if (mounted) {
        setState(() => _stage = _RecorderStage.error);
      }
    }
  }

  double _normalizeAmplitude(double decibels) {
    if (decibels.isNaN || decibels <= -60) {
      return 0.08;
    }
    return ((decibels + 60) / 60).clamp(0.08, 1.0);
  }

  Future<void> _togglePause() async {
    if (_stage == _RecorderStage.recording) {
      await _recorder.pause();
      if (mounted) {
        setState(() => _stage = _RecorderStage.paused);
      }
      return;
    }
    if (_stage == _RecorderStage.paused) {
      await _recorder.resume();
      if (mounted) {
        setState(() => _stage = _RecorderStage.recording);
      }
    }
  }

  Future<void> _stopAndSend() async {
    _ticker?.cancel();
    await _amplitudeSubscription?.cancel();
    String? finalPath;
    try {
      finalPath = await _recorder.stop();
    } catch (_) {
      finalPath = null;
    }
    finalPath ??= _recordingPath;
    if (!mounted) {
      return;
    }

    if (finalPath == null || _elapsed < _minimumVoiceNoteDuration) {
      if (finalPath != null) {
        unawaited(_tryDeleteFile(finalPath));
      }
      Navigator.of(context).pop();
      return;
    }

    final attachment = ChatAttachment(
      id: '${widget.threadId}-voice-${DateTime.now().microsecondsSinceEpoch}',
      type: ChatAttachmentType.voiceNote,
      title: 'Voice note',
      details: _formatDuration(_elapsed),
      tintColor: AppPalette.purple,
      aspectRatio: 1.55,
      localMediaPath: finalPath,
    );
    Navigator.of(context).pop(attachment);
  }

  Future<void> _discard() async {
    _ticker?.cancel();
    await _amplitudeSubscription?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {
      // Already stopped/never started.
    }
    final path = _recordingPath;
    if (path != null) {
      unawaited(_tryDeleteFile(path));
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _tryDeleteFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
                          child: _RecordingWaveform(samples: _waveformSamples),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatDuration(_elapsed),
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
