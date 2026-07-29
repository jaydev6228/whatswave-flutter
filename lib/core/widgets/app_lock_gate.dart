import 'package:flutter/material.dart';

import '../controllers/app_preferences_controller.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({
    required this.child,
    required this.controller,
    required this.isEnabled,
    super.key,
  });

  final Widget child;
  final AppPreferencesController controller;
  final bool isEnabled;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.controller.handleLifecycleChange(state);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Stack(
          children: [
            widget.child,
            if (widget.isEnabled && widget.controller.isAppLocked)
              Positioned.fill(
                child: _AppLockOverlay(controller: widget.controller),
              ),
          ],
        );
      },
    );
  }
}

class _AppLockOverlay extends StatelessWidget {
  const _AppLockOverlay({required this.controller});

  final AppPreferencesController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface.withValues(alpha: 0.97),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    key: const Key('app_lock_overlay'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        child: Icon(
                          Icons.lock_rounded,
                          color: theme.colorScheme.primary,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'WhatsWave is locked',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Unlock to return to your chats, updates, calls, and settings.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        key: const Key('app_lock_unlock_button'),
                        onPressed: controller.unlockApp,
                        icon: const Icon(Icons.lock_open_rounded),
                        label: const Text('Unlock app'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
