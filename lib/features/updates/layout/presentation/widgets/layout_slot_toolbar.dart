import 'package:flutter/material.dart';

import '../../../presentation/widgets/status_chrome.dart';
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

/// Picks the shape of the whole canvas. What you see here is what the
/// posted story shows — the viewer letterboxes the export to this ratio.
class LayoutCanvasRatioSheet extends StatelessWidget {
  const LayoutCanvasRatioSheet({
    required this.selectedRatio,
    required this.onRatioSelected,
    super.key,
  });

  final LayoutCanvasRatio selectedRatio;
  final ValueChanged<LayoutCanvasRatio> onRatioSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Canvas size',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final ratio in LayoutCanvasRatio.values)
                  _RatioTile(
                    key: Key('layout_ratio_${ratio.name}'),
                    ratio: ratio,
                    isSelected: ratio == selectedRatio,
                    onTap: () => onRatioSelected(ratio),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RatioTile extends StatelessWidget {
  const _RatioTile({
    required this.ratio,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final LayoutCanvasRatio ratio;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = isSelected ? const Color(0xFF2AABEE) : Colors.white;

    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 56,
                  width: 56,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: ratio.value,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: isSelected ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: accent.withValues(alpha: isSelected ? 1 : 0.4),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  ratio.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LayoutBackgroundColorSheet extends StatelessWidget {
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
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in _swatches)
                  _ColorSwatch(
                    key: Key('layout_background_swatch_${color.toARGB32()}'),
                    color: color,
                    isSelected: color.toARGB32() == selectedColor.toARGB32(),
                    onTap: () => onColorSelected(color),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : const Color(0x55FFFFFF),
                width: isSelected ? 3 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
