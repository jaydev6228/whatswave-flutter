import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get_video_thumbnail/get_video_thumbnail.dart';
import 'package:get_video_thumbnail/index.dart' show ImageFormat;

const int _kFilmstripFrameCount = 10;

/// Caches a video's filmstrip frames in memory, keyed by path -- the
/// composer rebuilds often while trimming (every drag frame), and
/// regenerating ~10 on-device thumbnails on every rebuild would be wasteful
/// and would flicker. Mirrors the same lifetime/caching approach as
/// `video_thumbnail_source.dart`'s single-thumbnail cache for chat bubbles.
final Map<String, Future<List<Uint8List?>>> _filmstripCache = {};

Future<List<Uint8List?>> _filmstripFramesFor(
  String videoPath,
  double durationSeconds,
) {
  final cacheKey = '$videoPath#${durationSeconds.round()}';
  return _filmstripCache.putIfAbsent(
    cacheKey,
    () => _generateFilmstrip(videoPath, durationSeconds),
  );
}

Future<List<Uint8List?>> _generateFilmstrip(
  String videoPath,
  double durationSeconds,
) async {
  final durationMs = (durationSeconds * 1000).round();
  // Fired off together instead of awaited one at a time -- sequential
  // generation left the bar visibly blank for a noticeable stretch before
  // any frame appeared, since 10 on-device thumbnail extractions in a row
  // add up even though each one alone is quick.
  final requests = List.generate(_kFilmstripFrameCount, (i) async {
    final timeMs = _kFilmstripFrameCount == 1
        ? 0
        : (durationMs * i / (_kFilmstripFrameCount - 1)).round();
    try {
      return await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        timeMs: timeMs,
        maxWidth: 160,
        quality: 40,
      );
    } catch (_) {
      return null;
    }
  });
  return Future.wait(requests);
}

String _formatTrimDuration(double seconds) {
  final totalSeconds = seconds.round().clamp(0, 359999);
  final minutes = totalSeconds ~/ 60;
  final remainingSeconds = totalSeconds % 60;
  return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
}

enum _TrimHandle { start, end, window }

/// WhatsApp-style video trim scrubber: a frame-by-frame filmstrip with a
/// highlighted selection you can drag by its edges to resize, or by its
/// middle to shift the whole window -- matching the real trim tool instead
/// of a bare line track.
class VideoTrimScrubber extends StatefulWidget {
  const VideoTrimScrubber({
    required this.videoPath,
    required this.fullDurationSeconds,
    required this.trimStartSeconds,
    required this.trimEndSeconds,
    required this.minTrimSeconds,
    required this.maxTrimSeconds,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    super.key,
  });

  final String videoPath;
  final double fullDurationSeconds;
  final double trimStartSeconds;
  final double trimEndSeconds;
  final double minTrimSeconds;
  final double maxTrimSeconds;
  final VoidCallback onScrubStart;

  /// Called continuously while a handle is being dragged. [previewSeconds]
  /// is the timestamp to show a live preview frame for -- whichever edge
  /// just moved, or the new window start when panning the whole selection.
  final void Function(RangeValues values, double previewSeconds) onScrubUpdate;
  final VoidCallback onScrubEnd;

  @override
  State<VideoTrimScrubber> createState() => _VideoTrimScrubberState();
}

class _VideoTrimScrubberState extends State<VideoTrimScrubber> {
  static const double _barHeight = 52;
  static const double _handleHitWidth = 30;

  late Future<List<Uint8List?>> _framesFuture;
  _TrimHandle? _activeHandle;
  int? _totalFileSizeBytes;

  @override
  void initState() {
    super.initState();
    _framesFuture =
        _filmstripFramesFor(widget.videoPath, widget.fullDurationSeconds);
    try {
      _totalFileSizeBytes = File(widget.videoPath).lengthSync();
    } catch (_) {
      _totalFileSizeBytes = null;
    }
  }

