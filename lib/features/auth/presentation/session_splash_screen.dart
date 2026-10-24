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
        // Scrollable Center: avatar, headline, status message and spinner
        // together exceed a 320x568 screen once text doubles -- by 12px with
        // the real "No saved session on this device yet." message a fresh
        // install actually shows. Centred while it fits, scrollable when it
        // does not.
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.sizeOf(context).height,
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
                    // Only a real status message from the auth controller. There
                    // used to be a fallback line describing what the app was
                    // doing, which said the same thing the spinner already does
                    // and showed on every launch whether or not anything was
                    // being restored.
                    if (message?.trim().isNotEmpty ?? false) ...[
                      const SizedBox(height: 8),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.72),
                        ),
                      ),
                    ],
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
        ),
      ),
    );
  }
}
