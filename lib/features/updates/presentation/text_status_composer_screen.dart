import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/status_story.dart';
import 'widgets/emoji_picker_sheet.dart';
import 'widgets/status_media_decoration_overlay.dart';
import 'widgets/text_status_canvas.dart';

class TextStatusComposerDraft {
  const TextStatusComposerDraft({
    required this.caption,
    required this.textStyle,
    this.overlayItems = const <StatusMediaOverlayItem>[],
  });

  final String caption;
  final StatusTextStyle textStyle;
  final List<StatusMediaOverlayItem> overlayItems;
}

class TextStatusComposerScreen extends StatefulWidget {
  const TextStatusComposerScreen({
    super.key,
    this.initialDraft,
  });

  final TextStatusComposerDraft? initialDraft;

  @override
  State<TextStatusComposerScreen> createState() =>
      _TextStatusComposerScreenState();
}

class _TextStatusComposerScreenState extends State<TextStatusComposerScreen> {
  static const StatusTextStyle _defaultStyle = StatusTextStyle(
    fontId: 'banner',
    backgroundId: 'midnight_drive',
    layout: StatusTextLayout.banner,
    alignment: StatusTextAlignment.center,
    sizeScale: 1,
  );

  late final TextEditingController _captionController;
  late final FocusNode _focusNode;
  late StatusTextStyle _style;
  final List<StatusMediaOverlayItem> _overlayItems = <StatusMediaOverlayItem>[];
  String? _selectedOverlayId;
  int _nextOverlaySeed = 0;
  double? _pinchStartSizeScale;

