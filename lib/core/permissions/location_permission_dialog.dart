import 'package:flutter/material.dart';
import 'package:whatswave/features/shared/widgets/liquid_glass.dart';

/// After the OS will not show its permission prompt again (iOS after the
/// first deny, Android after "Don't ask again"), this is the recovery path:
/// explain the block and jump to this app's Settings page on both platforms.
Future<void> showPermissionDeniedDialog(
  BuildContext context, {
  required String title,
  required String message,
  required Future<void> Function() onOpenSettings,
}) async {
  final shouldOpenSettings = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return LiquidGlassDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            key: const Key('permission_denied_open_settings_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Open Settings'),
          ),
        ],
      );
    },
  );

  if (shouldOpenSettings == true) {
    await onOpenSettings();
  }
}

/// Shown wherever location access is needed and denied, instead of a
/// persistent error banner (a banner tied to a shared controller field can
/// leak onto unrelated screens that read the same field).
Future<void> showLocationPermissionDeniedDialog(
  BuildContext context, {
  required Future<void> Function() onOpenSettings,
  String message =
      'You don’t have location permission. Allow it in Settings to use this feature.',
}) {
  return showPermissionDeniedDialog(
    context,
    title: 'Location access needed',
    message: message,
    onOpenSettings: onOpenSettings,
  );
}

/// Shown for a genuine location failure (GPS off, device error) -- distinct
/// from [showLocationPermissionDeniedDialog], which offers a way to fix the
/// underlying permission instead of just acknowledging the problem.
Future<void> showLocationErrorDialog(
  BuildContext context,
  String message,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return LiquidGlassDialog(
        title: const Text('Location unavailable'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
