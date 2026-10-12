import 'package:flutter/material.dart';

import '../controllers/app_preferences_controller.dart';
import '../session/app_lock_authenticator.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({
    required this.child,
    required this.controller,
    required this.isEnabled,
    this.authenticator,
    super.key,
  });

  final Widget child;
  final AppPreferencesController controller;
  final bool isEnabled;

  /// Overridden in tests. Defaults to the real OS-backed authenticator.
  final AppLockAuthenticator? authenticator;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  late final AppLockAuthenticator _authenticator =
      widget.authenticator ?? LocalAuthAppLockAuthenticator();

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
                child: _AppLockOverlay(
                  controller: widget.controller,
                  authenticator: _authenticator,
                ),
              )
            // Not locked, but on the way out of the foreground: hide the
            // content so the OS's app-switcher snapshot shows this and not
            // the open chat. No unlock UI -- coming straight back should
            // not demand Face ID.
            else if (widget.isEnabled && widget.controller.isPrivacyCovered)
              const Positioned.fill(child: _PrivacyCover()),
          ],
        );
      },
    );
  }
}

/// The lock screen.
///
/// Stateful because it actually authenticates: it prompts the OS as soon as
/// it appears, and only calls [AppPreferencesController.unlockApp] on a
/// positive result. Before this, the overlay was a button wired straight to
/// `unlockApp` -- anyone holding the phone was one tap from the whole
/// message history, which made the app lock decorative.
class _AppLockOverlay extends StatefulWidget {
  const _AppLockOverlay({
    required this.controller,
    required this.authenticator,
  });

  final AppPreferencesController controller;
  final AppLockAuthenticator authenticator;

  @override
  State<_AppLockOverlay> createState() => _AppLockOverlayState();
}

class _AppLockOverlayState extends State<_AppLockOverlay> {
  AppLockMethod? _method;
  bool _isAuthenticating = false;
  bool _wasDenied = false;

  @override
  void initState() {
    super.initState();
    // Prompt immediately: the lock engaging is itself the user's cue, and
    // making them tap a button first just adds a step to every unlock.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating || !mounted) {
      return;
    }
    setState(() => _isAuthenticating = true);

    final method = await widget.authenticator.availableMethod();
    if (!mounted) {
      return;
    }
    setState(() => _method = method);

    if (method == AppLockMethod.unavailable) {
      // Nothing on this device to authenticate against, so asking the OS
      // would just fail forever and strand the owner outside their own app.
      // Degrade to an explicit confirm and say why (see _body). On a device
      // with no passcode at all this costs nothing real: anyone holding the
      // phone already has everything on it.
      setState(() => _isAuthenticating = false);
      return;
    }

    final unlocked = await widget.authenticator.authenticate(
      reason: 'Unlock WhatsWave to see your chats, updates, and calls.',
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _isAuthenticating = false;
      _wasDenied = !unlocked;
    });

    if (unlocked) {
      widget.controller.unlockApp();
    }
  }

  String get _body {
    if (_isAuthenticating) {
      return 'Confirming it is you...';
    }
    // Checked before _wasDenied: "add a device lock" is more useful than
    // "that did not match" when there was nothing to match against.
    if (_method == AppLockMethod.unavailable) {
      // Said plainly rather than implying a check that cannot happen.
      return 'This device has no passcode or biometric set up, so there is '
          'nothing to check against. Add a device lock in Settings to secure '
          'WhatsWave properly.';
    }
    if (_wasDenied) {
      return 'That did not match. Try again to get back to your chats.';
    }
    return 'Unlock to return to your chats, updates, calls, and settings.';
  }

  IconData get _icon => switch (_method) {
        AppLockMethod.faceId => Icons.face_rounded,
        AppLockMethod.fingerprint => Icons.fingerprint_rounded,
        AppLockMethod.biometric => Icons.fingerprint_rounded,
        _ => Icons.lock_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final method = _method;
    return ColoredBox(
      // Fully opaque. At 0.97 the chat behind it stayed faintly legible,
      // which rather defeats the point of a lock screen.
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          // Scrolls rather than clipping: the denial and no-device-lock
          // copy is several lines, and at a large accessibility text scale
          // on a compact phone this card can exceed the viewport.
          child: SingleChildScrollView(
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
                          backgroundColor: theme.colorScheme.primary
                              .withValues(alpha: 0.12),
                          child: Icon(
                            _icon,
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
                          _body,
                          key: const Key('app_lock_body'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        if (_isAuthenticating)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: CircularProgressIndicator(),
                          )
                        else
                          FilledButton.icon(
                            key: const Key('app_lock_unlock_button'),
                            onPressed: method == AppLockMethod.unavailable
                                ? widget.controller.unlockApp
                                : _authenticate,
                            icon: Icon(
                              _wasDenied ? Icons.refresh_rounded : _icon,
                            ),
                            label: Text(
                              _wasDenied
                                  ? 'Try again'
                                  : (method?.actionLabel ?? 'Unlock app'),
                            ),
                          ),
                      ],
                    ),
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

/// Blank, brand-coloured screen shown while the app is leaving or returning
/// to the foreground, so the OS snapshot behind the app switcher never shows
/// anyone's messages. Deliberately inert: no buttons, nothing to read.
class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      key: const Key('app_lock_privacy_cover'),
      color: theme.colorScheme.surface,
      child: Center(
        child: Icon(
          Icons.lock_rounded,
          size: 40,
          color: theme.colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}
