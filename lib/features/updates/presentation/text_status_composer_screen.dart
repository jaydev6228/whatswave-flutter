import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/status_story.dart';
import 'status_motion.dart';
import 'status_system_chrome.dart';
import 'widgets/emoji_picker_sheet.dart';
import 'widgets/status_chrome.dart';
import 'widgets/status_media_decoration_overlay.dart';
import 'widgets/text_status_canvas.dart';
import 'widgets/status_text_editing_tools.dart';
import 'widgets/overlay_delete_target.dart';

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
const double _kTextFontRowHeight = kStatusTextFontRowHeight;
const double _kTextRailWidth = 34;

/// Height of the floating top chrome (8pt padding + a 48pt tap target +
/// 8pt). The colour rail and the editor card start below it: the rail used
/// to run up under the Share button, where Share won the hit test and the
/// top of the track simply did not respond to drags.
const double _kTextChromeHeight = 64;
const double _kTextSizeRowHeight = kStatusTextSizeRowHeight;

/// The floating send button, matched to the media composer's so both
/// composers end on the same primary action. It sits bottom-right rather
/// than in the top chrome: a text "Share" label had to survive on top of
/// whatever background the user picked, and on the pale presets it all but
/// disappeared.
const double _kTextSendButtonSize = 54;
const double _kTextSendButtonGap = 12;

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

  /// Drag-to-delete, the same gesture the media composer offers. The badge
  /// on a selected item stays as the quick way out; this is the one that
  /// works while you are already dragging.
  final GlobalKey _deleteTargetKey = GlobalKey();
  bool _isDraggingOverlay = false;
  bool _isDeleteTargetActive = false;
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
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    // The send button is pinned to the bottom of the screen and does not
    // ride up with the keyboard: raising it left it floating in the middle
    // of the story with the preview behind it. The keyboard simply covers
    // it while typing, and it is there again the moment the keyboard goes
    // down -- which is also when there is something to send.
    const sendButtonBottom = 16.0;
    const sendButtonReach = _kTextSendButtonSize + _kTextSendButtonGap;

    // The styling rows only exist while typing, so everything above them
    // reclaims that space once the keyboard is down. They sit above
    // whichever is taller: the keyboard, or the send button when there is
    // no software keyboard to hide it (a hardware keyboard on iPad).
    final editingRowsHeight =
        _isEditing ? _kTextSizeRowHeight + _kTextFontRowHeight + 12 : 0.0;
    final stylingRowsBottom =
        16 + math.max<double>(keyboardInset, sendButtonReach);
    // The colour rail and the editor card stop above the styling rows.
    final upperControlsBottom = stylingRowsBottom + editingRowsHeight;
    return StatusStorySystemChrome(
      child: Scaffold(
        key: const Key('updates_composer_sheet'),
        backgroundColor: Colors.black,
        // The canvas is a live preview of the posted story, so it must keep
        // its full size when the keyboard opens. Letting Scaffold shrink the
        // body turned the preview into a small box that showed nothing like
        // the result -- the controls take the inset on themselves instead.
        resizeToAvoidBottomInset: false,
        // No AppBar: the posted story is edge-to-edge, so an app bar (and the
        // inset, rounded card it forced the canvas into) previewed a framed
        // layout the viewer never shows. The controls float over the preview
        // instead, exactly as they do in the media composer.
        body: LayoutBuilder(
          builder: (context, constraints) {
            // The canvas fills this box, so it is the size the posted text
            // will be measured against.
            final canvasSize = constraints.biggest;
            return Stack(
              children: [
                Positioned.fill(child: _buildComposerStage(Theme.of(context))),
                // Keeps the OS clock/battery legible over a background the
                // user picks -- including the near-white end of the colour
                // rail. Above the canvas, below the chrome, so the composer's
                // own buttons are never dimmed by it.
                const Positioned(
                  key: Key('updates_composer_status_bar_scrim'),
                  top: 0,
                  left: 0,
                  right: 0,
                  child: StatusStoryEdgeScrim(),
                ),
                // Drag an emoji down onto this to remove it -- the same
                // gesture and the same pill the media composer uses.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 40,
                  child: Center(
                    key: const Key('updates_text_delete_target_host'),
                    child: KeyedSubtree(
                      key: _deleteTargetKey,
                      child: IgnorePointer(
                        ignoring: !_isDraggingOverlay,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          offset: _isDraggingOverlay
                              ? Offset.zero
                              : const Offset(0, 0.08),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOutCubic,
                            opacity: _isDraggingOverlay ? 1 : 0,
                            child: StatusOverlayDeleteTarget(
                              key: const Key(
                                'updates_text_delete_overlay_button',
                              ),
                              isActive: _isDeleteTargetActive,
                              onTap: () {
                                final id = _selectedOverlayId;
                                if (id != null) {
                                  _endOverlayDrag(id);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Editing chrome cross-fades in and out on the feature's
                // shared timing instead of popping the instant the keyboard
                // moves, and AnimatedPositioned carries the slide as the
                // rows below it appear and disappear.
                AnimatedPositioned(
                  duration: kStatusMotionDuration,
                  curve: kStatusMotionCurve,
                  top: _kTextChromeHeight,
                  left: 16,
                  right: 16 + _kTextRailWidth + 10,
                  bottom: upperControlsBottom,
                  child: StatusModeSwitcher(
                    child: !_isEditing
                        ? const SizedBox.shrink()
                        : SafeArea(
                            bottom: false,
                            child: Center(
                              child: StatusTextEditorCard(
                                fieldKey: const Key('updates_composer_field'),
                                cardKey:
                                    const Key('updates_composer_text_card'),
                                controller: _captionController,
                                focusNode: _focusNode,
                                textStyleModel: _style,
                                // Same words the canvas shows when empty,
                                // so the prompt does not change as the
                                // keyboard comes and goes.
                                hintText: kTextStatusCanvasPlaceholder,
                                // Exactly the style the canvas will render once the
                                // keyboard is down -- a text status scales its type
                                // with the canvas and the amount typed, so a fixed
                                // editor size made typing and the result disagree.
                                textStyle:
                                    _postedTextStyle(context, canvasSize),
                              ),
                            ),
                          ),
                  ),
                ),
                // Same continuous colour rail as the media composer's text tool,
                // floating over the preview rather than taking width from it.
                AnimatedPositioned(
                  duration: kStatusMotionDuration,
                  curve: kStatusMotionCurve,
                  right: 16,
                  top: _kTextChromeHeight,
                  bottom: upperControlsBottom,
                  child: StatusModeSwitcher(
                    child: !_isEditing
                        ? const SizedBox.shrink()
                        : SafeArea(
                            bottom: false,
                            child: StatusTextColorRail(
                              railKey: const Key('updates_text_color_rail'),
                              barKey: const Key('updates_text_color_bar'),
                              thumbKey: const Key('updates_text_color_thumb'),
                              selectedColor: _style.textColor ?? Colors.white,
                              onSelectColor: _selectTextColor,
                            ),
                          ),
                  ),
                ),
                AnimatedPositioned(
                  duration: kStatusMotionDuration,
                  curve: kStatusMotionCurve,
                  left: 16,
                  right: 16,
                  bottom: stylingRowsBottom,
                  child: StatusModeSwitcher(
                    alignment: Alignment.bottomCenter,
                    child: !_isEditing
                        ? const SizedBox.shrink()
                        // Lifted clear of the home indicator, same as the
                        // send button below them, so the two stay aligned.
                        : SafeArea(
                            top: false,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StatusTextSizeWeightControls(
                                  sliderKey:
                                      const Key('updates_text_size_slider'),
                                  weightButtonKey:
                                      const Key('updates_text_weight_button'),
                                  style: _style,
                                  onSizeChanged: _setSizeScale,
                                  onWeightChanged: _setFontWeight,
                                ),
                                StatusTextFontStyleRow(
                                  rowKey: const Key('updates_text_font_row'),
                                  optionKeyBuilder: (fontId) =>
                                      Key('updates_text_font_option_$fontId'),
                                  selectedFontId: _style.fontId,
                                  onFontSelected: _selectFont,
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                // The primary action, matching the media composer's send button
                // exactly. Placed after the rail and the editor card so it wins
                // the hit test against both.
                Positioned(
                  right: 16,
                  bottom: sendButtonBottom,
                  // No keyboard offset: the button stays put. It does fade
                  // while the status is empty -- at full strength it looked
                  // live but did nothing, since there is nothing to send.
                  child: SafeArea(
                    top: false,
                    child: AnimatedOpacity(
                      duration: kStatusMotionDuration,
                      curve: kStatusMotionCurve,
                      opacity: _canShare ? 1 : 0.35,
                      child: StatusChromeSendButton(
                        actionKey: const Key('updates_share_status_button'),
                        onTap: _canShare ? _share : null,
                      ),
                    ),
                  ),
                ),
                // Floating chrome, over the full-bleed preview.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Row(
                        spacing: 8,
                        children: [
                          StatusChromeButton(
                            key: const Key('updates_close_composer_button'),
                            tooltip: 'Close',
                            icon: Icons.close_rounded,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          // The tool group absorbs the slack: it scrolls rather
                          // than overflowing when the icons plus a scaled-up
                          // Share label outgrow a narrow screen (the AppBar used
                          // to hide this by clipping for us).
                          // Styling controls exist only while typing. Once the
                          // keyboard is down the screen is a preview of the
                          // posted story, and a story carries no toolbars --
                          // only Close and Share survive, which are navigation
                          // rather than part of the status itself.
                          Expanded(
                            // ExcludeFocus: tapping a styling button used to
                            // move focus off the text field, and losing focus
                            // is what ends editing -- so shuffling the style or
                            // changing the background dropped the keyboard
                            // instead of just restyling. These buttons act on
                            // the text; they never need focus themselves.
                            child: StatusModeSwitcher(
                              alignment: Alignment.centerRight,
                              child: !_isEditing
                                  ? const SizedBox.shrink()
                                  : ExcludeFocus(
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        reverse: true,
                                        child: Row(spacing: 8, children: [
                                          StatusChromeButton(
                                            key: const Key(
                                                'updates_cycle_font_button'),
                                            tooltip: 'Text alignment',
                                            icon: statusTextAlignmentIcon(
                                                _style.alignment),
                                            onTap: () =>
                                                _restyle(_cycleAlignment),
                                          ),
                                          StatusChromeButton(
                                            key: const Key(
                                                'updates_text_decoration_button'),
                                            tooltip: 'Text background',
                                            icon: _style.useSolidBackground
                                                ? Icons
                                                    .format_color_reset_rounded
                                                : Icons
                                                    .format_color_fill_rounded,
                                            onTap: () =>
                                                _restyle(_toggleTextBackground),
                                          ),
                                          StatusChromeButton(
                                            key: const Key(
                                                'updates_cycle_background_button'),
                                            tooltip: 'Change background color',
                                            icon: Icons.palette_outlined,
                                            onTap: () =>
                                                _restyle(_cycleBackground),
                                          ),
                                          StatusChromeButton(
                                            key: const Key(
                                                'updates_add_text_emoji_button'),
                                            tooltip: 'Add emoji',
                                            icon: Icons.emoji_emotions_outlined,
                                            onTap: _openEmojiPicker,
                                          ),
                                          StatusChromeButton(
                                            key: const Key(
                                                'updates_randomize_text_style_button'),
                                            tooltip: 'Shuffle style',
                                            icon: Icons.auto_awesome_rounded,
                                            onTap: () => _restyle(_shuffleLook),
                                          ),
                                        ]),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
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
                      sizeScale: (start * details.scale).clamp(
                          kStatusTextMinSizeScale, kStatusTextMaxSizeScale),
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
                // Edge-to-edge and unframed, exactly how the viewer renders
                // a posted text status -- the rounded, bordered card the
                // composer used to show was a frame the story never has.
                borderRadius: BorderRadius.zero,
                showFrame: false,
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
                  onDragStart: () => setState(() {
                    _isDraggingOverlay = true;
                    _isDeleteTargetActive = false;
                    _selectedOverlayId = item.id;
                  }),
                  onDragUpdate: _updateDeleteTargetHover,
                  onDragEnd: () => _endOverlayDrag(item.id),
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

  /// What the canvas will actually lay out -- the typed text, or the
  /// placeholder while it is empty, matching TextStatusCanvas.
  String get _visibleCanvasText {
    final typed = _captionController.text.trim();
    return typed.isEmpty ? kTextStatusCanvasPlaceholder : typed;
  }

  /// The style the canvas itself will use once the text is committed --
  /// the single source of truth for "what this will look like posted".
  /// [canvasSize] is the box the canvas actually lays out in, not
  /// MediaQuery's -- the two differ under `setSurfaceSize`, and sizing the
  /// editor from a different box than the canvas is exactly the mismatch
  /// this method exists to prevent.
  TextStyle _postedTextStyle(BuildContext context, Size canvasSize) {
    final size = canvasSize;
    return buildTextStatusTextStyle(
      theme: Theme.of(context),
      style: _style,
      accentColor: AppPalette.emerald,
      shortestSide: math.min(size.width, size.height),
      // Exactly what the canvas measures: the visible text, falling back to
      // the placeholder when empty. Passing a floored length instead put
      // the editor in a different size tier from the posted result.
      textLength: _visibleCanvasText.length,
    );
  }

  void _setSizeScale(double scale) {
    setState(() {
      _style = _style.copyWith(sizeScale: scale);
    });
  }

  void _setFontWeight(int index) {
    setState(() {
      _style = _style.copyWith(fontWeightIndex: index);
    });
  }

  void _selectFont(String fontId) {
    setState(() {
      _style = _style.copyWith(fontId: fontId);
    });
  }

  /// Applies a styling change without ending editing.
  ///
  /// Tapping a toolbar button moves focus off the text field, and focus
  /// loss is what drops out of editing -- so restyling used to dismiss the
  /// keyboard as a side effect. Styling acts on the text; the text keeps
  /// the caret.
  void _restyle(VoidCallback apply) {
    apply();
    // The tap's focus change reaches the focus listener before this runs,
    // so editing may already have been flipped off by the time we get
    // here -- restore it rather than testing for it. These buttons only
    // exist while editing, so there is no other state to preserve.
    if (!_isEditing) {
      setState(() => _isEditing = true);
    }
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
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
      // Only the canvas background changes. The text plate is the user's
      // own choice from the fill button and survives -- this used to reset
      // it, so picking a plate and then a colour lost the plate.
      _style = _style.copyWith(
        backgroundId: kTextStatusBackgroundPresets[nextIndex].id,
        clearBackgroundColor: true,
      );
    });
  }

  Future<void> _openEmojiPicker() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      // Transparent so the sheet's own glass shows the story behind it.
      // Explicitly off, overriding the app theme's global
      // showDragHandle: true. StatusChromeSheet draws its own handle
      // inside the glass -- Flutter's renders in the sheet's own area,
      // which is transparent here, so both showed at once.
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) => const StatusChromeSheet(child: EmojiPickerSheet()),
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

  /// Lights the target while the finger is over it.
  void _updateDeleteTargetHover(Offset globalFocalPoint) {
    final deleteContext = _deleteTargetKey.currentContext;
    if (!_isDraggingOverlay || deleteContext == null) {
      if (_isDeleteTargetActive) {
        setState(() => _isDeleteTargetActive = false);
      }
      return;
    }
    final box = deleteContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return;
    }
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final isHovering = rect.inflate(12).contains(globalFocalPoint);
    if (isHovering == _isDeleteTargetActive) {
      return;
    }
    setState(() => _isDeleteTargetActive = isHovering);
  }

  void _endOverlayDrag(String itemId) {
    final shouldDelete = _isDeleteTargetActive;
    setState(() {
      _isDraggingOverlay = false;
      _isDeleteTargetActive = false;
      if (shouldDelete) {
        _overlayItems.removeWhere((o) => o.id == itemId);
        if (_selectedOverlayId == itemId) {
          _selectedOverlayId = null;
        }
      }
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

    setState(() {
      // Shuffles the *look* -- font, background, layout, size -- while
      // keeping the choices the user made deliberately. Building a fresh
      // StatusTextStyle silently dropped the picked text colour and
      // weight, so shuffling reset the text to white with no way to tell
      // that had happened.
      _style = _style.copyWith(
        fontId: font.id,
        backgroundId: background.id,
        layout: layout,
        alignment:
            layout == StatusTextLayout.poster || layout == StatusTextLayout.note
                ? StatusTextAlignment.left
                : StatusTextAlignment.center,
        sizeScale: 0.88 + (random.nextDouble() * 0.4),
        clearBackgroundColor: true,
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
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    super.key,
  });

  final StatusMediaOverlayItem item;
  final Size canvasSize;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<StatusMediaOverlayItem> onChanged;

  /// Drag lifecycle, so the screen can light and hit-test its delete target.
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  State<_TextStatusOverlayItem> createState() => _TextStatusOverlayItemState();
}

class _TextStatusOverlayItemState extends State<_TextStatusOverlayItem> {
  StatusMediaOverlayItem? _gestureAnchor;
  Offset? _gestureStartFocalPoint;
  StatusMediaOverlayItem? _resizeAnchor;

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
                widget.onDragStart();
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
                widget.onDragUpdate(details.focalPoint);
              },
              onScaleEnd: (_) {
                _gestureAnchor = null;
                _gestureStartFocalPoint = null;
                widget.onDragEnd();
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
        // A corner handle, where the close badge used to sit. Deleting is
        // the drag-to-target gesture now, the same as the media composer's,
        // so a second way out on the item itself was one affordance too
        // many -- and pinching to resize had none at all, which is the part
        // that was actually undiscoverable.
        if (widget.isSelected)
          Center(
            child: Transform.translate(
              offset: offset + Offset(22 * item.scale, 22 * item.scale),
              child: GestureDetector(
                key: const Key('updates_text_overlay_resize_handle'),
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => _resizeAnchor = item,
                onPanUpdate: (details) {
                  final anchor = _resizeAnchor;
                  if (anchor == null) {
                    return;
                  }
                  // Dragging away from the middle grows it. Both axes count,
                  // so a diagonal drag -- the natural one for a corner --
                  // moves at the rate it looks like it should.
                  final growth = (details.delta.dx + details.delta.dy) / 90;
                  widget.onChanged(
                    anchor.copyWith(
                      scale: (item.scale + growth).clamp(0.5, 3.0),
                    ),
                  );
                },
                onPanEnd: (_) => _resizeAnchor = null,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.7),
                      width: 1.2,
                    ),
                  ),
                  child: const Icon(
                    Icons.open_in_full_rounded,
                    size: 13,
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
