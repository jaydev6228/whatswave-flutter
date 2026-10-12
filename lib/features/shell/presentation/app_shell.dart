import 'package:flutter/material.dart';

import '../../../core/controllers/app_preferences_controller.dart';
import '../../../core/integrations/integration_hub_controller.dart';
import '../../../core/models/app_user.dart';
import '../../../core/observability/app_telemetry.dart';
import '../../../core/session/backend_reachability.dart';
import '../../auth/application/auth_controller.dart';
import '../../calls/application/calls_controller.dart';
import '../../calls/presentation/calls_screen.dart';
import '../../chats/application/chats_controller.dart';
import '../../chats/presentation/chats_screen.dart';
import '../../chats/presentation/conversation_screen.dart';
import '../../chats/presentation/new_chat_screen.dart';
import '../../communities/application/communities_controller.dart';
import '../../communities/presentation/communities_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../updates/application/updates_controller.dart';
import 'floating_tab_bar.dart';
import 'tab_crossfade_stack.dart';
import '../../shared/sheet_route.dart';

enum AppTab { chats, communities, calls, settings }

class AppShell extends StatefulWidget {
  const AppShell({
    required this.authController,
    required this.currentUser,
    required this.preferencesController,
    required this.integrationController,
    required this.callsController,
    required this.chatsController,
    required this.communitiesController,
    required this.updatesController,
    this.reachability,
    super.key,
  });

  final AuthController authController;
  final AppUser currentUser;
  final AppPreferencesController preferencesController;
  final IntegrationHubController integrationController;
  final CallsController callsController;
  final ChatsController chatsController;
  final CommunitiesController communitiesController;
  final UpdatesController updatesController;

  /// Null in local/seeded builds, which have no backend to be cut off from.
  final BackendReachability? reachability;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _currentTab = AppTab.chats;
  bool _trackedInitialTab = false;

  @override
  void initState() {
    super.initState();
    widget.chatsController.ensureLoaded();
    widget.updatesController.ensureLoaded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_trackedInitialTab) {
      return;
    }

    _trackedInitialTab = true;
    _trackScreenView(_currentTab, initial: true);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ChatsScreen(
        callsController: widget.callsController,
        communitiesController: widget.communitiesController,
        controller: widget.chatsController,
        updatesController: widget.updatesController,
        authController: widget.authController,
      ),
      CommunitiesScreen(
        controller: widget.communitiesController,
        chatsController: widget.chatsController,
        callsController: widget.callsController,
        updatesController: widget.updatesController,
      ),
      CallsScreen(
        controller: widget.callsController,
        communitiesController: widget.communitiesController,
      ),
      SettingsScreen(
        authController: widget.authController,
        currentUser: widget.currentUser,
        preferencesController: widget.preferencesController,
        integrationController: widget.integrationController,
        chatsController: widget.chatsController,
        callsController: widget.callsController,
        updatesController: widget.updatesController,
        communitiesController: widget.communitiesController,
      ),
    ];

    return Scaffold(
      // The tab bar and compose button float over the page at the bottom of
      // the screen, and they belong there whether or not a keyboard is up.
      // Scaffold's default shrinks the whole body by the keyboard's height,
      // which carried both of them up with it the moment the chat search
      // field took focus.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          TabCrossfadeStack(
            index: _currentTab.index,
            children: pages,
          ),
          // One banner for every tab rather than per-screen: being offline
          // is an app-wide fact, and the chats, updates and calls lists are
          // all equally stale while it holds.
          if (widget.reachability != null)
            Align(
              alignment: Alignment.topCenter,
              child: _OfflineBanner(reachability: widget.reachability!),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: AnimatedBuilder(
                animation: widget.chatsController,
                builder: (context, _) {
                  final unreadChatCount =
                      widget.chatsController.unreadThreadCount;
                  final showComposeFab = _currentTab == AppTab.chats;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FloatingTabBarFabTransition(
                        visible: showComposeFab,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16, bottom: 14),
                          child: FloatingTabBarFab(
                            icon: Icons.add_comment_outlined,
                            tooltip: 'New chat',
                            onPressed: () => _openNewChat(context),
                          ),
                        ),
                      ),
                      FloatingTabBar(
                        selectedIndex: _currentTab.index,
                        onDestinationSelected: (index) {
                          final nextTab = AppTab.values[index];
                          if (nextTab == _currentTab) {
                            return;
                          }

                          AppTelemetryScope.of(context).recordInteraction(
                            'navigation_tab_selected',
                            attributes: <String, Object?>{
                              'from': _currentTab.name,
                              'to': nextTab.name,
                            },
                          );
                          setState(() => _currentTab = nextTab);
                          _trackScreenView(nextTab);
                        },
                        destinations: [
                          FloatingTabDestination(
                            icon: Icons.chat_bubble_outline_rounded,
                            selectedIcon: Icons.chat_bubble_rounded,
                            tooltip: 'Chats',
                            badgeCount: unreadChatCount,
                          ),
                          const FloatingTabDestination(
                            icon: Icons.groups_outlined,
                            selectedIcon: Icons.groups_rounded,
                            tooltip: 'Communities',
                          ),
                          const FloatingTabDestination(
                            icon: Icons.call_outlined,
                            selectedIcon: Icons.call_rounded,
                            tooltip: 'Calls',
                          ),
                          const FloatingTabDestination(
                            icon: Icons.settings_outlined,
                            selectedIcon: Icons.settings_rounded,
                            tooltip: 'Settings',
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openNewChat(BuildContext context) async {
    // Presented, not navigated to: WhatsApp raises the new-chat picker from
    // the bottom, and MaterialPageRoute's sideways push read as going
    // "deeper" into the chat list rather than opening a chooser over it.
    final threadId = await Navigator.of(context).push<String>(
      appSheetRoute<String>(
        name: 'new_chat',
        builder: (_) => NewChatScreen(
          communitiesController: widget.communitiesController,
          chatsController: widget.chatsController,
          callsController: widget.callsController,
        ),
      ),
    );
    if (!mounted || !context.mounted || threadId == null) {
      return;
    }

    widget.chatsController.openThread(threadId);
    widget.chatsController.ensureThreadMessagesLoaded(threadId);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          callsController: widget.callsController,
          controller: widget.chatsController,
          updatesController: widget.updatesController,
          communitiesController: widget.communitiesController,
          threadId: threadId,
        ),
      ),
    );
  }

  void _trackScreenView(
    AppTab tab, {
    bool initial = false,
  }) {
    AppTelemetryScope.of(context).recordScreenView(
      'tab_${tab.name}',
      attributes: <String, Object?>{
        'tab': tab.name,
        'initial': initial,
      },
    );
  }
}

/// Thin bar that appears when reads start coming from the local cache.
///
/// Says "not current" rather than "no internet": the signal is Firestore's
/// own cache-vs-server metadata, which also catches a captive portal, an
/// expired token or a backend outage -- none of which are the user's wifi
/// being off, and all of which look identical from their side.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.reachability});

  final BackendReachability reachability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: reachability,
      builder: (context, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: !reachability.isOffline
              ? const SizedBox.shrink()
              : SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Material(
                      key: const Key('offline_banner'),
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off_rounded,
                              size: 18,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 10),
                            // Flexible + wrapping, never a fixed height:
                            // this has to survive a 200% text scale on a
                            // compact phone (docs/ui_layout_guidelines.md).
                            Flexible(
                              child: Text(
                                "Offline. You're seeing saved messages, and "
                                'anything you send will go out when you '
                                'reconnect.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
