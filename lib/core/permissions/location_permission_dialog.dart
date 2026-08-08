import 'package:flutter/material.dart';

/// Shown wherever location access is needed and denied, instead of a
/// persistent error banner (a banner tied to a shared controller field can
/// leak onto unrelated screens that read the same field).
Future<void> showLocationPermissionDeniedDialog(
  BuildContext context, {
  required Future<void> Function() onOpenSettings,
  String message =
      'Allow location access in Settings to use this feature.',
}) async {
  final shouldOpenSettings = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Location access needed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
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
      return AlertDialog(
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
