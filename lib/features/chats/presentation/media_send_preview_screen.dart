import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../domain/chat_attachment.dart';

/// What [MediaSendPreviewScreen] pops with on a real send -- the (possibly
/// rotated/annotated) attachments plus whatever caption text was entered,
/// ready to hand straight to ChatsController.sendAttachmentMessage.
class MediaSendDraft {
  const MediaSendDraft({
    required this.attachments,
    required this.caption,
  });

  final List<ChatAttachment> attachments;
  final String? caption;
}

/// A one-hop pencil stroke -- a color plus the points the finger passed
/// through while down, drawn as a single polyline over the current photo.
class _MarkupStroke {
  _MarkupStroke(this.color) : points = <Offset>[];

  final Color color;
  final List<Offset> points;
}

const List<Color> _markupPalette = [
  Colors.white,
  Colors.black,
  Color(0xFFFF3B30),
  Color(0xFFFFCC00),
  Color(0xFF34C759),
  Color(0xFF0A84FF),
];

/// WhatsApp-style "review before you send" screen -- shown after picking
/// photo/video attachments in a conversation, instead of sending them the
/// instant they're picked (see ConversationScreen._handleAttachmentTap).
/// Lets the sender add a caption, rotate a photo, and freehand-annotate it
/// with a color pencil before it actually goes out. Video gets a caption
/// only -- rotate/markup are photo-only in this first pass (video would
/// need real frame re-encoding, a much bigger feature on its own).
///
/// Edits are flattened into a brand new local image file (via
/// RepaintBoundary capture, not a pixel-manipulation package) the moment
/// they're committed -- rotate on tap, markup on checkmark -- so every
/// other place a sent photo attachment is read (message bubble, shared
/// media grid, forwarding, saving) needs zero changes: it's just an
/// ordinary photo attachment with an ordinary local file path.
class MediaSendPreviewScreen extends StatefulWidget {
  const MediaSendPreviewScreen({
    required this.attachments,
    required this.initialCaption,
    super.key,
  });

  final List<ChatAttachment> attachments;
  final String? initialCaption;

  @override
  State<MediaSendPreviewScreen> createState() => _MediaSendPreviewScreenState();
}

class _MediaSendPreviewScreenState extends State<MediaSendPreviewScreen> {
  late List<ChatAttachment> _attachments;
  late final PageController _pageController;
  late final TextEditingController _captionController;
  final GlobalKey _boundaryKey = GlobalKey();

  int _currentIndex = 0;
  bool _isMarkupMode = false;
  bool _isProcessing = false;
  Color _markupColor = _markupPalette.first;
  final List<_MarkupStroke> _strokes = <_MarkupStroke>[];

  /// Rotation applied but not yet baked into pixels -- only ever valid for
  /// the *currently visible* page (see the class doc comment: rotate
  /// flattens immediately, on this same page, rather than deferring to
  /// send time). PageView.builder only keeps nearby pages actually built,
  /// so capturing a RepaintBoundary for any other, possibly-unbuilt page
  /// would risk a null currentContext -- staying on-page sidesteps that
  /// entirely.
  int _liveQuarterTurns = 0;

  VideoPlayerController? _videoController;
  String? _activeVideoPath;

  @override
  void initState() {
    super.initState();
    _attachments = List<ChatAttachment>.of(widget.attachments);
    _pageController = PageController();
    _captionController = TextEditingController(text: widget.initialCaption);
    _configureVideoForCurrentPage();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _captionController.dispose();
    unawaited(_videoController?.dispose());
    super.dispose();
  }

  ChatAttachment get _currentAttachment => _attachments[_currentIndex];
  bool get _currentIsPhoto =>
      _currentAttachment.type == ChatAttachmentType.photo;

  void _configureVideoForCurrentPage() {
    final attachment = _currentAttachment;
    final path = attachment.localMediaPath;
    if (attachment.type != ChatAttachmentType.video || path == null) {
      return;
    }
    if (_activeVideoPath == path) {
      return;
    }
    unawaited(_videoController?.dispose());
    _activeVideoPath = path;
    final controller = VideoPlayerController.file(File(path));
    _videoController = controller;
    controller
      ..setLooping(true)
      ..initialize().then((_) {
        if (!mounted || _videoController != controller) {
          return;
        }
        setState(() {});
        controller.play();
      });
  }

