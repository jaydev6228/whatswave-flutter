import 'package:flutter/material.dart';
import 'package:whatswave/features/shared/widgets/liquid_glass.dart';

/// Shown for a one-off action failure, instead of a `SnackBar` -- matches
/// [showLocationErrorDialog]'s existing precedent of using a modal dialog
/// rather than a pinned top/bottom banner for transient error feedback.
Future<void> showErrorDialog(
  BuildContext context,
  String message, {
  String title = 'Something went wrong',
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return LiquidGlassDialog(
        title: Text(title),
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
