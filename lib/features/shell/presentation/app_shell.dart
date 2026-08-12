import 'package:flutter/material.dart';

import '../../../core/controllers/app_preferences_controller.dart';
import '../../../core/integrations/integration_hub_controller.dart';
import '../../../core/models/app_user.dart';
import '../../../core/observability/app_telemetry.dart';
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
      body: Stack(
        children: [
          IndexedStack(
            index: _currentTab.index,
            children: pages,
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
                      if (showComposeFab)
                        Padding(
                          padding: const EdgeInsets.only(right: 16, bottom: 14),
                          child: FloatingTabBarFab(
                            icon: Icons.add_comment_outlined,
                            tooltip: 'New chat',
                            onPressed: () => _openNewChat(context),
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
    final threadId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
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
