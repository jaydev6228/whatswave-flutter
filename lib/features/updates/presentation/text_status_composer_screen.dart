import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/status_story.dart';
import 'widgets/text_status_canvas.dart';

class TextStatusComposerDraft {
  const TextStatusComposerDraft({
    required this.caption,
    required this.textStyle,
  });

  final String caption;
  final StatusTextStyle textStyle;
}

enum _ComposerPanel { cards, fonts, backgrounds, tone }

enum _CustomBackgroundFill { gradient, solid }

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

  static const List<_CardPreset> _cardPresets = <_CardPreset>[
    _CardPreset(
      id: 'invite',
      label: 'Invite',
      subtitle: 'Card-style event invite',
      sampleText: 'Studio launch invite\nFriday • 7:00 PM\nShibuya, Tokyo',
      style: StatusTextStyle(
        fontId: 'serif',
        backgroundId: 'sunset_glow',
        layout: StatusTextLayout.invitation,
        alignment: StatusTextAlignment.center,
        textColorValue: 0xFF3D1604,
        sizeScale: 0.94,
      ),
    ),
    _CardPreset(
      id: 'launch',
      label: 'Launch',
      subtitle: 'Bold release banner',
      sampleText: 'NEW DROP\nVersion 1.0 is live today',
      style: StatusTextStyle(
        fontId: 'impact',
        backgroundId: 'neon_stage',
        layout: StatusTextLayout.banner,
        alignment: StatusTextAlignment.center,
        textColorValue: 0xFFFFFFFF,
        sizeScale: 1.08,
      ),
    ),
    _CardPreset(
      id: 'birthday',
      label: 'Birthday',
      subtitle: 'Celebration poster',
      sampleText: 'HAPPY BIRTHDAY\nNoah\nDinner at 8?',
      style: StatusTextStyle(
        fontId: 'soft',
        backgroundId: 'rose_gold',
        layout: StatusTextLayout.spotlight,
        alignment: StatusTextAlignment.center,
        textColorValue: 0xFFFFFFFF,
        sizeScale: 1.04,
      ),
    ),
    _CardPreset(
      id: 'agenda',
      label: 'Agenda',
      subtitle: 'Structured info note',
      sampleText: 'Today\n9:30 Design review\n2:00 QA pass\n6:00 Ship build',
      style: StatusTextStyle(
        fontId: 'mono',
        backgroundId: 'peach_cloud',
        layout: StatusTextLayout.note,
        alignment: StatusTextAlignment.left,
        textColorValue: 0xFF111B21,
        sizeScale: 0.9,
      ),
    ),
    _CardPreset(
      id: 'quote',
      label: 'Quote',
      subtitle: 'Simple standout thought',
      sampleText: 'Build things people feel, not just features they can tap.',
      style: StatusTextStyle(
        fontId: 'editorial',
        backgroundId: 'forest_night',
        layout: StatusTextLayout.poster,
        alignment: StatusTextAlignment.left,
        textColorValue: 0xFFFFFFFF,
        sizeScale: 1.02,
      ),
    ),
    _CardPreset(
      id: 'party',
      label: 'Party',
      subtitle: 'Bright social announcement',
      sampleText: 'HOUSE PARTY\nSaturday\nBring your best playlist',
      style: StatusTextStyle(
        fontId: 'wide',
        backgroundId: 'mango_fizz',
        layout: StatusTextLayout.classic,
        alignment: StatusTextAlignment.center,
        textColorValue: 0xFF4F2300,
        sizeScale: 1.02,
      ),
    ),
    _CardPreset(
      id: 'save-the-date',
      label: 'Save Date',
      subtitle: 'Elegant event card',
      sampleText: 'SAVE THE DATE\n12 December\nOsaka Riverside Hall',
      style: StatusTextStyle(
        fontId: 'luxe',
        backgroundId: 'lavender_dream',
        layout: StatusTextLayout.invitation,
        alignment: StatusTextAlignment.center,
        textColorValue: 0xFFFFFFFF,
        sizeScale: 0.96,
      ),
    ),
    _CardPreset(
      id: 'match-night',
      label: 'Match',
      subtitle: 'Scoreboard-style poster',
      sampleText: 'MATCH NIGHT\nTokyo 2 - 1 Osaka\nFull time',
      style: StatusTextStyle(
        fontId: 'signal',
        backgroundId: 'ocean_splash',
        layout: StatusTextLayout.poster,
        alignment: StatusTextAlignment.left,
        textColorValue: 0xFFFFFFFF,
        sizeScale: 0.94,
      ),
    ),
    _CardPreset(
      id: 'flash-sale',
      label: 'Flash',
      subtitle: 'Fast promo banner',
      sampleText: 'FLASH SALE\nToday only\nUp to 40% off',
      style: StatusTextStyle(
        fontId: 'cinema',
        backgroundId: 'mango_fizz',
        layout: StatusTextLayout.banner,
        alignment: StatusTextAlignment.center,
        textColorValue: 0xFF4F2300,
        sizeScale: 1.0,
      ),
    ),
    _CardPreset(
      id: 'journal',
      label: 'Journal',
      subtitle: 'Soft personal note',
      sampleText:
          'Small wins count.\nShip the bug fix,\nthen celebrate the tea break.',
      style: StatusTextStyle(
        fontId: 'journal',
        backgroundId: 'ocean_splash',
        layout: StatusTextLayout.note,
        alignment: StatusTextAlignment.left,
        textColorValue: 0xFF0E2236,
        sizeScale: 0.9,
      ),
    ),
    _CardPreset(
      id: 'spotlight',
      label: 'Spotlight',
      subtitle: 'Big hero announcement',
      sampleText: 'TONIGHT\nLive showcase\n8:30 PM',
      style: StatusTextStyle(
        fontId: 'cinema',
        backgroundId: 'neon_stage',
        layout: StatusTextLayout.spotlight,
        alignment: StatusTextAlignment.center,
        textColorValue: 0xFFFFFFFF,
        sizeScale: 1.06,
      ),
    ),
  ];

  static const List<Color> _backgroundPaletteColors = <Color>[
    Color(0xFF2563EB),
    Color(0xFF0EA5E9),
    Color(0xFF7C3AED),
    Color(0xFFD946EF),
    Color(0xFFEC4899),
    Color(0xFFF97316),
    Color(0xFFF59E0B),
    Color(0xFF84CC16),
    Color(0xFF22C55E),
    Color(0xFF14B8A6),
    Color(0xFF64748B),
    Color(0xFF0F172A),
  ];

  late final TextEditingController _captionController;
  late final FocusNode _focusNode;
  late StatusTextStyle _style;
  _ComposerPanel _selectedPanel = _ComposerPanel.cards;

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
  }

  @override
  void dispose() {
    _captionController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      key: const Key('updates_composer_sheet'),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text(
          'Text studio',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final deckHeight = keyboardVisible
                ? math.min(188.0, constraints.maxHeight * 0.32)
                : math.min(236.0, constraints.maxHeight * 0.4);
            final stagePadding = keyboardVisible
                ? const EdgeInsets.fromLTRB(16, 8, 16, 8)
                : const EdgeInsets.fromLTRB(16, 10, 16, 12);
            final deckPadding = keyboardVisible
                ? const EdgeInsets.fromLTRB(14, 10, 14, 10)
                : const EdgeInsets.fromLTRB(14, 12, 14, 14);

            return Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: stagePadding,
                    child: _buildComposerStage(theme),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  height: deckHeight,
                  padding: deckPadding,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.42),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _ComposerPanel.values.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final panel = _ComposerPanel.values[index];
                                  final isSelected = _selectedPanel == panel;
                                  return _PanelPill(
                                    key: Key(
                                      'updates_composer_panel_${panel.name}',
                                    ),
                                    label: _labelForPanel(panel),
                                    icon: _iconForPanel(panel),
                                    isSelected: isSelected,
                                    onTap: () {
                                      _dismissKeyboard();
                                      setState(() {
                                        _selectedPanel = panel;
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            key: const Key('updates_toggle_keyboard_button'),
                            tooltip:
                                keyboardVisible ? 'Hide keyboard' : 'Edit text',
                            onPressed: () {
                              if (keyboardVisible) {
                                _dismissKeyboard();
                              } else {
                                _focusNode.requestFocus();
                              }
                            },
                            icon: Icon(
                              keyboardVisible
                                  ? Icons.keyboard_hide_rounded
                                  : Icons.edit_rounded,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: keyboardVisible ? 8 : 10),
                      if (!keyboardVisible) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _AlignmentStrip(
                                alignment: _style.alignment,
                                onChanged: (alignment) {
                                  _dismissKeyboard();
                                  setState(() {
                                    _style = _style.copyWith(
                                      alignment: alignment,
                                    );
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _ScaleStrip(
                                value: _style.sizeScale,
                                onChanged: (value) {
                                  setState(() {
                                    _style = _style.copyWith(sizeScale: value);
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: KeyedSubtree(
                            key: ValueKey<_ComposerPanel>(_selectedPanel),
                            child: _buildPanelBody(theme),
                          ),
                        ),
                      ),
                    ],
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
        final shortestSide = math.min(
          constraints.maxWidth,
          constraints.maxHeight,
        );
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
          onTap: () => _focusNode.requestFocus(),
          child: TextStatusCanvas(
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
        );
      },
    );
  }

  Widget _buildPanelBody(ThemeData theme) {
    return switch (_selectedPanel) {
      _ComposerPanel.cards => ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _cardPresets.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final preset = _cardPresets[index];
            final isSelected = _matchesPreset(preset);
            return _CardPresetTile(
              key: Key('updates_card_preset_${preset.id}'),
              preset: preset,
              isSelected: isSelected,
              onTap: () => _applyCardPreset(preset),
            );
          },
        ),
      _ComposerPanel.fonts => ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: kTextStatusFontLooks.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final look = kTextStatusFontLooks[index];
            final isSelected = _style.fontId == look.id;
            final label =
                look.uppercase ? look.sample.toUpperCase() : look.sample;
            return _FontLookChip(
              key: Key('updates_font_${look.id}'),
              fontLook: look,
              label: label,
              isSelected: isSelected,
              onTap: () {
                _dismissKeyboard();
                setState(() {
                  _style = _style.copyWith(fontId: look.id);
                });
              },
            );
          },
        ),
      _ComposerPanel.backgrounds => ListView(
          scrollDirection: Axis.horizontal,
          children: _buildBackgroundPanelChildren(),
        ),
      _ComposerPanel.tone => ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: kTextStatusTonePresets.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final tone = kTextStatusTonePresets[index];
            final isSelected = _style.textColorValue == tone.colorValue;
            return _ToneChip(
              key: Key('updates_tone_${tone.id}'),
              tone: tone,
              isSelected: isSelected,
              onTap: () {
                _dismissKeyboard();
                setState(() {
                  _style = _style.copyWith(
                    textColorValue: tone.colorValue,
                    clearTextColor: tone.colorValue == null,
                  );
                });
              },
            );
          },
        ),
    };
  }

  List<Widget> _buildBackgroundPanelChildren() {
    final children = <Widget>[
      for (final preset in kTextStatusBackgroundPresets) ...[
        _BackgroundSwatch(
          key: Key('updates_background_${preset.id}'),
          preset: preset,
          isSelected: _style.backgroundColorValue == null &&
              _style.backgroundId == preset.id,
          onTap: () {
            _dismissKeyboard();
            setState(() {
              _style = _style.copyWith(
                backgroundId: preset.id,
                clearBackgroundColor: true,
                useSolidBackground: false,
              );
            });
          },
        ),
        const SizedBox(width: 12),
      ],
      _CustomBackgroundLauncher(
        key: const Key('updates_background_custom_picker'),
        preview: buildCustomTextStatusBackgroundPreset(
          _customBackgroundSeedColor,
          useSolidColor: _customBackgroundUsesSolid,
        ),
        isSelected: _style.backgroundColorValue != null,
        onTap: _openCustomBackgroundPicker,
      ),
    ];
    return children;
  }

  void _applyCardPreset(_CardPreset preset) {
    _dismissKeyboard();
    setState(() {
      _style = preset.style;
      if (_captionController.text.trim().isEmpty) {
        _captionController.text = preset.sampleText;
        _captionController.selection = TextSelection.collapsed(
          offset: _captionController.text.length,
        );
      }
    });
  }

  bool _matchesPreset(_CardPreset preset) {
    return _style.fontId == preset.style.fontId &&
        _style.backgroundId == preset.style.backgroundId &&
        _style.backgroundColorValue == preset.style.backgroundColorValue &&
        _style.useSolidBackground == preset.style.useSolidBackground &&
        _style.layout == preset.style.layout &&
        _style.alignment == preset.style.alignment &&
        _style.textColorValue == preset.style.textColorValue &&
        (_style.sizeScale - preset.style.sizeScale).abs() < 0.001;
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  Color get _customBackgroundSeedColor {
    final customColor = _style.backgroundColor;
    if (customColor != null) {
      return customColor;
    }
    final preset = resolveTextStatusBackgroundPreset(
      _style.backgroundId,
      AppPalette.emerald,
    );
    return preset.colors[preset.colors.length ~/ 2];
  }

  bool get _customBackgroundUsesSolid =>
      _style.backgroundColorValue != null && _style.useSolidBackground;

  Future<void> _openCustomBackgroundPicker() async {
    _dismissKeyboard();
    final selection = await showModalBottomSheet<_BackgroundColorSelection>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return _BackgroundColorPickerSheet(
          initialColor: _customBackgroundSeedColor,
          initialFill: _customBackgroundUsesSolid
              ? _CustomBackgroundFill.solid
              : _CustomBackgroundFill.gradient,
        );
      },
    );
    if (!mounted || selection == null) {
      return;
    }

    setState(() {
      _style = _style.copyWith(
        backgroundColorValue: selection.color.toARGB32(),
        useSolidBackground: selection.fill == _CustomBackgroundFill.solid,
      );
    });
  }

  void _shuffleLook() {
    final random = math.Random();
    final font =
        kTextStatusFontLooks[random.nextInt(kTextStatusFontLooks.length)];
    final background = kTextStatusBackgroundPresets[
        random.nextInt(kTextStatusBackgroundPresets.length)];
    final tone =
        kTextStatusTonePresets[random.nextInt(kTextStatusTonePresets.length)];
    final preset = _cardPresets[random.nextInt(_cardPresets.length)];
    final usePaletteBackground = random.nextBool();
    final backgroundColor = _backgroundPaletteColors[
        random.nextInt(_backgroundPaletteColors.length)];

    _dismissKeyboard();
    setState(() {
      _style = StatusTextStyle(
        fontId: font.id,
        backgroundId: background.id,
        backgroundColorValue:
            usePaletteBackground ? backgroundColor.toARGB32() : null,
        useSolidBackground: usePaletteBackground && random.nextBool(),
        layout: preset.style.layout,
        alignment: preset.style.layout == StatusTextLayout.poster ||
                preset.style.layout == StatusTextLayout.note
            ? StatusTextAlignment.left
            : preset.style.alignment,
        textColorValue: tone.colorValue,
        sizeScale: 0.88 + (random.nextDouble() * 0.4),
      );
    });
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
      ),
    );
  }

  static String _labelForPanel(_ComposerPanel panel) {
    return switch (panel) {
      _ComposerPanel.cards => 'Cards',
      _ComposerPanel.fonts => 'Fonts',
      _ComposerPanel.backgrounds => 'Canvas',
      _ComposerPanel.tone => 'Text',
    };
  }

  static IconData _iconForPanel(_ComposerPanel panel) {
    return switch (panel) {
      _ComposerPanel.cards => Icons.dashboard_customize_rounded,
      _ComposerPanel.fonts => Icons.font_download_outlined,
      _ComposerPanel.backgrounds => Icons.palette_outlined,
      _ComposerPanel.tone => Icons.invert_colors_on_outlined,
    };
  }
}