  bool get _canShare => _captionController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final initialDraft = widget.initialDraft;
    _captionController = TextEditingController(
      text: initialDraft?.caption ?? '',
    )..addListener(() {
        setState(() {});
      });
    _focusNode = FocusNode();
    _style = initialDraft?.textStyle ?? _defaultStyle;
    _overlayItems.addAll(initialDraft?.overlayItems ?? const []);
  }

  @override
  void dispose() {
    _captionController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('updates_composer_sheet'),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        actions: [
          IconButton(
            key: const Key('updates_cycle_font_button'),
            tooltip: 'Change font',
            onPressed: _cycleFont,
            icon: const Icon(Icons.font_download_outlined),
          ),
          IconButton(
            key: const Key('updates_cycle_background_button'),
            tooltip: 'Change background color',
            onPressed: _cycleBackground,
            icon: const Icon(Icons.palette_outlined),
          ),
          IconButton(
            key: const Key('updates_add_text_emoji_button'),
            tooltip: 'Add emoji',
            onPressed: _openEmojiPicker,
            icon: const Icon(Icons.emoji_emotions_outlined),
          ),
          IconButton(
            key: const Key('updates_randomize_text_style_button'),
            tooltip: 'Shuffle style',
            onPressed: _shuffleLook,
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
          TextButton(
            key: const Key('updates_share_status_button'),
            onPressed: _canShare ? _share : null,
            child: const Text('Share'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: _buildComposerStage(Theme.of(context)),
        ),
      ),
    );
  }

  Widget _buildComposerStage(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = constraints.biggest;
        final shortestSide = math.min(canvasSize.width, canvasSize.height);
        final textStyle = buildTextStatusTextStyle(
          theme: theme,
          style: _style,
          accentColor: AppPalette.emerald,
          shortestSide: shortestSide,
          textLength: math.max(_captionController.text.trim().length, 24),
        );
        const hintText = 'Type your status';

        return GestureDetector(
          key: const Key('updates_composer_canvas'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_selectedOverlayId != null) {
              setState(() => _selectedOverlayId = null);
            } else {
              _focusNode.requestFocus();
            }
          },
          // Pinch-to-scale the text itself -- matches WhatsApp's real text
          // status, which has no separate size slider at all. Disabled
          // whenever an overlay is selected so this outer recognizer
          // doesn't compete with that overlay's own drag/pinch handling for
          // the same pointer.
          onScaleStart: _selectedOverlayId != null
              ? null
              : (_) => _pinchStartSizeScale = _style.sizeScale,
          onScaleUpdate: _selectedOverlayId != null
              ? null
              : (details) {
                  final start = _pinchStartSizeScale;
                  if (start == null) {
                    return;
                  }
                  setState(() {
                    _style = _style.copyWith(
                      sizeScale: (start * details.scale).clamp(0.6, 2.2),
                    );
                  });
                },
          onScaleEnd:
              _selectedOverlayId != null ? null : (_) => _pinchStartSizeScale = null,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              TextStatusCanvas(
                text: _captionController.text,
                style: _style,
                accentColor: AppPalette.emerald,
                textChild: TextField(
                  key: const Key('updates_composer_field'),
                  focusNode: _focusNode,
                  controller: _captionController,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  maxLines: null,
                  maxLength: 240,
                  buildCounter: (
                    _, {
                    required int currentLength,
                    required bool isFocused,
                    required int? maxLength,
                  }) =>
                      null,
                  textAlign: textStatusTextAlign(_style.alignment),
                  style: textStyle,
                  cursorColor: textStyle.color ?? theme.colorScheme.onPrimary,
                  decoration: InputDecoration.collapsed(
                    hintText: hintText,
                    hintStyle: textStyle.copyWith(
                      color: textStyle.color?.withValues(alpha: 0.42),
                    ),
                  ),
                ),
              ),
              for (final item in _overlayItems)
                _TextStatusOverlayItem(
                  key: ValueKey(item.id),
                  item: item,
                  canvasSize: canvasSize,
                  isSelected: _selectedOverlayId == item.id,
                  onTap: () => setState(() => _selectedOverlayId = item.id),
                  onDelete: () => setState(() {
                    _overlayItems.removeWhere((o) => o.id == item.id);
                    if (_selectedOverlayId == item.id) {
                      _selectedOverlayId = null;
                    }
                  }),
                  onChanged: (updated) => setState(() {
                    final index =
                        _overlayItems.indexWhere((o) => o.id == item.id);
                    if (index != -1) {
                      _overlayItems[index] = updated;
                    }
                  }),
                ),
            ],
          ),
        );
      },
    );
  }

  void _cycleFont() {
    final currentIndex =
        kTextStatusFontLooks.indexWhere((look) => look.id == _style.fontId);
    final nextIndex = (currentIndex + 1) % kTextStatusFontLooks.length;
    setState(() {
      _style = _style.copyWith(fontId: kTextStatusFontLooks[nextIndex].id);
    });
  }

  void _cycleBackground() {
    final currentIndex = kTextStatusBackgroundPresets
        .indexWhere((preset) => preset.id == _style.backgroundId);
    final nextIndex = (currentIndex + 1) % kTextStatusBackgroundPresets.length;
    setState(() {
      _style = _style.copyWith(
        backgroundId: kTextStatusBackgroundPresets[nextIndex].id,
        clearBackgroundColor: true,
        useSolidBackground: false,
      );
    });
  }

  Future<void> _openEmojiPicker() async {
    final theme = Theme.of(context);
    final emoji = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) => const EmojiPickerSheet(),
    );
    if (!mounted || emoji == null || emoji.isEmpty) {
      return;
    }

    final id = 'text-emoji-$_nextOverlaySeed';
    _nextOverlaySeed += 1;
    setState(() {
      _overlayItems.add(
        StatusMediaOverlayItem(
          id: id,
          type: StatusMediaOverlayType.emoji,
          label: emoji,
          positionDx: 0.5,
          positionDy: 0.3,
          scale: 1.3,
        ),
      );
      _selectedOverlayId = id;
    });
  }

  void _shuffleLook() {
    final random = math.Random();
    final font =
        kTextStatusFontLooks[random.nextInt(kTextStatusFontLooks.length)];
    final background = kTextStatusBackgroundPresets[
        random.nextInt(kTextStatusBackgroundPresets.length)];
    final layout =
        StatusTextLayout.values[random.nextInt(StatusTextLayout.values.length)];

    _dismissKeyboard();
    setState(() {
      _style = StatusTextStyle(
        fontId: font.id,
        backgroundId: background.id,
        layout: layout,
        alignment: layout == StatusTextLayout.poster ||
                layout == StatusTextLayout.note
            ? StatusTextAlignment.left
            : StatusTextAlignment.center,
        sizeScale: 0.88 + (random.nextDouble() * 0.4),
      );
    });
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  void _share() {
    if (!_canShare) {
      return;
    }

    _dismissKeyboard();
    Navigator.of(context).pop(
      TextStatusComposerDraft(
        caption: _captionController.text.trim(),
        textStyle: _style,
        overlayItems: List<StatusMediaOverlayItem>.unmodifiable(_overlayItems),
      ),
    );
  }
}

