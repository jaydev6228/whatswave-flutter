import 'package:flutter/material.dart';

import '../../../../core/models/app_user.dart';
import '../../../shared/widgets/avatar_badge.dart';

const double _kSettingsRowHorizontalPadding = 18;

class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({
    required this.user,
    this.onEditTap,
    super.key,
  });

  final AppUser user;
  final VoidCallback? onEditTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            _kSettingsRowHorizontalPadding,
            10,
            _kSettingsRowHorizontalPadding,
            10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AvatarBadge(
                label: user.avatarLabel,
                color: user.accentColor,
                size: 58,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.phoneNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user.about,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.28),
                    ),
                  ],
                ),
              ),
              if (onEditTap != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('settings_profile_edit_button'),
                  tooltip: 'Edit profile',
                  visualDensity: VisualDensity.compact,
                  onPressed: onEditTap,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ],
          ),
        ),
        Divider(
          height: 1,
          indent: _kSettingsRowHorizontalPadding + 72,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ],
    );
  }
}
