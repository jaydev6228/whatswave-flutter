import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/widgets/liquid_glass.dart';
import '../application/layout_exporter.dart';
import '../application/layout_picked_image_store.dart';
import '../data/layout_catalog.dart';
import '../models/layout_models.dart';
import '../../presentation/status_system_chrome.dart';
import '../../presentation/widgets/status_chrome.dart';
import '../../presentation/widgets/status_story_media_surface.dart';
import '../../presentation/widgets/status_text_editing_tools.dart';
import 'widgets/layout_canvas.dart';
import 'widgets/layout_pickers.dart';
import 'widgets/layout_slot_toolbar.dart';

/// Height of the bottom tool dock without slot tools (mode toggle + picker rail).
const double _kLayoutDockBaseHeight = 190;

/// Extra dock height when Replace / Remove / look chips are visible.
const double _kLayoutDockSlotToolsExtra = 136;

/// Top button row under the status-bar inset.
const double _kLayoutTopChromeHeight = 56;

class LayoutStatusComposerScreen extends StatefulWidget {
  const LayoutStatusComposerScreen({
    super.key,
    this.imagePicker,
    this.imageStore,
    this.exportOverride,
  });

  final ImagePicker? imagePicker;
  final LayoutPickedImageStore? imageStore;
  final Future<String> Function()? exportOverride;

  @override
  LayoutStatusComposerScreenState createState() =>
      LayoutStatusComposerScreenState();
}

class LayoutStatusComposerScreenState extends State<LayoutStatusComposerScreen> {
  late final ImagePicker _imagePicker;
  late final LayoutPickedImageStore _imageStore;
  final GlobalKey _canvasBoundaryKey = GlobalKey();
  final LayoutExporter _exporter = const LayoutExporter();

