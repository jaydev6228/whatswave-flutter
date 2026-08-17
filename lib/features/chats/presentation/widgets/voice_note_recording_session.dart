import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../app/theme/app_palette.dart';
import '../../domain/chat_attachment.dart';

/// Minimum recording length before a voice note is worth sending.
const Duration minimumVoiceNoteDuration = Duration(milliseconds: 500);

/// Sliding-window cap on how many live amplitude samples
/// [VoiceNoteRecordingSession] keeps -- the buffer never grows past this,
/// even for a long recording. The waveform painter divides its width by
/// this fixed capacity (not the live, still-ramping-up sample count) so
/// bars start at their final thin size from the first sample instead of
/// beginning as a few oversized blobs that shrink as more arrive.
const int voiceNoteWaveformSampleCap = 48;

/// Shared mic capture used by the recorder sheet and hold-to-record.
class VoiceNoteRecordingSession {
  VoiceNoteRecordingSession();

  final AudioRecorder _recorder = AudioRecorder();

  Timer? _ticker;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  Duration _elapsed = Duration.zero;
  String? _recordingPath;
  final List<double> waveformSamples = <double>[];
  bool _isRecording = false;
  bool _isPaused = false;

  Duration get elapsed => _elapsed;
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  List<double> get samples => List.unmodifiable(waveformSamples);

  Future<bool> start() async {
    if (_isRecording) {
      return true;
    }

    bool hasPermission;
    try {
      hasPermission = await _recorder.hasPermission();
    } catch (_) {
      hasPermission = false;
    }
    if (!hasPermission) {
      return false;
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
      _recordingPath = path;
      _elapsed = Duration.zero;
      waveformSamples.clear();
      _isRecording = true;
      _isPaused = false;
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_isRecording && !_isPaused) {
          _elapsed += const Duration(milliseconds: 200);
        }
      });
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((amplitude) {
        if (!_isRecording || _isPaused) {
          return;
        }
        final normalized = _normalizeAmplitude(amplitude.current);
        waveformSamples.add(normalized);
        if (waveformSamples.length > voiceNoteWaveformSampleCap) {
          waveformSamples.removeAt(0);
        }
      });
      return true;
    } catch (_) {
      await _tryDeleteFile(_recordingPath);
      _recordingPath = null;
      return false;
    }
  }

  Future<void> pause() async {
    if (!_isRecording || _isPaused) {
      return;
    }
    await _recorder.pause();
    _isPaused = true;
  }

  Future<void> resume() async {
    if (!_isRecording || !_isPaused) {
      return;
    }
    await _recorder.resume();
    _isPaused = false;
  }

  Future<ChatAttachment?> finish({
    required String threadId,
    required Duration elapsed,
  }) async {
    _ticker?.cancel();
    await _amplitudeSubscription?.cancel();
    String? finalPath;
    try {
      finalPath = await _recorder.stop();
    } catch (_) {
      finalPath = null;
    }
    finalPath ??= _recordingPath;
    _resetState();

    if (finalPath == null || elapsed < minimumVoiceNoteDuration) {
      if (finalPath != null) {
        unawaited(_tryDeleteFile(finalPath));
      }
      return null;
    }

    return ChatAttachment(
      id: '$threadId-voice-${DateTime.now().microsecondsSinceEpoch}',
      type: ChatAttachmentType.voiceNote,
      title: 'Voice note',
      details: formatVoiceNoteDuration(elapsed),
      tintColor: AppPalette.purple,
      aspectRatio: 1.55,
      localMediaPath: finalPath,
    );
  }

  Future<void> discard() async {
    _ticker?.cancel();
    await _amplitudeSubscription?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {
      // Already stopped.
    }
    final path = _recordingPath;
    _resetState();
    if (path != null) {
      unawaited(_tryDeleteFile(path));
    }
  }

  Future<void> dispose() async {
    await discard();
    await _recorder.dispose();
  }

  void _resetState() {
    _ticker?.cancel();
    _ticker = null;
    _amplitudeSubscription = null;
    _recordingPath = null;
    _elapsed = Duration.zero;
    waveformSamples.clear();
    _isRecording = false;
    _isPaused = false;
  }

  double _normalizeAmplitude(double decibels) {
    if (decibels.isNaN || decibels <= -60) {
      return 0.08;
    }
    return ((decibels + 60) / 60).clamp(0.08, 1.0);
  }

  Future<void> _tryDeleteFile(String? path) async {
    if (path == null) {
      return;
    }
    try {
      await File(path).delete();
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}

String formatVoiceNoteDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (minutes > 0) {
    return '$minutes:$seconds';
  }
  return '0:$seconds';
}