class _TextStatusOverlayItem extends StatefulWidget {
  const _TextStatusOverlayItem({
    required this.item,
    required this.canvasSize,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onChanged,
    super.key,
  });

  final StatusMediaOverlayItem item;
  final Size canvasSize;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<StatusMediaOverlayItem> onChanged;

  @override
  State<_TextStatusOverlayItem> createState() =>
      _TextStatusOverlayItemState();
}

class _TextStatusOverlayItemState extends State<_TextStatusOverlayItem> {
  StatusMediaOverlayItem? _gestureAnchor;
  Offset? _gestureStartFocalPoint;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final canvasSize = widget.canvasSize;
    final offset = statusStoryOverlayOffsetFor(canvasSize, item);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Center(
          child: Transform.translate(
            offset: offset,
            // The draggable content lives in its own GestureDetector, kept
            // free of any other tappable descendant (like the delete badge
            // below) -- nesting a second GestureDetector inside this one
            // put its TapGestureRecognizer in the same arena as this
            // widget's own Scale/Tap recognizers, and the delete tap lost
            // that race more often than not.
            child: GestureDetector(
              onTap: widget.onTap,
              onScaleStart: (details) {
                _gestureAnchor = item;
                _gestureStartFocalPoint = details.focalPoint;
              },
              onScaleUpdate: (details) {
                final anchor = _gestureAnchor;
                final startFocalPoint = _gestureStartFocalPoint;
                if (anchor == null ||
                    startFocalPoint == null ||
                    canvasSize.width <= 0 ||
                    canvasSize.height <= 0) {
                  return;
                }
                final delta = details.focalPoint - startFocalPoint;
                final nextDx =
                    ((anchor.positionDx * canvasSize.width) + delta.dx) /
                        canvasSize.width;
                final nextDy =
                    ((anchor.positionDy * canvasSize.height) + delta.dy) /
                        canvasSize.height;
                widget.onChanged(
                  anchor.copyWith(
                    positionDx: nextDx.clamp(0.06, 0.94),
                    positionDy: nextDy.clamp(0.06, 0.94),
                    scale: (anchor.scale * details.scale).clamp(0.5, 3.0),
                    rotation: anchor.rotation + details.rotation,
                  ),
                );
              },
              onScaleEnd: (_) {
                _gestureAnchor = null;
                _gestureStartFocalPoint = null;
              },
              child: Transform.rotate(
                angle: item.rotation,
                child: Transform.scale(
                  scale: item.scale,
                  child: Container(
                    decoration: widget.isSelected
                        ? BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.7),
                              width: 1.4,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          )
                        : null,
                    padding: const EdgeInsets.all(4),
                    child: StatusOverlayContent(
                      item: item,
                      compact: false,
                      accentColor: item.accentColor ?? AppPalette.emerald,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.isSelected)
          Center(
            child: Transform.translate(
              offset: offset + Offset(20 * item.scale, -20 * item.scale),
              child: GestureDetector(
                key: const Key('updates_text_overlay_delete_button'),
                onTap: widget.onDelete,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