  late LayoutComposerState _state;
  LayoutBottomMode _bottomMode = LayoutBottomMode.layouts;
  bool _isExporting = false;
  bool _isPickingImage = false;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _imagePicker = widget.imagePicker ?? ImagePicker();
    _imageStore = widget.imageStore ?? const LayoutPickedImageStore();
    _state = LayoutCatalog.initialState();
  }

  @visibleForTesting
  LayoutComposerState get debugState => _state;

  @visibleForTesting
  LayoutBottomMode get debugBottomMode => _bottomMode;

  @visibleForTesting
  bool get debugChromeVisible => _chromeVisible;

  LayoutSlotContent? get _selectedSlot {
    final index = _state.selectedSlotIndex;
    if (index == null || index < 0 || index >= _state.slots.length) {
      return null;
    }
    return _state.slots[index];
  }

  bool get _canEditSelectedPhoto {
    final slot = _selectedSlot;
    return slot != null && slot.hasImage && _state.selectedSlotIndex != null;
  }

  Future<void> _pickImageForSlot(int slotIndex) async {
    if (_isPickingImage ||
        slotIndex < 0 ||
        slotIndex >= _state.slots.length) {
      return;
    }

    _isPickingImage = true;
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 82,
      );
      if (!mounted || picked == null) {
        return;
      }

      final stablePath = await _imageStore.persist(picked.path);
      if (!mounted) {
        return;
      }

      _updateSlot(
        slotIndex,
        _state.slots[slotIndex].copyWith(
          imagePath: stablePath,
          scale: kLayoutDefaultPhotoScale,
        ),
        selectSlot: true,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not open your gallery right now.'),
        ),
      );
    } finally {
      _isPickingImage = false;
    }
  }

  void _updateSlot(
    int slotIndex,
    LayoutSlotContent content, {
    bool selectSlot = false,
  }) {
    final slots = List<LayoutSlotContent>.from(_state.slots);
    slots[slotIndex] = content;
    setState(() {
      _state = _state.copyWith(
        slots: slots,
        selectedSlotIndex: selectSlot ? slotIndex : _state.selectedSlotIndex,
      );
      if (selectSlot) {
        _chromeVisible = true;
      }
    });
  }

  void _applySlotLook(LayoutSlotLook look) {
    final index = _state.selectedSlotIndex;
    final slot = _selectedSlot;
    if (index == null || slot == null) {
      return;
    }
    _updateSlot(
      index,
      slot.copyWith(
        look: look,
        borderWidth: look.strokeWidth,
        borderColorValue: look.usesColor
            ? (slot.borderColorValue ?? look.defaultColorValue)
            : slot.borderColorValue,
      ),
      selectSlot: true,
    );
  }

  void _applySlotLookColor(Color color) {
    final index = _state.selectedSlotIndex;
    final slot = _selectedSlot;
    if (index == null || slot == null) {
      return;
    }
    _updateSlot(
      index,
      slot.copyWith(borderColorValue: color.toARGB32()),
      selectSlot: true,
    );
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }

  void _onSlotTap(int slotIndex) {
    if (!_chromeVisible) {
      setState(() => _chromeVisible = true);
      return;
    }
    if (slotIndex < 0 || slotIndex >= _state.slots.length) {
      return;
    }
    final slot = _state.slots[slotIndex];
    if (!slot.hasImage) {
      _pickImageForSlot(slotIndex);
      return;
    }
    setState(() {
      _state = _state.copyWith(selectedSlotIndex: slotIndex);
    });
  }

  void _selectTemplate(LayoutTemplate template) {
    setState(() {
      _state = LayoutCatalog.migrateState(_state, template);
      if (_state.slots.any((slot) => !slot.hasImage)) {
        _bottomMode = LayoutBottomMode.layouts;
      }
    });
  }

  void _setBottomMode(LayoutBottomMode mode) {
    setState(() {
      _bottomMode = mode;
      if (mode == LayoutBottomMode.shapes &&
          _state.selectedSlotIndex == null &&
          _state.slots.isNotEmpty) {
        _state = _state.copyWith(selectedSlotIndex: 0);
      }
    });
  }

  void _applyShape(LayoutShapeRailEntry entry) {
    if (entry.isCollage) {
      final template = LayoutCatalog.templateById(entry.templateId!);
      setState(() {
        _state = LayoutCatalog.migrateState(_state, template);
        _bottomMode = LayoutBottomMode.shapes;
        if (_state.slots.isNotEmpty) {
          _state = _state.copyWith(selectedSlotIndex: 0);
        }
      });
      return;
    }

    final shape = entry.shape!;
    var slotIndex = _state.selectedSlotIndex ?? 0;
    if (LayoutCatalog.isShapeCollage(_state.templateId)) {
      setState(() {
        _state = LayoutCatalog.migrateState(
          _state,
          LayoutCatalog.templateById('single'),
        );
      });
      slotIndex = 0;
    }
    if (slotIndex < 0 || slotIndex >= _state.slots.length) {
      return;
    }
    _updateSlot(
      slotIndex,
      _state.slots[slotIndex].copyWith(shape: shape),
      selectSlot: true,
    );
  }

  Future<void> _shareLayout() async {
    if (!_state.canShare || _isExporting) {
      return;
    }

    setState(() {
      _isExporting = true;
      _chromeVisible = false;
    });
    // Full-screen export paints the background into the notch / home
    // bands only after this rebuild. Capture before that and the posted
    // image is the letterboxed editor.
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    try {
      final exportedPath = widget.exportOverride != null
          ? await widget.exportOverride!()
          : await _exporter.exportToTempFile(
              state: _state,
              repaintBoundaryKey: _canvasBoundaryKey,
            );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(
        LayoutStatusComposerDraft(
          exportedImagePath: exportedPath,
          aspectRatio: _exportedAspect(),
          backgroundColorValue: _state.backgroundColorValue,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _chromeVisible = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not prepare that layout. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  double? _exportedAspect() {
    final fixed = _state.ratio.value;
    if (fixed != null && fixed > 0) {
      return fixed;
    }
    // Full screen is this device's safe-area collage — not the raw
    // screen — so a viewer on another phone contain-fits the same
    // photos instead of cover-cropping them to its own notch.
    final box =
        _canvasBoundaryKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.size.height > 0) {
      return box.size.width / box.size.height;
    }
    return kLayoutStoryAspectRatio;
  }

  Widget _buildLayoutCanvas() {
    return LayoutCanvas(
      state: _state,
      isEditing: _chromeVisible,
      onSlotTap: _onSlotTap,
      onCanvasBackgroundTap: _toggleChrome,
      onSplitWeightsChanged: (weights) {
        setState(() {
          _state = _state.copyWith(splitWeights: weights);
        });
      },
      onCellWeightsChanged: (band, weights) {
        final grid = LayoutCatalog.templateById(_state.templateId).grid;
        if (grid == null) {
          return;
        }
        final next = layoutSeedCellWeights(grid, _state.cellWeights);
        next[band] = weights;
        setState(() {
          _state = _state.copyWith(cellWeights: next);
        });
      },
      onSlotTransformEnd: (slotIndex, scale, focal) {
        _updateSlot(
          slotIndex,
          _state.slots[slotIndex].copyWith(
            scale: scale,
            focalDx: focal.dx,
            focalDy: focal.dy,
          ),
          selectSlot: true,
        );
      },
    );
  }

  Future<void> _showCanvasRatios(BuildContext anchorContext) async {
    final picked = await showLiquidGlassBubbleMenu<LayoutCanvasRatio>(
      anchorContext: anchorContext,
      openBelow: true,
      itemBuilder: (context) => [
        for (final ratio in LayoutCanvasRatio.values)
          LiquidGlassBubbleItem(
            key: Key('layout_ratio_${ratio.name}'),
            label: ratio.label,
            selected: ratio == _state.ratio,
            onTap: () => Navigator.of(context).pop(ratio),
          ),
      ],
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _state = _state.copyWith(ratio: picked));
  }

  Future<void> _showBackgroundColors() async {
    await showGlassBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return LayoutBackgroundColorSheet(
          selectedColor: _state.backgroundColor,
          onColorSelected: (color) {
            setState(() {
              _state = _state.copyWith(backgroundColorValue: color.toARGB32());
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _state.selectedSlotIndex;
    final selectedSlot = _selectedSlot;
    final canEditPhoto = _canEditSelectedPhoto;
    final showSlotTools = _chromeVisible && canEditPhoto;
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final padding = MediaQuery.paddingOf(context);
    final safeTop = viewPadding.top;
    final safeBottom = viewPadding.bottom;
    final safeLeft = viewPadding.left;
    final safeRight = viewPadding.right;
    final dockInset = padding.bottom + 12;
    final topReserve = _chromeVisible
        ? safeTop + _kLayoutTopChromeHeight + 8
        : safeTop + 8;
    final dockReserve = _chromeVisible
        ? _kLayoutDockBaseHeight +
            (showSlotTools ? _kLayoutDockSlotToolsExtra : 0) +
            dockInset +
            8
        : dockInset;

    final isFullScreen = _state.ratio == LayoutCanvasRatio.fullScreen;
    final previewFullBleed = isFullScreen && !_chromeVisible;

    return StatusStorySystemChrome(
      child: Scaffold(
        key: const Key('layout_status_composer_screen'),
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final safeArea = layoutComposerSafeAreaSize(
              screenSize: Size(constraints.maxWidth, constraints.maxHeight),
              topInset: safeTop,
              bottomInset: safeBottom,
              leftInset: safeLeft,
              rightInset: safeRight,
            );
            final aspect = _state.ratio.resolve(safeArea);
            final hostTop = previewFullBleed ? 0.0 : topReserve;
            final hostBottom = previewFullBleed ? 0.0 : dockReserve;
            final availableHeight =
                (constraints.maxHeight - hostTop - hostBottom)
                    .clamp(200.0, double.infinity);
            final photoHost = previewFullBleed
                ? safeArea
                : Size(constraints.maxWidth, availableHeight);
            final frameSize = statusStoryFrameSizeFor(photoHost, aspect);
            final photoCanvas = RepaintBoundary(
              key: _canvasBoundaryKey,
              child: SizedBox(
                key: const Key('layout_composer_canvas'),
                width: frameSize.width,
                height: frameSize.height,
                child: _buildLayoutCanvas(),
              ),
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  key: const Key('layout_composer_canvas_host'),
                  top: hostTop,
                  left: 0,
                  right: 0,
                  bottom: hostBottom,
                  child: previewFullBleed
                      ? ColoredBox(
                          color: _state.backgroundColor,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              safeLeft,
                              safeTop,
                              safeRight,
                              safeBottom,
                            ),
                            child: Center(child: photoCanvas),
                          ),
                        )
                      : Center(child: photoCanvas),
                ),
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: StatusStoryEdgeScrim(),
                ),
                if (_chromeVisible)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: dockReserve + 48,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0),
                              Colors.black.withValues(alpha: 0.55),
                              Colors.black.withValues(alpha: 0.92),
                            ],
                            stops: const [0, 0.45, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                // Top chrome — one row, same pattern as text/media composers.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _chromeVisible ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !_chromeVisible,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                          child: Row(
                            children: [
                              StatusChromeButton(
                                key: const Key('layout_composer_back'),
                                tooltip: 'Close',
                                icon: Icons.close_rounded,
                                onTap: () => Navigator.of(context).pop(),
                              ),
                              const Spacer(),
                              StatusChromeButtonGroup(
                                children: [
                                  StatusChromeButton(
                                    key: const Key('layout_composer_preview'),
                                    tooltip: 'Preview',
                                    icon: Icons.visibility_outlined,
                                    onTap: _toggleChrome,
                                    bare: true,
                                  ),
                                  Builder(
                                    builder: (buttonContext) {
                                      return StatusChromeButton(
                                        key: const Key('layout_composer_ratio'),
                                        tooltip: 'Canvas size',
                                        icon: Icons.aspect_ratio_rounded,
                                        onTap: () =>
                                            _showCanvasRatios(buttonContext),
                                        bare: true,
                                      );
                                    },
                                  ),
                                  StatusChromeButton(
                                    key: const Key(
                                      'layout_composer_background_color',
                                    ),
                                    tooltip: 'Background color',
                                    icon: Icons.palette_outlined,
                                    onTap: _showBackgroundColors,
                                    bare: true,
                                  ),
                                ],
                              ),
                              const SizedBox(width: 8),
                              StatusChromeSendButton(
                                actionKey: const Key('layout_composer_share'),
                                busy: _isExporting,
                                onTap: _state.canShare && !_isExporting
                                    ? _shareLayout
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (showSlotTools &&
                    selectedSlot != null &&
                    selectedSlot.look.usesColor)
                  Positioned(
                    top: topReserve,
                    right: 10,
                    bottom: dockReserve,
                    child: StatusTextColorRail(
                      railKey: const Key('layout_slot_color_rail'),
                      barKey: const Key('layout_slot_color_bar'),
                      thumbKey: const Key('layout_slot_color_thumb'),
                      selectedColor: selectedSlot.borderColor ??
                          Color(selectedSlot.look.defaultColorValue),
                      onSelectColor: _applySlotLookColor,
                    ),
                  ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: dockInset,
                  child: Offstage(
                    offstage: !_chromeVisible,
                    child: LayoutComposerDock(
                      bottomMode: _bottomMode,
                      selectedTemplateId: _state.templateId,
                      selectedShape:
                          selectedSlot?.shape ?? LayoutShapeId.rectangle,
                      showSlotTools: canEditPhoto,
                      frame: _state.frame,
                      onFrameChanged: (frame) {
                        setState(() {
                          _state = _state.copyWith(frame: frame);
                        });
                      },
                      editHint: canEditPhoto
                          ? 'Drag to move · Pinch to zoom'
                          : null,
                      onModeChanged: _setBottomMode,
                      onTemplateSelected: _selectTemplate,
                      onShapeSelected: _applyShape,
                      look: selectedSlot?.look ?? LayoutSlotLook.none,
                      onLookSelected: selectedIndex == null
                          ? null
                          : _applySlotLook,
                      onReplaceTap: selectedIndex == null
                          ? null
                          : () => _pickImageForSlot(selectedIndex),
                      onRemoveTap: selectedIndex == null || selectedSlot == null
                          ? null
                          : () {
                              _updateSlot(
                                selectedIndex,
                                selectedSlot.copyWith(clearImagePath: true),
                              );
                              setState(() {
                                _state =
                                    _state.copyWith(clearSelectedSlot: true);
                                _bottomMode = LayoutBottomMode.layouts;
                              });
                            },
                    ),
                  ),
                ),
                if (!_chromeVisible)
                  Positioned.fill(
                    child: GestureDetector(
                      key: const Key('layout_composer_preview_overlay'),
                      behavior: HitTestBehavior.translucent,
                      onTap: _toggleChrome,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