  void _handlePageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _isMarkupMode = false;
      _strokes.clear();
      _liveQuarterTurns = 0;
    });
    _configureVideoForCurrentPage();
  }

  /// Rotates and immediately bakes the result into a new file, rather than
  /// tracking rotation as UI-only state to flatten later -- see
  /// _liveQuarterTurns' doc comment for why that would risk capturing an
  /// unbuilt page.
  Future<void> _rotateCurrentPhoto() async {
    if (!_currentIsPhoto || _isProcessing) {
      return;
    }
    final index = _currentIndex;
    setState(() {
      _isProcessing = true;
      _liveQuarterTurns = (_liveQuarterTurns + 1) % 4;
    });
    try {
      final bytes = await _capturePngBytes();
      final path = await _writeEditedPngFile(bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _attachments[index] =
            _attachments[index].copyWith(localMediaPath: path);
        _liveQuarterTurns = 0;
      });
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _enterMarkupMode() {
    if (!_currentIsPhoto || _isProcessing) {
      return;
    }
    setState(() {
      _isMarkupMode = true;
      _strokes.clear();
    });
  }

  void _cancelMarkupMode() {
    setState(() {
      _isMarkupMode = false;
      _strokes.clear();
    });
  }

  void _undoLastStroke() {
    if (_strokes.isEmpty) {
      return;
    }
    setState(_strokes.removeLast);
  }

  Offset _localPointFrom(Offset globalPosition) {
    final renderObject = _boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) {
      return globalPosition;
    }
    return renderObject.globalToLocal(globalPosition);
  }

  void _handleMarkupPanStart(DragStartDetails details) {
    setState(() {
      _strokes.add(_MarkupStroke(_markupColor)
        ..points.add(_localPointFrom(details.globalPosition)));
    });
  }

  void _handleMarkupPanUpdate(DragUpdateDetails details) {
    if (_strokes.isEmpty) {
      return;
    }
    setState(() {
      _strokes.last.points.add(_localPointFrom(details.globalPosition));
    });
  }

  /// Waits for a frame to actually render the current setState before
  /// capturing it -- RepaintBoundary.toImage reads whatever was last
  /// painted, so capturing right after setState (before Flutter has
  /// repainted) would grab stale pixels.
  Future<Uint8List> _capturePngBytes() async {
    await WidgetsBinding.instance.endOfFrame;
    final renderObject = _boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await renderObject.toImage(pixelRatio: 2);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData!.buffer.asUint8List();
  }

  Future<String> _writeEditedPngFile(Uint8List bytes) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final editsDirectory =
        Directory('${documentsDirectory.path}/chat_media_edits');
    await editsDirectory.create(recursive: true);
    final filename = 'edited_${DateTime.now().microsecondsSinceEpoch}.png';
    final file = File('${editsDirectory.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _confirmMarkup() async {
    if (_strokes.isEmpty) {
      setState(() => _isMarkupMode = false);
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final bytes = await _capturePngBytes();
      final path = await _writeEditedPngFile(bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _attachments[_currentIndex] =
            _attachments[_currentIndex].copyWith(localMediaPath: path);
        _isMarkupMode = false;
        _strokes.clear();
      });
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _send() {
    if (_isProcessing) {
      return;
    }
    // Nothing left to flatten here -- rotate and markup both bake into
    // pixels the moment they're committed (see _rotateCurrentPhoto and
    // _confirmMarkup), so _attachments is always already final.
    Navigator.of(context).pop(
      MediaSendDraft(
        attachments: _attachments,
        caption: _captionController.text.trim().isEmpty
            ? null
            : _captionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('media_send_preview_screen'),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: PageView.builder(
                key: const Key('media_send_preview_page_view'),
                controller: _pageController,
                physics: _isMarkupMode
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: _attachments.length,
                onPageChanged: _handlePageChanged,
                itemBuilder: (context, index) => _buildPage(index),
              ),
            ),
            if (_isMarkupMode)
              _buildMarkupToolbar(context)
            else
              _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            key: const Key('media_send_preview_close_button'),
            onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          if (_attachments.length > 1) ...[
            const Spacer(),
            Text(
              '${_currentIndex + 1}/${_attachments.length}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            const SizedBox(width: 48),
          ] else
            const Spacer(),
        ],
      ),
    );
  }

  Widget _buildPage(int index) {
    final attachment = _attachments[index];
    final isCurrent = index == _currentIndex;

    if (attachment.type == ChatAttachmentType.video) {
      final controller = isCurrent ? _videoController : null;
      if (controller == null || !controller.value.isInitialized) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }

    final path = attachment.localMediaPath;
    // existsSync, not just a null check -- a picked file can point
    // somewhere that's since become unavailable (or, in tests, never
    // existed at all), and Image.file throws asynchronously for a missing
    // file rather than failing gracefully on its own.
    if (path == null || !File(path).existsSync()) {
      return const Center(
        child:
            Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
      );
    }

    final content = RotatedBox(
      quarterTurns: isCurrent ? _liveQuarterTurns : 0,
      child: Image.file(File(path), fit: BoxFit.contain),
    );

    if (!isCurrent) {
      return Center(child: content);
    }

    return RepaintBoundary(
      key: _boundaryKey,
      // fit: StackFit.expand -- deliberately not the default loose fit.
      // PageView's per-page slot gives bounded constraints, but a loose
      // Stack sizes itself to its biggest child's own reported size
      // instead of filling that bounded box, which can collapse to a
      // degenerate (zero) size depending on how Image lays itself out
      // under BoxFit.contain with no explicit width/height -- and
      // RepaintBoundary.toImage throws ("Invalid image dimensions") on a
      // zero-size layer rather than degrading gracefully. Expanding to
      // fill the known-bounded parent guarantees a well-formed size to
      // capture.
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            content,
            if (_strokes.isNotEmpty || _isMarkupMode)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_isMarkupMode,
                  child: GestureDetector(
                    key: const Key('media_send_preview_markup_canvas'),
                    onPanStart: _handleMarkupPanStart,
                    onPanUpdate: _handleMarkupPanUpdate,
                    child: CustomPaint(
                      painter: _MarkupPainter(_strokes),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarkupToolbar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _markupPalette.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final color = _markupPalette[index];
                final isSelected = color == _markupColor;
                return GestureDetector(
                  key: Key('media_send_preview_markup_color_$index'),
                  onTap: () => setState(() => _markupColor = color),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                key: const Key('media_send_preview_markup_undo_button'),
                onPressed: _strokes.isEmpty ? null : _undoLastStroke,
                icon: const Icon(Icons.undo_rounded, color: Colors.white),
                label:
                    const Text('Undo', style: TextStyle(color: Colors.white)),
              ),
              const Spacer(),
              TextButton(
                key: const Key('media_send_preview_markup_cancel_button'),
                onPressed: _cancelMarkupMode,
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('media_send_preview_markup_done_button'),
                onPressed: _isProcessing ? null : _confirmMarkup,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_currentIsPhoto)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  key: const Key('media_send_preview_rotate_button'),
                  onPressed: _isProcessing ? null : _rotateCurrentPhoto,
                  icon: const Icon(Icons.rotate_90_degrees_ccw_rounded,
                      color: Colors.white),
                ),
                IconButton(
                  key: const Key('media_send_preview_markup_button'),
                  onPressed: _isProcessing ? null : _enterMarkupMode,
                  icon: const Icon(Icons.edit_rounded, color: Colors.white),
                ),
              ],
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: TextField(
                    key: const Key('media_send_preview_caption_field'),
                    controller: _captionController,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Add a caption…',
                      hintStyle:
                          TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.12),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Theme.of(context).colorScheme.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const Key('media_send_preview_send_button'),
                  onTap: _isProcessing ? null : _send,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: _isProcessing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MarkupPainter extends CustomPainter {
  const _MarkupPainter(this.strokes);

  final List<_MarkupStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.length < 2) {
        continue;
      }
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MarkupPainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}
