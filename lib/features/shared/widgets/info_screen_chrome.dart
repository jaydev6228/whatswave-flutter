import 'package:flutter/material.dart';

import 'liquid_glass.dart';

/// Shared list-section chrome for Contact info, Group info, and Community
/// info -- one visual language, three entry points.
///
/// Section labels read as list-section captions, not page titles: Contact
/// info stacks up to six of them, and at title size they pushed most of
/// the content below the fold on a compact phone. Contact info carried its
/// own byte-identical copy of this until the two drifted on a contrast
/// fix; there is one now.
class InfoSectionHeading extends StatelessWidget {
  const InfoSectionHeading(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          // 0.66, not 0.6: at 0.6 this caption is 4.41 on cloud at its
          // 12pt size, just under WCAG AA's 4.5 for text under 18pt, on
          // all three info screens at once. 0.66 gives ~5.4 -- chosen with
          // margin rather than the first passing value, so a later tweak
          // to a surface colour does not quietly undo it.
          color: theme.colorScheme.onSurface.withValues(alpha: 0.66),
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class InfoFlatPanel extends StatelessWidget {
  const InfoFlatPanel({
    required this.child,
    this.padding = const EdgeInsets.all(2),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LiquidGlassSurface(
      blurred: false,
      showShadow: false,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      borderColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
      padding: padding,
      child: child,
    );
  }
}

class InfoPrimaryActionRow extends StatelessWidget {
  const InfoPrimaryActionRow({
    required this.actionKey,
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final Key actionKey;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final color = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.primary.withValues(alpha: 0.38);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: actionKey,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
