import 'package:flutter/material.dart';

import '../../../core/config/backend_runtime_config.dart';
import '../../../core/controllers/app_preferences_controller.dart';
import '../../../core/integrations/integration_hub_controller.dart';
import '../../../core/models/app_user.dart';
import '../../auth/application/auth_controller.dart';
import 'backend_sync_screen.dart';
import 'privacy_settings_screen.dart';
import 'profile_settings_screen.dart';
import 'widgets/profile_header_card.dart';
import 'widgets/settings_tile.dart';

const double _kSettingsScreenHorizontalPadding = 16;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.authController,
    required this.currentUser,
    required this.preferencesController,
    required this.integrationController,
    super.key,
  });

  final AuthController authController;
  final AppUser currentUser;
  final AppPreferencesController preferencesController;
  final IntegrationHubController integrationController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        preferencesController,
        authController,
        integrationController,
      ]),
      builder: (context, _) {
        final activeUser = authController.currentUser ?? currentUser;
        return SafeArea(
          child: CustomScrollView(
            key: const Key('settings_screen'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 100),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          _kSettingsScreenHorizontalPadding,
                          8,
                          _kSettingsScreenHorizontalPadding,
                          0,
                        ),
                        child: Text(
                          'Settings',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ProfileHeaderCard(
                        key: const Key('settings_profile_header'),
                        user: activeUser,
                        onEditTap: () => _openProfileSettings(
                          context,
                          activeUser,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SettingsGroup(
                        child: Column(
                          children: [
                            SettingsTile(
                              key: const Key('settings_account_phone_tile'),
                              icon: Icons.badge_outlined,
                              title: 'Phone and identity',
                              subtitle:
                                  'Your current number is ${activeUser.phoneNumber}.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: _kSettingsScreenHorizontalPadding,
                        ),
                        child: _SettingsSectionLabel(title: 'Appearance'),
                      ),
                      const SizedBox(height: 8),
                      _SettingsGroup(
                        child: SettingsTile(
                          key: const Key('settings_theme_mode_tile'),
                          icon: Icons.palette_outlined,
                          title: 'Theme mode',
                          subtitle: _themeModeLabel(
                            preferencesController.themeMode,
                          ),
                          onTap: () => _openThemeModePicker(context),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: _kSettingsScreenHorizontalPadding,
                        ),
                        child: _SettingsSectionLabel(
                          title: 'Privacy and security',
                        ),
                      ),
                      const SizedBox(height: 8),
                      _SettingsGroup(
                        child: Column(
                          children: [
                            SettingsTile(
                              key: const Key('settings_privacy_center_tile'),
                              icon: Icons.shield_outlined,
                              title: 'Privacy center',
                              subtitle:
                                  'Last seen: ${preferencesController.lastSeenAudience.label}. Status: ${preferencesController.statusAudience.label}.',
                              onTap: () => _openPrivacySettings(context),
                            ),
                            const Divider(height: 1),
                            SettingsTile(
                              key: const Key('settings_app_lock_tile'),
                              icon: Icons.lock_outline_rounded,
                              title: 'App lock',
                              subtitle: preferencesController.appLockEnabled
                                  ? 'Enabled • ${preferencesController.appLockTimeout.label}'
                                  : 'Keep the app open while iterating, or enable lock protection.',
                              trailing: Switch.adaptive(
                                key: const Key('settings_app_lock_switch'),
                                value: preferencesController.appLockEnabled,
                                onChanged:
                                    preferencesController.setAppLockEnabled,
                              ),
                            ),
                            const Divider(height: 1),
                            SettingsTile(
                              key: const Key('settings_notifications_tile'),
                              icon: Icons.notifications_none_rounded,
                              title: 'Notifications',
                              subtitle: preferencesController
                                      .notificationsEnabled
                                  ? 'Message alerts and previews are enabled.'
                                  : 'Notifications are muted on this device.',
                              trailing: Switch.adaptive(
                                key: const Key(
                                  'settings_notifications_switch',
                                ),
                                value:
                                    preferencesController.notificationsEnabled,
                                onChanged: preferencesController
                                    .setNotificationsEnabled,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: _kSettingsScreenHorizontalPadding,
                        ),
                        child:
                            _SettingsSectionLabel(title: 'Production and data'),
                      ),
                      const SizedBox(height: 8),
                      _SettingsGroup(
                        child: Column(
                          children: [
                            SettingsTile(
                              key: const Key('settings_backend_sync_tile'),
                              icon: Icons.cloud_sync_outlined,
                              title: 'Backend and sync',
                              subtitle: _backendSyncSubtitle(),
                              onTap: () => _openBackendSync(context),
                            ),
                            const Divider(height: 1),
                            const SettingsTile(
                              icon: Icons.folder_outlined,
                              title: 'Storage and data',
                              subtitle:
                                  'Media quality, download controls, and cache trimming stay ready for the next hardening pass.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: _kSettingsScreenHorizontalPadding,
                        ),
                        child: _SettingsSectionLabel(title: 'More'),
                      ),
                      const SizedBox(height: 8),
                      const _SettingsGroup(
                        child: SettingsTile(
                          icon: Icons.help_outline_rounded,
                          title: 'Help',
                          subtitle:
                              'FAQ, support, diagnostics, and safety guidance surfaces.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _backendSyncSubtitle() {
    final backendMode = integrationController.runtimeConfig.backendMode.label;
    final pushState = integrationController.pushRegistration.state.label;
    final syncCount = integrationController.syncedActivityCount;
    final uploads = integrationController.mediaTransfers.length;
    return '$backendMode • Push: $pushState • $syncCount synced ops • $uploads tracked uploads.';
  }

  Future<void> _openProfileSettings(
    BuildContext context,
    AppUser activeUser,
  ) async {
    final didSave = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProfileSettingsScreen(
          authController: authController,
          currentUser: activeUser,
        ),
      ),
    );

    if (!context.mounted || didSave != true) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated.')),
    );
  }

  Future<void> _openPrivacySettings(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PrivacySettingsScreen(
          controller: preferencesController,
        ),
      ),
    );
  }

  Future<void> _openBackendSync(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BackendSyncScreen(
          controller: integrationController,
        ),
      ),
    );
  }

  Future<void> _openThemeModePicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('settings_theme_system_chip'),
                title: const Text('System'),
                trailing: preferencesController.themeMode == ThemeMode.system
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () {
                  preferencesController.setThemeMode(ThemeMode.system);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                key: const Key('settings_theme_light_chip'),
                title: const Text('Light'),
                trailing: preferencesController.themeMode == ThemeMode.light
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () {
                  preferencesController.setThemeMode(ThemeMode.light);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                key: const Key('settings_theme_dark_chip'),
                title: const Text('Dark'),
                trailing: preferencesController.themeMode == ThemeMode.dark
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () {
                  preferencesController.setThemeMode(ThemeMode.dark);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

String _themeModeLabel(ThemeMode themeMode) {
  return switch (themeMode) {
    ThemeMode.system => 'Follow your device setting',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent, child: child);
  }
}
