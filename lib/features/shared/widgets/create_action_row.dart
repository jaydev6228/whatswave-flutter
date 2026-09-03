import 'package:flutter/material.dart';

import 'liquid_glass.dart';

/// Shared "create something new" row used at the top of list pickers --
/// New group (Chats +) and New community (Communities tab) share one layout
/// so the two entry points read as the same kind of action.
class CreateActionRow extends StatelessWidget {
  const CreateActionRow({
    required this.label,
    required this.onTap,
    required this.rowKey,
    this.icon = Icons.add_rounded,
    this.horizontalPadding = 18,
    this.verticalPadding = 14,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final Key rowKey;
  final IconData icon;
  final double horizontalPadding;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: rowKey,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: Row(
            children: [
              LiquidGlassSurface(
                blurred: false,
                showShadow: false,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Icon(
                      icon,
                      size: 22,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
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