  @override
  void didUpdateWidget(covariant VideoTrimScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath ||
        (oldWidget.fullDurationSeconds - widget.fullDurationSeconds).abs() >
            0.5) {
      _framesFuture =
          _filmstripFramesFor(widget.videoPath, widget.fullDurationSeconds);
    }
  }

  void _handlePanStart(_TrimHandle handle) {
    setState(() => _activeHandle = handle);
    widget.onScrubStart();
  }

  void _handlePanUpdate(DragUpdateDetails details, double width) {
    final handle = _activeHandle;
    if (handle == null || width <= 0 || widget.fullDurationSeconds <= 0) {
      return;
    }
    final deltaSeconds =
        details.delta.dx / width * widget.fullDurationSeconds;
    switch (handle) {
      case _TrimHandle.start:
        final minStart =
            math.max(0.0, widget.trimEndSeconds - widget.maxTrimSeconds);
        final maxStart = math.max(
          minStart,
          widget.trimEndSeconds - widget.minTrimSeconds,
        );
        final newStart = (widget.trimStartSeconds + deltaSeconds)
            .clamp(minStart, maxStart);
        widget.onScrubUpdate(
          RangeValues(newStart, widget.trimEndSeconds),
          newStart,
        );
      case _TrimHandle.end:
        final maxEnd = math.min(
          widget.fullDurationSeconds,
          widget.trimStartSeconds + widget.maxTrimSeconds,
        );
        final minEnd = math.min(
          maxEnd,
          widget.trimStartSeconds + widget.minTrimSeconds,
        );
        final newEnd =
            (widget.trimEndSeconds + deltaSeconds).clamp(minEnd, maxEnd);
        widget.onScrubUpdate(
          RangeValues(widget.trimStartSeconds, newEnd),
          newEnd,
        );
      case _TrimHandle.window:
        // Dragging inside the selection (not on an edge handle) shifts the
        // whole window left/right, keeping its duration fixed -- WhatsApp's
        // own trimmer lets you slide the selected range to pick a different
        // part of the clip without having to resize it first.
        final span = widget.trimEndSeconds - widget.trimStartSeconds;
        final maxStart =
            math.max(0.0, widget.fullDurationSeconds - span);
        final newStart =
            (widget.trimStartSeconds + deltaSeconds).clamp(0.0, maxStart);
        widget.onScrubUpdate(
          RangeValues(newStart, newStart + span),
          newStart,
        );
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() => _activeHandle = null);
    widget.onScrubEnd();
  }

  String? _formattedFileSize(double trimSeconds) {
    final totalBytes = _totalFileSizeBytes;
    if (totalBytes == null || widget.fullDurationSeconds <= 0) {
      return null;
    }
    final estimatedBytes =
        totalBytes * (trimSeconds / widget.fullDurationSeconds);
    final megabytes = estimatedBytes / (1024 * 1024);
    return '${megabytes.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isDragging = _activeHandle != null;
    final trimSeconds = widget.trimEndSeconds - widget.trimStartSeconds;
    final fileSize = _formattedFileSize(trimSeconds);
    // Matches WhatsApp's own trim label exactly: "duration · size" at rest,
    // switching to the "start - end" range only while actively dragging so
    // you can see precisely where the selection will land.
    final label = isDragging
        ? '${_formatTrimDuration(widget.trimStartSeconds)} - '
            '${_formatTrimDuration(widget.trimEndSeconds)}'
        : fileSize != null
            ? '${_formatTrimDuration(trimSeconds)} · $fileSize'
            : _formatTrimDuration(trimSeconds);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 2),
          child: Text(
            key: const Key('updates_media_trim_duration_label'),
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              shadows: [Shadow(blurRadius: 4, color: Colors.black87)],
            ),
          ),
        ),
        _buildScrubberBar(),
      ],
    );
  }

  Widget _buildScrubberBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fullDuration =
            widget.fullDurationSeconds <= 0 ? 1.0 : widget.fullDurationSeconds;
        final startX =
            (widget.trimStartSeconds / fullDuration * width).clamp(0.0, width);
        final endX =
            (widget.trimEndSeconds / fullDuration * width).clamp(0.0, width);

        return SizedBox(
          height: _barHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: _barHeight,
                  width: width,
                  child: FutureBuilder<List<Uint8List?>>(
                    future: _framesFuture,
                    builder: (context, snapshot) {
                      final frames = snapshot.data;
                      if (frames == null) {
                        return const ColoredBox(color: Color(0xFF1C1C1E));
                      }
                      return Row(
                        children: [
                          for (final frame in frames)
                            Expanded(
                              child: frame != null
                                  ? Image.memory(
                                      frame,
                                      fit: BoxFit.cover,
                                      height: _barHeight,
                                      gaplessPlayback: true,
                                    )
                                  : const ColoredBox(
                                      color: Color(0xFF1C1C1E),
                                    ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              // Darken the trimmed-out portions -- WhatsApp's own trimmer
              // dims everything outside the selected range.
              Positioned(
                key: const Key('updates_media_trim_dim_before'),
                left: 0,
                top: 0,
                bottom: 0,
                width: startX,
                child: const IgnorePointer(
                  child: ColoredBox(color: Color(0x99000000)),
                ),
              ),
              Positioned(
                key: const Key('updates_media_trim_dim_after'),
                left: endX,
                right: 0,
                top: 0,
                bottom: 0,
                child: const IgnorePointer(
                  child: ColoredBox(color: Color(0x99000000)),
                ),
              ),
              // The selection itself -- draggable by its middle to shift
              // the whole window without resizing it (the edge handles,
              // added below on top of this, take priority right at their
              // own position so resizing still works).
              Positioned(
                key: const Key('updates_media_trim_window'),
                left: startX,
                top: 0,
                bottom: 0,
                width: math.max(endX - startX, 0),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => _handlePanStart(_TrimHandle.window),
                  onPanUpdate: (details) => _handlePanUpdate(details, width),
                  onPanEnd: _handlePanEnd,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.symmetric(
                        horizontal: BorderSide(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
              _buildHandle(
                startX,
                _TrimHandle.start,
                'updates_media_trim_start_handle',
                width,
              ),
              _buildHandle(
                endX,
                _TrimHandle.end,
                'updates_media_trim_end_handle',
                width,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHandle(
    double centerX,
    _TrimHandle handle,
    String keyValue,
    double width,
  ) {
    return Positioned(
      left: (centerX - _handleHitWidth / 2).clamp(-_handleHitWidth / 2, width),
      top: 0,
      bottom: 0,
      width: _handleHitWidth,
      child: GestureDetector(
        key: Key(keyValue),
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _handlePanStart(handle),
        onPanUpdate: (details) => _handlePanUpdate(details, width),
        onPanEnd: _handlePanEnd,
        child: Center(
          child: Container(
            width: 6,
            height: _barHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
