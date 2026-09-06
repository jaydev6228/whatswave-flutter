import 'package:flutter/material.dart';

import '../../../presentation/widgets/status_chrome.dart';
import '../../../presentation/widgets/status_text_editing_tools.dart';
import '../../models/layout_models.dart';

class LayoutSlotToolbar extends StatelessWidget {
  const LayoutSlotToolbar({
    required this.onReplaceTap,
    required this.onRemoveTap,
    super.key,
  });

  final VoidCallback onReplaceTap;
  final VoidCallback onRemoveTap;

  @override
  Widget build(BuildContext context) {
    return StatusChromeSurface(
      blurred: true,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ToolbarAction(
            key: const Key('layout_slot_replace'),
            icon: Icons.swap_horiz_rounded,
            label: 'Replace',
            onTap: onReplaceTap,
          ),
          _ToolbarAction(
            key: const Key('layout_slot_remove'),
            icon: Icons.delete_outline_rounded,
            label: 'Remove',
            onTap: onRemoveTap,
          ),
        ],
      ),
    );
  }
}

class LayoutSlotLookRail extends StatelessWidget {
  const LayoutSlotLookRail({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final LayoutSlotLook selected;
  final ValueChanged<LayoutSlotLook> onSelected;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SingleChildScrollView(
        key: const Key('layout_slot_look_rail'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final look in LayoutSlotLook.values) ...[
              if (look != LayoutSlotLook.values.first) const SizedBox(width: 6),
              _LookChip(
                key: Key('layout_slot_look_${look.name}'),
                look: look,
                selected: look == selected,
                onTap: () => onSelected(look),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LookChip extends StatelessWidget {
  const _LookChip({
    required this.look,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final LayoutSlotLook look;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? const Color(0xFF2AABEE) : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      label: look.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF2AABEE).withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: accent.withValues(alpha: selected ? 1 : 0.28),
              ),
            ),
            child: Text(
              look.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 68,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LayoutBackgroundColorSheet extends StatefulWidget {
  const LayoutBackgroundColorSheet({
    required this.selectedColor,
    required this.onColorSelected,
    super.key,
  });

  final Color selectedColor;
  final ValueChanged<Color> onColorSelected;

  static const List<Color> _swatches = <Color>[
    Colors.white,
    Color(0xFFF5F5F5),
    Color(0xFF111111),
    Color(0xFF2AABEE),
    Color(0xFFFF6B6B),
    Color(0xFFFFD166),
    Color(0xFF06D6A0),
    Color(0xFF8338EC),
    Color(0xFFFF8FAB),
    Color(0xFF8ECAE6),
    Color(0xFFFFD6A5),
    Color(0xFFFDFFB6),
    Color(0xFFCAFFBF),
    Color(0xFFBDB2FF),
    Color(0xFFFFC6FF),
    Color(0xFF9BF6FF),
    Color(0xFFFFE5D9),
    Color(0xFFD0F4DE),
  ];

  @override
  State<LayoutBackgroundColorSheet> createState() =>
      _LayoutBackgroundColorSheetState();
}

class _LayoutBackgroundColorSheetState
    extends State<LayoutBackgroundColorSheet> {
  late Color _selected = widget.selectedColor;
  late Color _shadeBase = widget.selectedColor;

  void _pick(Color color, {bool dismiss = false, bool asBase = false}) {
    setState(() {
      _selected = color;
      if (asBase) {
        _shadeBase = color;
      }
    });
    widget.onColorSelected(color);
    if (dismiss && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shadeStops = <Color>[
      Color.lerp(Colors.white, _shadeBase, 0.12)!,
      _shadeBase,
      _strongerBackground(_shadeBase),
    ];
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Background',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      (constraints.maxWidth / 36).floor().clamp(8, 12);
                  final cell = constraints.maxWidth / columns;
                  final visual = (cell - 8).clamp(24.0, 32.0);
                  return Wrap(
                    children: [
                      for (final color in LayoutBackgroundColorSheet._swatches)
                        SizedBox(
                          width: cell,
                          height: cell,
                          child: Center(
                            child: _ColorSwatch(
                              key: Key(
                                'layout_background_swatch_${color.toARGB32()}',
                              ),
                              color: color,
                              size: visual,
                              isSelected:
                                  color.toARGB32() == _selected.toARGB32(),
                              onTap: () =>
                                  _pick(color, dismiss: true, asBase: true),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              const Text(
                'Custom',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              StatusTextColorRail(
                axis: Axis.horizontal,
                railKey: const Key('layout_background_color_rail'),
                barKey: const Key('layout_background_color_bar'),
                thumbKey: const Key('layout_background_color_thumb'),
                selectedColor: _shadeBase,
                onSelectColor: (color) => _pick(color, asBase: true),
              ),
              const SizedBox(height: 10),
              StatusTextColorRail(
                axis: Axis.horizontal,
                colors: shadeStops,
                railKey: const Key('layout_background_shade_rail'),
                barKey: const Key('layout_background_shade_bar'),
                thumbKey: const Key('layout_background_shade_thumb'),
                selectedColor: _selected,
                onSelectColor: _pick,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _strongerBackground(Color color) {
  final hsl = HSLColor.fromColor(color);
  if (hsl.saturation < 0.08) {
    return Color.lerp(color, Colors.black, 0.72)!;
  }
  return hsl
      .withSaturation((hsl.saturation * 1.2).clamp(0.35, 1.0))
      .withLightness((hsl.lightness * 0.52).clamp(0.12, 0.42))
      .toColor();
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.size = 40,
    super.key,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.white24,
                width: isSelected ? 2.5 : 1,
              ),
              boxShadow: isSelected
                  ? const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
