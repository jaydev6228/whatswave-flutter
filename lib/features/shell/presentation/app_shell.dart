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
import '../../communities/application/communities_controller.dart';
import '../../communities/presentation/communities_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../updates/application/updates_controller.dart';
import '../../updates/presentation/updates_screen.dart';

enum AppTab { chats, updates, communities, calls, settings }

const double _kNavigationLabelBaseFontSize = 12;
const double _kMinNavigationLabelScale = 0.72;
const double _kCompactPhoneWidth = 320;
const double _kWidePhoneWidth = 430;

double navigationLabelScaleForWidth(double width) {
  if (width <= _kCompactPhoneWidth) {
    return _kMinNavigationLabelScale;
  }
  if (width >= _kWidePhoneWidth) {
    return 1;
  }

  final progress =
      (width - _kCompactPhoneWidth) / (_kWidePhoneWidth - _kCompactPhoneWidth);
  return _kMinNavigationLabelScale +
      ((1 - _kMinNavigationLabelScale) * progress);
}

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
    final theme = Theme.of(context);
    final navigationTheme = theme.navigationBarTheme;
    final navigationLabelScale =
        navigationLabelScaleForWidth(MediaQuery.sizeOf(context).width);
    final adaptiveLabelTextStyle =
        WidgetStateProperty.resolveWith<TextStyle?>((states) {
      final baseStyle = navigationTheme.labelTextStyle?.resolve(states) ??
          theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700) ??
          const TextStyle(fontWeight: FontWeight.w700);
      final fontSize = (baseStyle.fontSize ?? _kNavigationLabelBaseFontSize) *
          navigationLabelScale;
      return baseStyle.copyWith(fontSize: fontSize, height: 1);
    });

    final pages = [
      ChatsScreen(
        callsController: widget.callsController,
        controller: widget.chatsController,
        updatesController: widget.updatesController,
      ),
      UpdatesScreen(controller: widget.updatesController),
      CommunitiesScreen(controller: widget.communitiesController),
      CallsScreen(controller: widget.callsController),
      SettingsScreen(
        authController: widget.authController,
        currentUser: widget.currentUser,
        preferencesController: widget.preferencesController,
        integrationController: widget.integrationController,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentTab.index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: navigationTheme.copyWith(
          labelTextStyle: adaptiveLabelTextStyle,
        ),
        child: NavigationBar(
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
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_motion_outlined),
              selectedIcon: Icon(Icons.auto_awesome_motion_rounded),
              label: 'Updates',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups_rounded),
              label: 'Communities',
            ),
            NavigationDestination(
              icon: Icon(Icons.call_outlined),
              selectedIcon: Icon(Icons.call_rounded),
              label: 'Calls',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
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
