import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../shared/widgets/status_motion.dart';
import '../../updates/presentation/widgets/draw_tools.dart';
import '../../updates/presentation/widgets/status_chrome.dart';
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

/// A one-hop pencil stroke -- a color, a width, and the points the finger
/// passed through while down, drawn as a single polyline over the current
/// photo. An eraser stroke is the same thing painted with BlendMode.clear
/// (see [_MarkupPainter]).
class _MarkupStroke {
  _MarkupStroke({
    required this.color,
    required this.strokeWidth,
    required this.isEraser,
  }) : points = <Offset>[];

  final Color color;
  final double strokeWidth;
  final bool isEraser;
  final List<Offset> points;
}

/// The three widths [DrawStrokeTray] offers, in logical pixels -- the
/// markup canvas works in the boundary's own coordinates, unlike the
/// status composer's frame-normalized fractions.
const List<double> _kMarkupStrokeWidths = <double>[3, 6, 12];

/// WhatsApp-style "review before you send" screen -- shown after picking
/// photo/video attachments in a conversation, instead of sending them the
/// instant they're picked (see ConversationScreen._handleAttachmentTap).
/// Rotates encoded image [bytes] a quarter turn clockwise, returning PNG.
///
/// Deliberately not a RepaintBoundary capture of the preview page (which is
/// how markup bakes its edit): that screenshots the page slot, which is the
/// whole screen's shape, so a portrait photo came back letterboxed -- its
/// transparent bars baked in as pixels. The next rotate then contained
/// *that* into the slot again, so every tap shrank the picture inside a
/// growing border. Rotating the source pixels has no letterbox to bake and
/// no resampling, so ten rotations stay as sharp as one.
Future<Uint8List> rotatePhotoBytesClockwise(
  Uint8List bytes, {
  int quarterTurns = 1,
}) async {
  final turns = quarterTurns % 4;
  if (turns == 0) {
    return bytes;
  }
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final source = frame.image;
  final width = source.width;
  final height = source.height;
  // Odd turns swap the axes; even ones keep them.
  final isQuarter = turns.isOdd;
  final targetWidth = isQuarter ? height : width;
  final targetHeight = isQuarter ? width : height;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // Rotating about the origin sweeps the image off-canvas; the translate
  // brings the rotated corner back to (0, 0).
  switch (turns) {
    case 1:
      canvas.translate(height.toDouble(), 0);
    case 2:
      canvas.translate(width.toDouble(), height.toDouble());
    case 3:
      canvas.translate(0, width.toDouble());
  }
  canvas.rotate(math.pi / 2 * turns);
  canvas.drawImage(source, Offset.zero, Paint());
  final picture = recorder.endRecording();
  final rotated = await picture.toImage(targetWidth, targetHeight);
  picture.dispose();
  source.dispose();
  codec.dispose();

  final data = await rotated.toByteData(format: ui.ImageByteFormat.png);
  rotated.dispose();
  return data!.buffer.asUint8List();
}

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
  Color _markupColor = Colors.white;
  bool _markupIsEraser = false;
  int _markupStrokeIndex = 1;
  final List<_MarkupStroke> _strokes = <_MarkupStroke>[];

  /// Path -> intrinsic width/height, so the capture surface can hug the
  /// photo instead of the page slot (see [_photoDisplayAspect]).
  final Map<String, double> _photoAspects = <String, double>{};
  final Set<String> _pendingAspectPaths = <String>{};

  /// Page index -> quarter turns the user has asked for but that are not
  /// in the file yet.
  ///
  /// Rotation used to decode, redraw and re-encode the whole photo on every
  /// tap, which on a phone-camera JPEG is most of a second of dead time
  /// behind a spinner. It is now a plain [RotatedBox] -- instant, and free
  /// to be tapped four times in a row -- and the pixels are baked once, on
  /// send. Baking no longer captures the screen (see
  /// [rotatePhotoBytesClockwise]), so unlike the old flatten-on-tap
  /// approach it does not need the page to be built.
  final Map<int, int> _quarterTurns = <int, int>{};

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

  /// Displayed width/height of the photo at [path], or null until it has
  /// decoded far enough to know. Cached per path; a rotate writes a new
  /// file, so the entry never goes stale.
  double? _photoDisplayAspect(String path, int index) {
    final intrinsic = _photoAspects[path];
    if (intrinsic == null) {
      _resolvePhotoAspect(path);
      return null;
    }
    return _turnsFor(index).isOdd ? 1 / intrinsic : intrinsic;
  }

  void _resolvePhotoAspect(String path) {
    if (_pendingAspectPaths.contains(path)) {
      return;
    }
    _pendingAspectPaths.add(path);
    final stream = FileImage(File(path)).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    void finish(double? aspect) {
      stream.removeListener(listener);
      _pendingAspectPaths.remove(path);
      if (aspect == null || !mounted) {
        return;
      }
      // Post-frame: an already-cached image calls back synchronously from
      // inside build, and setState there throws.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _photoAspects[path] = aspect);
        }
      });
    }

    listener = ImageStreamListener(
      (info, _) {
        final aspect = info.image.width / info.image.height;
        info.image.dispose();
        finish(aspect);
      },
      onError: (_, __) => finish(null),
    );
    stream.addListener(listener);
  }

  ChatAttachment get _currentAttachment => _attachments[_currentIndex];

  int _turnsFor(int index) => _quarterTurns[index] ?? 0;
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
    });
    _configureVideoForCurrentPage();
  }

  /// Rotates and immediately bakes the result into a new file, rather than
  /// tracking rotation as UI-only state to flatten later -- see
  /// _liveQuarterTurns' doc comment for why that would risk capturing an
  /// unbuilt page.
  /// Instant: the turn is UI state until send bakes it (see
  /// [_quarterTurns]).
  void _rotateCurrentPhoto() {
    if (!_currentIsPhoto || _isProcessing) {
      return;
    }
    setState(() {
      _quarterTurns[_currentIndex] = (_turnsFor(_currentIndex) + 1) % 4;
    });
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
      _strokes.add(
        _MarkupStroke(
          color: _markupColor,
          strokeWidth: _kMarkupStrokeWidths[_markupStrokeIndex],
          isEraser: _markupIsEraser,
        )..points.add(_localPointFrom(details.globalPosition)),
      );
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
        // The capture was of the rotated view, so the turn is in the file
        // now and must not be applied a second time on send.
        _quarterTurns.remove(_currentIndex);
        _isMarkupMode = false;
        _strokes.clear();
      });
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _send() async {
    if (_isProcessing) {
      return;
    }
    // Markup bakes on its own Done; rotation is still UI state, so this is
    // where it becomes pixels -- once per photo, however many times it was
    // turned, and only for the photos that were actually turned.
    if (_quarterTurns.values.any((turns) => turns % 4 != 0)) {
      setState(() => _isProcessing = true);
      try {
        await _bakePendingRotations();
      } finally {
        if (mounted) {
          setState(() => _isProcessing = false);
        }
      }
      if (!mounted) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(
      MediaSendDraft(
        attachments: _attachments,
        caption: _captionController.text.trim().isEmpty
            ? null
            : _captionController.text.trim(),
      ),
    );
  }

  Future<void> _bakePendingRotations() async {
    for (final entry in _quarterTurns.entries.toList(growable: false)) {
      final turns = entry.value % 4;
      final sourcePath = _attachments[entry.key].localMediaPath;
      if (turns == 0 || sourcePath == null || !File(sourcePath).existsSync()) {
        continue;
      }
      final rotated = await rotatePhotoBytesClockwise(
        await File(sourcePath).readAsBytes(),
        quarterTurns: turns,
      );
      final path = await _writeEditedPngFile(rotated);
      _attachments[entry.key] =
          _attachments[entry.key].copyWith(localMediaPath: path);
    }
    _quarterTurns.clear();
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
              // The draw controls float over the photo rather than sitting
              // in the toolbar below it: they must stay *outside* the
              // capture boundary (see [_buildPage]) or they would be baked
              // into the saved file along with the ink.
              child: Stack(
                children: [
                  // Tapping the photo puts the caption keyboard away. It is
                  // the only empty space on the screen, and without this
                  // there was no way to dismiss it at all -- the caption is
                  // multi-line, so Return inserts a newline rather than
                  // closing anything. Off during markup, where a tap is a
                  // dab of ink.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _isMarkupMode
                          ? null
                          : () => FocusScope.of(context).unfocus(),
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
                  ),
                  if (_isMarkupMode) ...[
                    Positioned(
                      top: 10,
                      right: 14,
                      bottom: 10,
                      child: DrawColorRail(
                        keyPrefix: 'media_send_preview_markup',
                        selectedColor: _markupColor,
                        isEraserMode: _markupIsEraser,
                        onSelectColor: (color) {
                          setState(() {
                            _markupColor = color;
                            _markupIsEraser = false;
                          });
                        },
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 10,
                      child: Center(
                        child: DrawStrokeTray(
                          keyPrefix: 'media_send_preview_markup',
                          color: _markupColor,
                          isEraserMode: _markupIsEraser,
                          onToggleEraser: () => setState(
                            () => _markupIsEraser = !_markupIsEraser,
                          ),
                          selectedStrokeIndex: _markupStrokeIndex,
                          onSelectStroke: (index) =>
                              setState(() => _markupStrokeIndex = index),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Same swap, same timing as the status composer's tool trays:
            // the caption row and the markup toolbar occupy the same strip
            // and put buttons in the same corners, so snapping between them
            // read as controls teleporting.
            StatusModeSwitcher(
              alignment: Alignment.bottomCenter,
              child: KeyedSubtree(
                key: ValueKey<bool>(_isMarkupMode),
                child: _isMarkupMode
                    ? _buildMarkupToolbar(context)
                    : _buildBottomBar(context),
              ),
            ),
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
      quarterTurns: _turnsFor(index),
      child: Image.file(File(path), fit: BoxFit.contain),
    );

    if (!isCurrent) {
      return Center(child: content);
    }

    final surface = RepaintBoundary(
      key: _boundaryKey,
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

    final aspect = _photoDisplayAspect(path, index);
    if (aspect == null) {
      // Until the photo's own proportions are known, fill the page slot.
      // A loose Stack would size to its biggest child's reported size
      // instead, and Image under BoxFit.contain reports nothing until it
      // has decoded -- RepaintBoundary.toImage throws ("Invalid image
      // dimensions") on a zero-size layer rather than degrading
      // gracefully.
      return surface;
    }
    // Once they are, the capture surface hugs the photo rather than the
    // screen-shaped slot around it. Committing markup captures this
    // boundary, so a full-slot surface baked the letterbox bars into the
    // saved file and left the picture smaller inside a new border -- the
    // same defect rotation had before _rotatePhotoFile stopped capturing
    // at all.
    return Center(
      child: AspectRatio(aspectRatio: aspect, child: surface),
    );
  }

  Widget _buildMarkupToolbar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // No hint line here. It was only shown until the first stroke
          // landed, so the toolbar lost its height mid-gesture and the
          // photo above jumped down as the user started drawing -- and the
          // rail and stroke pill say what they are well enough now that
          // they are the status composer's own controls.
          // The same chrome the status composer's draw mode uses, rather
          // than bare TextButtons -- the two are the same tool.
          Row(
            children: [
              StatusChromeButton(
                key: const Key('media_send_preview_markup_cancel_button'),
                tooltip: 'Cancel',
                icon: Icons.close_rounded,
                onTap: _cancelMarkupMode,
              ),
              const Spacer(),
              StatusChromeButtonGroup(
                children: [
                  StatusChromeButton(
                    key: const Key('media_send_preview_markup_undo_button'),
                    tooltip: 'Undo stroke',
                    icon: Icons.undo_rounded,
                    onTap: _strokes.isEmpty ? null : _undoLastStroke,
                    bare: true,
                  ),
                  StatusChromeButton(
                    key: const Key('media_send_preview_markup_done_button'),
                    tooltip: 'Done',
                    icon: Icons.check_rounded,
                    onTap: _isProcessing ? null : _confirmMarkup,
                    bare: true,
                  ),
                ],
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
                  // cw, not ccw: rotatePhotoBytesClockwise turns the
                  // photo clockwise, and the icon said otherwise.
                  icon: const Icon(Icons.rotate_90_degrees_cw_rounded,
                      color: Colors.white),
                ),
                IconButton(
                  key: const Key('media_send_preview_markup_button'),
                  onPressed: _isProcessing ? null : _enterMarkupMode,
                  icon: const Icon(Icons.edit_rounded, color: Colors.white),
                ),
              ],
            ),
          // The same glass capsule + glass send button the status composer
          // uses. A filled grey field beside a solid green circle made the
          // two "review before it goes out" bars look like different apps.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: StatusChromeCaptionField(
                  fieldKey: const Key('media_send_preview_caption_field'),
                  controller: _captionController,
                ),
              ),
              const SizedBox(width: 12),
              StatusChromeSendButton(
                actionKey: const Key('media_send_preview_send_button'),
                tooltip: 'Send',
                busy: _isProcessing,
                onTap: _send,
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
    // Painted into an offscreen layer so an eraser stroke's BlendMode.clear
    // only punches through ink laid down earlier in this same layer, never
    // the photo underneath (a separate layer beneath this CustomPaint).
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) {
        continue;
      }
      final paint = Paint()
        ..color = stroke.isEraser ? Colors.black : stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;
      if (stroke.points.length == 1) {
        // A dab, not a drag -- still ink.
        canvas.drawCircle(
          stroke.points.first,
          stroke.strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
        continue;
      }
      final path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  // Always. The strokes list is mutated in place -- it is the same List
  // instance every build -- so comparing it to the delegate's copy was
  // comparing it to itself, always false, and the canvas never repainted:
  // every stroke was recorded and none was ever drawn.
  @override
  bool shouldRepaint(covariant _MarkupPainter oldDelegate) => true;
}
