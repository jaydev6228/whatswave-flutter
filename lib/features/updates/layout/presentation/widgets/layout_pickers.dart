import 'package:flutter/material.dart';

import '../../../presentation/widgets/status_chrome.dart';
import '../../data/layout_catalog.dart';
import '../../models/layout_models.dart';
import 'layout_shape_clipper.dart';
import 'layout_slot_toolbar.dart';

/// Floating bottom dock — layouts/shapes rail + optional slot tools.
class LayoutComposerDock extends StatelessWidget {
  const LayoutComposerDock({
    required this.bottomMode,
    required this.selectedTemplateId,
    required this.selectedShape,
    required this.showSlotTools,
    required this.onModeChanged,
    required this.onTemplateSelected,
    required this.onShapeSelected,
    this.editHint,
    this.onReplaceTap,
    this.onRemoveTap,
    super.key,
  });

  final LayoutBottomMode bottomMode;
  final String selectedTemplateId;
  final LayoutShapeId selectedShape;
  final bool showSlotTools;
  final String? editHint;
  final ValueChanged<LayoutBottomMode> onModeChanged;
  final ValueChanged<LayoutTemplate> onTemplateSelected;
  final ValueChanged<LayoutShapeId> onShapeSelected;
  final VoidCallback? onReplaceTap;
  final VoidCallback? onRemoveTap;

  @override
  Widget build(BuildContext context) {
    return StatusChromeSurface(
      blurred: true,
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showSlotTools &&
              onReplaceTap != null &&
              onRemoveTap != null) ...[
            LayoutSlotToolbar(
              onReplaceTap: onReplaceTap!,
              onRemoveTap: onRemoveTap!,
            ),
            if (editHint != null) ...[
              const SizedBox(height: 6),
              Text(
                editHint!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 10),
          ],
          Center(
            child: LayoutBottomModeToggle(
              mode: bottomMode,
              onModeChanged: onModeChanged,
            ),
          ),
          const SizedBox(height: 10),
          if (bottomMode == LayoutBottomMode.layouts)
            LayoutTemplatePicker(
              selectedTemplateId: selectedTemplateId,
              onTemplateSelected: onTemplateSelected,
            )
          else
            LayoutShapePicker(
              selectedShape: selectedShape,
              onShapeSelected: onShapeSelected,
            ),
        ],
      ),
    );
  }
}

class LayoutTemplatePicker extends StatelessWidget {
  const LayoutTemplatePicker({
    required this.selectedTemplateId,
    required this.onTemplateSelected,
    super.key,
  });

  final String selectedTemplateId;
  final ValueChanged<LayoutTemplate> onTemplateSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        key: const Key('layout_template_picker'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: LayoutCatalog.templates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final template = LayoutCatalog.templates[index];
          final isSelected = template.id == selectedTemplateId;
          return _TemplateTile(
            key: Key('layout_template_${template.id}'),
            template: template,
            isSelected: isSelected,
            onTap: () => onTemplateSelected(template),
          );
        },
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final LayoutTemplate template;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: template.label,
      selected: isSelected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 52,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF2AABEE)
                    : Colors.white.withValues(alpha: 0.12),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: CustomPaint(
              painter: LayoutTemplatePreviewPainter(
                template: template,
                fillColor: Colors.white.withValues(alpha: 0.35),
                gutterColor: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LayoutShapePicker extends StatelessWidget {
  const LayoutShapePicker({
    required this.selectedShape,
    required this.onShapeSelected,
    super.key,
  });

  final LayoutShapeId selectedShape;
  final ValueChanged<LayoutShapeId> onShapeSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        key: const Key('layout_shape_picker'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: kLayoutShapePickerOrder.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final shape = kLayoutShapePickerOrder[index];
          final isSelected = shape == selectedShape;
          return _ShapeTile(
            key: Key('layout_shape_${shape.name}'),
            shape: shape,
            isSelected: isSelected,
            onTap: () => onShapeSelected(shape),
          );
        },
      ),
    );
  }
}

class _ShapeTile extends StatelessWidget {
  const _ShapeTile({
    required this.shape,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final LayoutShapeId shape;
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
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 52,
            height: 68,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF2AABEE)
                    : Colors.white.withValues(alpha: 0.12),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: CustomPaint(
              painter: LayoutShapePreviewPainter(
                shape: shape,
                fillColor: Colors.white.withValues(alpha: 0.38),
                strokeColor: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LayoutBottomModeToggle extends StatelessWidget {
  const LayoutBottomModeToggle({
    required this.mode,
    required this.onModeChanged,
    super.key,
  });

  final LayoutBottomMode mode;
  final ValueChanged<LayoutBottomMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ModeChip(
              key: const Key('layout_mode_layouts'),
              label: 'Layouts',
              isSelected: mode == LayoutBottomMode.layouts,
              onTap: () => onModeChanged(LayoutBottomMode.layouts),
            ),
            _ModeChip(
              key: const Key('layout_mode_shapes'),
              label: 'Shapes',
              isSelected: mode == LayoutBottomMode.shapes,
              onTap: () => onModeChanged(LayoutBottomMode.shapes),
            ),
          ],
        ),
      ),
    );
  }
}

enum LayoutBottomMode { layouts, shapes }

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.62),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
