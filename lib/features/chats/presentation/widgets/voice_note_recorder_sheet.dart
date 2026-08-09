import 'dart:async';
import 'dart:io';

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
/// starts immediately, a live duration timer counts up, and the user either
/// sends (returns the finished [ChatAttachment]) or discards it (returns
/// null and deletes the recorded file). Mic access is requested via
/// `record`'s own permission check.
Future<ChatAttachment?> showVoiceNoteRecorderSheet(
  BuildContext context, {
  required String threadId,
}) {
  return showModalBottomSheet<ChatAttachment>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (sheetContext) => _VoiceNoteRecorderSheet(threadId: threadId),
  );
}

enum _RecorderStage { starting, permissionDenied, recording, error }

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
  Duration _elapsed = Duration.zero;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startRecording());
  }

  @override
  void dispose() {
    _ticker?.cancel();
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
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) {
          setState(() => _elapsed += const Duration(milliseconds: 200));
        }
      });
      setState(() => _stage = _RecorderStage.recording);
    } catch (_) {
      if (mounted) {
        setState(() => _stage = _RecorderStage.error);
      }
    }
  }

  Future<void> _stopAndSend() async {
    _ticker?.cancel();
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
    try {
      await _recorder.stop();
    } catch (_) {
      // Already stopped/never started -- nothing to clean up via stop().
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
      // Best-effort cleanup -- a leftover temp recording doesn't block
      // anything the user asked for.
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
    final isRecording = _stage == _RecorderStage.recording;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
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
              _RecordingPulse(isActive: isRecording),
              const SizedBox(height: 16),
              Text(
                _formatDuration(_elapsed),
                key: const Key('voice_recorder_timer'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isRecording ? 'Recording…' : 'Starting…',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
                ),
              ),
              const SizedBox(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    key: const Key('voice_recorder_discard_button'),
                    onPressed: isRecording ? _discard : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                    iconSize: 26,
                    tooltip: 'Discard',
                  ),
                  const SizedBox(width: 28),
                  IconButton.filled(
                    key: const Key('voice_recorder_send_button'),
                    onPressed: isRecording ? _stopAndSend : null,
                    icon: const Icon(Icons.send_rounded),
                    iconSize: 26,
                    tooltip: 'Send',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A pulsing red mic badge while recording -- the live "you're being
/// recorded" affordance every voice-message UI needs.
class _RecordingPulse extends StatefulWidget {
  const _RecordingPulse({required this.isActive});

  final bool isActive;

  @override
  State<_RecordingPulse> createState() => _RecordingPulseState();
}

class _RecordingPulseState extends State<_RecordingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          color: AppPalette.rose,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.mic_rounded, color: Colors.white, size: 32),
      ),
    );
  }
}
