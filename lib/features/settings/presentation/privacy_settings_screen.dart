import 'package:flutter/material.dart';

import '../../../core/controllers/app_preferences_controller.dart';
import '../domain/app_lock_timeout.dart';
import '../domain/privacy_audience.dart';
import 'widgets/settings_tile.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({
    required this.controller,
    super.key,
  });

  final AppPreferencesController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          key: const Key('privacy_settings_screen'),
          appBar: AppBar(
            title: const Text('Privacy'),
          ),
          body: SafeArea(
            child: CustomScrollView(
              key: const Key('privacy_settings_scroll_view'),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Control who can see your activity, what gets shared by default, and how the app protects the screen when you step away.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.72),
                                  ),
                        ),
                        const SizedBox(height: 20),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Column(
                              children: [
                                SettingsTile(
                                  key: const Key('privacy_last_seen_tile'),
                                  icon: Icons.visibility_outlined,
                                  title: 'Last seen and online',
                                  subtitle:
                                      '${controller.lastSeenAudience.label} can see when you were active.',
                                  onTap: () => _showAudienceSheet(
                                    context,
                                    title: 'Last seen and online',
                                    value: controller.lastSeenAudience,
                                    onChanged: controller.setLastSeenAudience,
                                  ),
                                ),
                                const Divider(height: 1),
                                SettingsTile(
                                  key: const Key('privacy_profile_photo_tile'),
                                  icon: Icons.account_circle_outlined,
                                  title: 'Profile photo',
                                  subtitle:
                                      '${controller.profilePhotoAudience.label} can see your profile avatar.',
                                  onTap: () => _showAudienceSheet(
                                    context,
                                    title: 'Profile photo',
                                    value: controller.profilePhotoAudience,
                                    onChanged:
                                        controller.setProfilePhotoAudience,
                                  ),
                                ),
                                const Divider(height: 1),
                                SettingsTile(
                                  key: const Key('privacy_status_tile'),
                                  icon: Icons.auto_awesome_motion_outlined,
                                  title: 'Status',
                                  subtitle:
                                      '${controller.statusAudience.label} can see your story updates.',
                                  onTap: () => _showAudienceSheet(
                                    context,
                                    title: 'Status',
                                    value: controller.statusAudience,
                                    onChanged: controller.setStatusAudience,
                                  ),
                                ),
                                const Divider(height: 1),
                                SettingsTile(
                                  key: const Key('privacy_groups_tile'),
                                  icon: Icons.groups_outlined,
                                  title: 'Groups and communities',
                                  subtitle:
                                      '${controller.groupsAudience.label} can add you by default.',
                                  onTap: () => _showAudienceSheet(
                                    context,
                                    title: 'Groups and communities',
                                    value: controller.groupsAudience,
                                    onChanged: controller.setGroupsAudience,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Column(
                              children: [
                                SettingsTile(
                                  key: const Key('privacy_read_receipts_tile'),
                                  icon: Icons.done_all_rounded,
                                  title: 'Read receipts',
                                  subtitle: controller.readReceiptsEnabled
                                      ? 'People can see when messages are read.'
                                      : 'Read receipts stay off where the surface supports it.',
                                  trailing: Switch.adaptive(
                                    key: const Key(
                                      'privacy_read_receipts_switch',
                                    ),
                                    value: controller.readReceiptsEnabled,
                                    onChanged:
                                        controller.setReadReceiptsEnabled,
                                  ),
                                ),
                                const Divider(height: 1),
                                SettingsTile(
                                  key: const Key(
                                    'privacy_security_notifications_tile',
                                  ),
                                  icon: Icons.security_rounded,
                                  title: 'Security notifications',
                                  subtitle: controller
                                          .securityNotificationsEnabled
                                      ? 'Important safety alerts stay visible.'
                                      : 'Only critical blocking alerts will appear.',
                                  trailing: Switch.adaptive(
                                    key: const Key(
                                      'privacy_security_notifications_switch',
                                    ),
                                    value:
                                        controller.securityNotificationsEnabled,
                                    onChanged: controller
                                        .setSecurityNotificationsEnabled,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'App lock',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                    ),
                                    Switch.adaptive(
                                      key: const Key(
                                        'privacy_app_lock_switch',
                                      ),
                                      value: controller.appLockEnabled,
                                      onChanged: controller.setAppLockEnabled,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  controller.appLockEnabled
                                      ? 'The app will cover the current screen after the selected timeout when you leave it.'
                                      : 'Keep app lock off while iterating quickly, or enable it to test the secure overlay behavior.',
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children:
                                      AppLockTimeout.values.map((timeout) {
                                    return ChoiceChip(
                                      key: Key(
                                        'privacy_lock_timeout_${timeout.name}',
                                      ),
                                      label: Text(timeout.label),
                                      selected:
                                          controller.appLockTimeout == timeout,
                                      onSelected: controller.appLockEnabled
                                          ? (_) => controller
                                              .setAppLockTimeout(timeout)
                                          : null,
                                    );
                                  }).toList(growable: false),
                                ),
                                const SizedBox(height: 16),
                                FilledButton.tonalIcon(
                                  key: const Key('privacy_lock_now_button'),
                                  onPressed: controller.appLockEnabled
                                      ? controller.lockNow
                                      : null,
                                  icon: const Icon(Icons.lock_clock_rounded),
                                  label: const Text('Lock now'),
                                ),
                              ],
                            ),
                          ),
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

  Future<void> _showAudienceSheet(
    BuildContext context, {
    required String title,
    required PrivacyAudience value,
    required ValueChanged<PrivacyAudience> onChanged,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 12),
                RadioGroup<PrivacyAudience>(
                  groupValue: value,
                  onChanged: (nextValue) {
                    if (nextValue == null) {
                      return;
                    }
                    onChanged(nextValue);
                    Navigator.of(context).pop();
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: PrivacyAudience.values.map((audience) {
                      return RadioListTile<PrivacyAudience>(
                        key: Key('privacy_audience_option_${audience.name}'),
                        value: audience,
                        contentPadding: EdgeInsets.zero,
                        title: Text(audience.label),
                      );
                    }).toList(growable: false),
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
