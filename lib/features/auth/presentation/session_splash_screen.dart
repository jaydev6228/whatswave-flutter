import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';

class SessionSplashScreen extends StatelessWidget {
  const SessionSplashScreen({
    this.message,
    super.key,
  });

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.12),
              theme.scaffoldBackgroundColor,
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: theme.colorScheme.primary,
                  child: const Icon(
                    Icons.chat_bubble_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'WhatsWave',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message ??
                      'Restoring your session, chats, and recent activity.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 24),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppPalette.emerald,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