class _CardPreset {
  const _CardPreset({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.sampleText,
    required this.style,
  });

  final String id;
  final String label;
  final String subtitle;
  final String sampleText;
  final StatusTextStyle style;
}

class _PanelPill extends StatelessWidget {
  const _PanelPill({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlignmentStrip extends StatelessWidget {
  const _AlignmentStrip({
    required this.alignment,
    required this.onChanged,
  });

  final StatusTextAlignment alignment;
  final ValueChanged<StatusTextAlignment> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: StatusTextAlignment.values.map((value) {
          final isSelected = alignment == value;
          final icon = switch (value) {
            StatusTextAlignment.left => Icons.format_align_left_rounded,
            StatusTextAlignment.center => Icons.format_align_center_rounded,
            StatusTextAlignment.right => Icons.format_align_right_rounded,
          };
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.66),
                  size: 18,
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _ScaleStrip extends StatelessWidget {
  const _ScaleStrip({
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(
            Icons.text_decrease_rounded,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value,
                min: 0.72,
                max: 1.45,
                divisions: 14,
                onChanged: onChanged,
              ),
            ),
          ),
          Icon(
            Icons.text_increase_rounded,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
          ),
        ],
      ),
    );
  }
}

class _CardPresetTile extends StatelessWidget {
  const _CardPresetTile({
    required this.preset,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final _CardPreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = resolveTextStatusBackgroundForStyle(
      preset.style,
      AppPalette.emerald,
    );
    final previewColor =
        preset.style.textColor ?? background.suggestedTextColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 168,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: background.colors,
              begin: background.begin,
              end: background.end,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.88)
                  : Colors.white.withValues(alpha: 0.2),
              width: isSelected ? 2.1 : 1.1,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 92;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: previewColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preset.subtitle,
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: previewColor.withValues(alpha: 0.84),
                      height: 1.24,
                    ),
                  ),
                  if (!compact) ...[
                    const Spacer(),
                    Text(
                      preset.sampleText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: previewColor.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FontLookChip extends StatelessWidget {
  const _FontLookChip({
    required this.fontLook,
    required this.label,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final TextStatusFontLook fontLook;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewBase = theme.textTheme.titleMedium?.copyWith(
          color: isSelected
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurface,
          fontSize: 20,
        ) ??
        const TextStyle(fontSize: 20);

    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.52),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 88,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: fontLook.apply(previewBase),
                maxLines: 1,
                overflow: TextOverflow.fade,
              ),
              const SizedBox(height: 6),
              Text(
                fontLook.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.66),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackgroundSwatch extends StatelessWidget {
  const _BackgroundSwatch({
    required this.preset,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final TextStatusBackgroundPreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: preset.colors,
                begin: preset.begin,
                end: preset.end,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : Colors.white.withValues(alpha: 0.3),
                width: isSelected ? 2.2 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            preset.label,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _CustomBackgroundLauncher extends StatelessWidget {
  const _CustomBackgroundLauncher({
    required this.preview,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final TextStatusBackgroundPreset preview;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewColor = preview.isSolid ? preview.colors.first : null;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Tooltip(
            message: 'Custom color',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: previewColor,
                gradient: preview.isSolid
                    ? null
                    : LinearGradient(
                        colors: preview.colors,
                        begin: preview.begin,
                        end: preview.end,
                      ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.white.withValues(alpha: 0.28),
                  width: isSelected ? 2.4 : 1.2,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Icon(
                    Icons.palette_outlined,
                    size: 17,
                    color: preview.suggestedTextColor,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Color Lab',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _BackgroundColorSelection {
  const _BackgroundColorSelection({
    required this.color,
    required this.fill,
  });

  final Color color;
  final _CustomBackgroundFill fill;
}

class _BackgroundColorPickerSheet extends StatefulWidget {
  const _BackgroundColorPickerSheet({
    required this.initialColor,
    required this.initialFill,
  });

  final Color initialColor;
  final _CustomBackgroundFill initialFill;

  @override
  State<_BackgroundColorPickerSheet> createState() =>
      _BackgroundColorPickerSheetState();
}

class _BackgroundColorPickerSheetState
    extends State<_BackgroundColorPickerSheet> {
  late HSVColor _selectedColor;
  late _CustomBackgroundFill _selectedFill;

  @override
  void initState() {
    super.initState();
    _selectedColor = HSVColor.fromColor(widget.initialColor);
    _selectedFill = widget.initialFill;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = _selectedColor.toColor();
    final preview = buildCustomTextStatusBackgroundPreset(
      selectedColor,
      useSolidColor: _selectedFill == _CustomBackgroundFill.solid,
    );
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Custom canvas color',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pick the exact background tone you want before sharing.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 18),
          SegmentedButton<_CustomBackgroundFill>(
            segments: const [
              ButtonSegment<_CustomBackgroundFill>(
                value: _CustomBackgroundFill.gradient,
                icon: Icon(Icons.gradient_rounded),
                label: Text('Gradient'),
              ),
              ButtonSegment<_CustomBackgroundFill>(
                value: _CustomBackgroundFill.solid,
                icon: Icon(Icons.format_color_fill_rounded),
                label: Text('Solid'),
              ),
            ],
            selected: {_selectedFill},
            onSelectionChanged: (selection) {
              setState(() {
                _selectedFill = selection.first;
              });
            },
          ),
          const SizedBox(height: 18),
          Container(
            height: 84,
            width: double.infinity,
            decoration: BoxDecoration(
              color: preview.isSolid ? preview.colors.first : null,
              gradient: preview.isSolid
                  ? null
                  : LinearGradient(
                      colors: preview.colors,
                      begin: preview.begin,
                      end: preview.end,
                    ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.26),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: selectedColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.72),
                        width: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _hexLabel(selectedColor),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: preview.suggestedTextColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          AspectRatio(
            aspectRatio: 1.2,
            child: _SaturationValueBoard(
              color: _selectedColor,
              onChanged: (color) {
                setState(() {
                  _selectedColor = color;
                });
              },
            ),
          ),
          const SizedBox(height: 18),
          _HueSpectrumSlider(
            hue: _selectedColor.hue,
            onChanged: (hue) {
              setState(() {
                _selectedColor = _selectedColor.withHue(hue);
              });
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _selectedColor = HSVColor.fromColor(widget.initialColor);
                    _selectedFill = widget.initialFill;
                  });
                },
                child: const Text('Reset'),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  _BackgroundColorSelection(
                    color: selectedColor,
                    fill: _selectedFill,
                  ),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _hexLabel(Color color) {
    final argb = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${argb.substring(2).toUpperCase()}';
  }
}

class _SaturationValueBoard extends StatelessWidget {
  const _SaturationValueBoard({
    required this.color,
    required this.onChanged,
  });

  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final markerLeft = color.saturation * size.width;
        final markerTop = (1 - color.value) * size.height;
        final hueColor = HSVColor.fromAHSV(1, color.hue, 1, 1).toColor();

        void updateColor(Offset localPosition) {
          final dx = localPosition.dx.clamp(0.0, size.width);
          final dy = localPosition.dy.clamp(0.0, size.height);
          onChanged(
            color
                .withSaturation(dx / size.width)
                .withValue(1 - (dy / size.height)),
          );
        }

        return GestureDetector(
          onTapDown: (details) => updateColor(details.localPosition),
          onPanDown: (details) => updateColor(details.localPosition),
          onPanUpdate: (details) => updateColor(details.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.white, hueColor],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                ),
                Positioned(
                  left: markerLeft.clamp(14.0, size.width - 14.0) - 14,
                  top: markerTop.clamp(14.0, size.height - 14.0) - 14,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.toColor(),
                      border: Border.all(color: Colors.white, width: 2.6),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HueSpectrumSlider extends StatelessWidget {
  const _HueSpectrumSlider({
    required this.hue,
    required this.onChanged,
  });

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final markerLeft = (hue / 360) * width;

          void updateHue(Offset localPosition) {
            final dx = localPosition.dx.clamp(0.0, width);
            onChanged((dx / width) * 360);
          }

          return GestureDetector(
            onTapDown: (details) => updateHue(details.localPosition),
            onPanDown: (details) => updateHue(details.localPosition),
            onPanUpdate: (details) => updateHue(details.localPosition),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFF0000),
                        Color(0xFFFFFF00),
                        Color(0xFF00FF00),
                        Color(0xFF00FFFF),
                        Color(0xFF0000FF),
                        Color(0xFFFF00FF),
                        Color(0xFFFF0000),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: markerLeft.clamp(14.0, width - 14.0) - 14,
                  top: 3,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.6),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ToneChip extends StatelessWidget {
  const _ToneChip({
    required this.tone,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final TextStatusTonePreset tone;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.52),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              tone.color == null
                  ? Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surface,
                      ),
                      child: Icon(
                        Icons.auto_fix_high_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurface,
                      ),
                    )
                  : Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tone.color,
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: isSelected
                          ? Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: ThemeData.estimateBrightnessForColor(
                                        tone.color!,
                                      ) ==
                                      Brightness.dark
                                  ? Colors.white
                                  : AppPalette.ink,
                            )
                          : null,
                    ),
              const SizedBox(height: 6),
              Text(
                tone.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
