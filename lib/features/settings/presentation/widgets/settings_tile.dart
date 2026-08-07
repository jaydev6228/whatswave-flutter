import 'package:flutter/material.dart';

const double _kSettingsTileHorizontalPadding = 18;
const double _kSettingsTileVerticalPadding = 13;
const double _kSettingsTileLeadingWidth = 34;

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tintColor = destructive ? theme.colorScheme.error : null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _kSettingsTileHorizontalPadding,
        vertical: _kSettingsTileVerticalPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _kSettingsTileLeadingWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Icon(
                icon,
                size: 20,
                color: tintColor ??
                    theme.colorScheme.onSurface.withValues(alpha: 0.64),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: tintColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null || onTap != null) ...[
            const SizedBox(width: 12),
            trailing ??
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.48),
                ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return row;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: row,
      ),
    );
  }
}
