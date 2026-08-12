import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../updates/presentation/widgets/status_media_source.dart';

/// An inline, playable voice-note bubble -- play/pause button, a progress
/// bar, and elapsed/total time -- matching WhatsApp's voice message player
/// instead of a plain icon+title+details row you have to tap into a
/// separate screen to hear. Reuses [VideoPlayerController] for audio-only
/// playback (a real audio track with no video track plays back fine
/// through it) rather than adding a second, audio-specific package.
class VoiceNoteBubble extends StatefulWidget {
  const VoiceNoteBubble({
    required this.localMediaPath,
    required this.fallbackLabel,
    this.accentColor = AppPalette.purple,
    super.key,
  });

  final String localMediaPath;

  /// Shown in place of the live elapsed/total time before playback has
  /// initialized (e.g. the attachment's persisted duration label).
  final String fallbackLabel;
  final Color accentColor;

  @override
  State<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends State<VoiceNoteBubble> {
  VideoPlayerController? _controller;
  bool _isReady = false;
  bool _hasError = false;
  bool _isInitializing = false;

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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
    final timeLabel = !_hasError && _isReady
        ? '${_formatDuration(position)} / ${_formatDuration(duration)}'
        : widget.fallbackLabel;
    final isPlaying = value?.isPlaying ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          IconButton.filled(
            key: const Key('voice_note_play_pause_button'),
            onPressed: _hasError
                ? null
                : () {
                    unawaited(_togglePlayback());
                  },
            icon: Icon(
              _hasError
                  ? Icons.error_outline_rounded
                  : isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
            ),
            iconSize: 20,
            style: IconButton.styleFrom(
              backgroundColor: widget.accentColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: widget.accentColor.withValues(alpha: 0.5),
              disabledForegroundColor: Colors.white70,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: widget.accentColor.withValues(alpha: 0.18),
                    valueColor: AlwaysStoppedAnimation(widget.accentColor),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _hasError ? 'Voice note unavailable' : timeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
