import 'package:flutter/material.dart';

import '../../../core/config/backend_runtime_config.dart';
import '../../../core/controllers/app_preferences_controller.dart';
import '../../../core/integrations/integration_hub_controller.dart';
import '../../../core/models/app_user.dart';
import '../../auth/application/auth_controller.dart';
import '../../calls/application/calls_controller.dart';
import '../../chats/application/chats_controller.dart';
import '../../chats/presentation/starred_messages_screen.dart';
import '../../communities/application/communities_controller.dart';
import '../../updates/application/updates_controller.dart';
import 'backend_sync_screen.dart';
import 'blocked_contacts_screen.dart';
import 'help_screen.dart';
import 'privacy_settings_screen.dart';
import 'profile_settings_screen.dart';
import 'storage_data_screen.dart';
import 'widgets/profile_header_card.dart';
import 'widgets/settings_tile.dart';

// Matches PrivacySettingsScreen's own SliverPadding horizontal inset exactly.
const double _kSettingsScreenHorizontalPadding = 20;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.authController,
    required this.currentUser,
    required this.preferencesController,
    required this.integrationController,
    required this.chatsController,
    required this.callsController,
    required this.updatesController,
    required this.communitiesController,
    super.key,
  });

  final AuthController authController;
  final AppUser currentUser;
  final AppPreferencesController preferencesController;
  final IntegrationHubController integrationController;
  final ChatsController chatsController;
  final CallsController callsController;
  final UpdatesController updatesController;
  final CommunitiesController communitiesController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        preferencesController,
        authController,
        integrationController,
        chatsController,
      ]),
      builder: (context, _) {
        final activeUser = authController.currentUser ?? currentUser;
        final bottomSafeInset = MediaQuery.paddingOf(context).bottom;
        return SafeArea(
          bottom: false,
          child: CustomScrollView(
            key: const Key('settings_screen'),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  _kSettingsScreenHorizontalPadding,
                  0,
                  _kSettingsScreenHorizontalPadding,
                  100 + bottomSafeInset,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
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
                      // Grouped into rounded Cards -- the exact treatment
                      // PrivacySettingsScreen already uses (Card + a
                      // fromLTRB(16,8,16,8) pad + Divider(height:1) between
                      // rows in the same card) -- rather than either one
                      // undifferentiated list or separate text-labeled
                      // sections.
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: SettingsTile(
                            key: const Key('settings_starred_messages_tile'),
                            icon: Icons.star_border_rounded,
                            title: 'Starred messages',
                            subtitle: chatsController.starredMessages.isEmpty
                                ? 'Tap and hold any message to star it.'
                                : '${chatsController.starredMessages.length} starred.',
                            onTap: () => _openStarredMessages(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                              const SettingsRowDivider(),
                              SettingsTile(
                                key: const Key(
                                  'settings_blocked_contacts_tile',
                                ),
                                icon: Icons.block_outlined,
                                title: 'Blocked contacts',
                                subtitle: _blockedContactsCount() == 0
                                    ? 'No blocked contacts.'
                                    : '${_blockedContactsCount()} blocked.',
                                onTap: () => _openBlockedContacts(context),
                              ),
                              const SettingsRowDivider(),
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
                                  value: preferencesController
                                      .notificationsEnabled,
                                  onChanged: preferencesController
                                      .setNotificationsEnabled,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Column(
                            children: [
                              SettingsTile(
                                key: const Key('settings_backend_sync_tile'),
                                icon: Icons.cloud_sync_outlined,
                                title: 'Backend and sync',
                                subtitle: _backendSyncSubtitle(),
                                onTap: () => _openBackendSync(context),
                              ),
                              const SettingsRowDivider(),
                              SettingsTile(
                                key: const Key('settings_storage_data_tile'),
                                icon: Icons.folder_outlined,
                                title: 'Storage and data',
                                subtitle: chatsController.threads.isEmpty
                                    ? 'Media usage and auto-download settings.'
                                    : '${_mediaItemCount()} media items across your chats.',
                                onTap: () => _openStorageData(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: SettingsTile(
                            key: const Key('settings_help_tile'),
                            icon: Icons.help_outline_rounded,
                            title: 'Help',
                            subtitle: 'FAQ and contact support.',
                            onTap: () => _openHelp(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: SettingsTile(
                            key: const Key('settings_sign_out_tile'),
                            icon: Icons.logout_rounded,
                            title: 'Sign out',
                            subtitle: 'Sign out of WhatsWave on this device.',
                            destructive: true,
                            onTap: authController.isBusy
                                ? null
                                : () => _confirmSignOut(context),
                          ),
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
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProfileSettingsScreen(
          authController: authController,
          currentUser: activeUser,
        ),
      ),
    );
  }

  Future<void> _openStarredMessages(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StarredMessagesScreen(
          chatsController: chatsController,
          callsController: callsController,
          updatesController: updatesController,
          communitiesController: communitiesController,
        ),
      ),
    );
  }

  int _blockedContactsCount() =>
      chatsController.threads.where((thread) => thread.isBlocked).length;

  int _mediaItemCount() {
    var count = 0;
    for (final thread in chatsController.threads) {
      for (final message in thread.messages) {
        count += message.attachments.length;
      }
    }
    return count;
  }

  Future<void> _openBlockedContacts(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BlockedContactsScreen(chatsController: chatsController),
      ),
    );
  }

  Future<void> _openStorageData(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StorageDataScreen(
          chatsController: chatsController,
          preferencesController: preferencesController,
        ),
      ),
    );
  }

  Future<void> _openHelp(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const HelpScreen(),
      ),
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

  Future<void> _confirmSignOut(BuildContext context) async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Sign out?'),
          content: const Text(
            "You'll need to verify your phone number again to sign back in on this device.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('settings_confirm_sign_out_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sign out'),
            ),
          ],
        );
      },
    );

    if (shouldSignOut == true) {
      await authController.signOut();
    }
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
