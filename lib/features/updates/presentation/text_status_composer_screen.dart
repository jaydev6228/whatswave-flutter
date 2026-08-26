import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/status_story.dart';
import 'widgets/emoji_picker_sheet.dart';
import 'widgets/status_media_decoration_overlay.dart';
import 'widgets/text_status_canvas.dart';
import 'widgets/status_text_editing_tools.dart';

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

/// The font swatch row's height and the colour rail's width -- the editor
/// card reserves exactly these so the three controls never overlap.
const double _kTextFontRowHeight = 56;
const double _kTextRailWidth = 34;

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

  /// Whether the text is being typed right now. Drives the editor card
  /// rather than [FocusNode.hasFocus] does: the card autofocuses itself,
  /// so keying off focus alone would mean it could never appear in the
  /// first place. Starts true because a text status opens ready to type,
  /// the way WhatsApp does.
  bool _isEditing = true;

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
    _focusNode = FocusNode()
      ..addListener(() {
        // Covers the keyboard being dismissed by the system rather than by
        // a tap -- the preview should reveal itself either way.
        if (!_focusNode.hasFocus && _isEditing) {
          setState(() => _isEditing = false);
        }
      });
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
      // The canvas is a live preview of the posted story, so it must keep
      // its full size when the keyboard opens. Letting Scaffold shrink the
      // body turned the preview into a small box that showed nothing like
      // the result -- the font row below reacts to viewInsets instead.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        actions: [
          // Styling controls exist only while typing. Once the keyboard is
          // down the screen is a preview of the posted story, and a story
          // carries no toolbars -- only Close and Share survive, which are
          // navigation rather than part of the status itself.
          if (_isEditing) ...[
            IconButton(
              key: const Key('updates_cycle_font_button'),
              tooltip: 'Text alignment',
              onPressed: _cycleAlignment,
              icon: Icon(statusTextAlignmentIcon(_style.alignment)),
            ),
            IconButton(
              key: const Key('updates_text_decoration_button'),
              tooltip: 'Text background',
              onPressed: _toggleTextBackground,
              icon: Icon(
                _style.useSolidBackground
                    ? Icons.format_color_reset_rounded
                    : Icons.format_color_fill_rounded,
              ),
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
          ],
          // Fixed chrome: the action row has a hard width budget, so its
          // label is clamped rather than allowed to scale to 200% and push
          // the icons off the edge (docs/ui_layout_guidelines.md rule 4).
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: TextButton(
              key: const Key('updates_share_status_button'),
              onPressed: _canShare ? _share : null,
              child: const Text('Share'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // The preview fills the screen and never resizes -- it is the
            // posted story, so anything that shrank it would be showing a
            // layout the viewer will never see.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildComposerStage(Theme.of(context))),
                    if (_isEditing) const SizedBox(width: 10),
                    // Same continuous colour rail as the media composer's
                    // text tool, so picking a text colour works identically
                    // on both kinds of status.
                    if (_isEditing)
                      StatusTextColorRail(
                        railKey: const Key('updates_text_color_rail'),
                        barKey: const Key('updates_text_color_bar'),
                        thumbKey: const Key('updates_text_color_thumb'),
                        selectedColor: _style.textColor ?? Colors.white,
                        onSelectColor: _selectTextColor,
                      ),
                  ],
                ),
              ),
            ),
            // The editor card, confined to what is actually visible:
            // below the app bar, clear of the colour rail, and above both
            // the font row and the keyboard.
            if (_isEditing)
              Positioned(
                top: 10,
                left: 16,
                right: 16 + (_isEditing ? _kTextRailWidth + 10 : 0),
                bottom: 16 +
                    MediaQuery.viewInsetsOf(context).bottom +
                    _kTextFontRowHeight +
                    12,
                child: Center(
                  child: StatusTextEditorCard(
                    fieldKey: const Key('updates_composer_field'),
                    cardKey: const Key('updates_composer_text_card'),
                    controller: _captionController,
                    focusNode: _focusNode,
                    textStyleModel: _style,
                    hintText: 'Type your status',
                  ),
                ),
              ),
            // Fonts are picked directly from the shared swatch row, and it
            // floats over the preview riding above the keyboard rather than
            // pushing the preview up.
            if (_isEditing)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
                child: StatusTextFontStyleRow(
                  rowKey: const Key('updates_text_font_row'),
                  optionKeyBuilder: (fontId) =>
                      Key('updates_text_font_option_$fontId'),
                  selectedFontId: _style.fontId,
                  onFontSelected: _selectFont,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposerStage(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = constraints.biggest;

        return GestureDetector(
          key: const Key('updates_composer_canvas'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_selectedOverlayId != null) {
              setState(() => _selectedOverlayId = null);
              return;
            }
            // Tapping away from the text puts the keyboard down and shows
            // the story exactly as it will be posted, which is also when
            // colour/alignment/position are worth adjusting. Tapping again
            // goes back to typing -- the WhatsApp round trip.
            if (_isEditing) {
              _focusNode.unfocus();
              setState(() => _isEditing = false);
            } else {
              setState(() => _isEditing = true);
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
          onScaleEnd: _selectedOverlayId != null
              ? null
              : (_) => _pinchStartSizeScale = null,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              TextStatusCanvas(
                text: _captionController.text,
                style: _style,
                accentColor: AppPalette.emerald,
                // The very same editor the media composer's "Add text"
                // overlay uses, so the two tools behave identically rather
                // than drifting as two parallel implementations.
                // While typing the canvas holds the text back and the
                // editor card is laid out above the keyboard instead (see
                // the body Stack) -- centring it in the full-height preview
                // would drop it behind the keyboard and under the font row.
                // With the keyboard down the canvas renders its own text:
                // no card chrome, no border, precisely what gets posted.
                // Hidden outright while typing -- an empty child still
                // left the panel's own capsule painted on the preview.
                showText: !_isEditing,
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

  void _selectFont(String fontId) {
    setState(() {
      _style = _style.copyWith(fontId: fontId);
    });
  }

  void _cycleAlignment() {
    setState(() {
      _style = _style.copyWith(
        alignment: nextStatusTextAlignment(_style.alignment),
      );
    });
  }

  /// Same "decoration" affordance the media composer's text tool has --
  /// toggles a solid plate behind the text for legibility over a busy
  /// background.
  void _toggleTextBackground() {
    setState(() {
      _style = _style.copyWith(
        useSolidBackground: !_style.useSolidBackground,
      );
    });
  }

  void _selectTextColor(Color color) {
    setState(() {
      _style = _style.copyWith(textColorValue: color.toARGB32());
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
        alignment:
            layout == StatusTextLayout.poster || layout == StatusTextLayout.note
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
  State<_TextStatusOverlayItem> createState() => _TextStatusOverlayItemState();
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
