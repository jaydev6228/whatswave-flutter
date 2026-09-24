import 'package:flutter/material.dart';

import '../../../core/permissions/location_permission_dialog.dart';
import '../../shared/widgets/error_dialog.dart';
import '../application/calls_controller.dart';
import '../domain/call_contact.dart';
import '../domain/call_history_entry.dart';
import 'call_experience_screen.dart';

Future<void> startCallFlow(
  BuildContext context, {
  required CallsController controller,
  required CallContact contact,
  required CallType type,
}) async {
  await controller.startOutgoingCall(contact: contact, type: type);
  if (!context.mounted) {
    return;
  }

  await presentCallsControllerFeedback(
    context,
    controller,
    presentSession: true,
  );
}

Future<void> simulateIncomingCallFlow(
  BuildContext context, {
  required CallsController controller,
  required CallContact contact,
  required CallType type,
}) async {
  await controller.simulateIncomingCall(contact: contact, type: type);
  if (!context.mounted) {
    return;
  }

  await presentCallsControllerFeedback(
    context,
    controller,
    presentSession: true,
  );
}

Future<void> presentCallsControllerFeedback(
  BuildContext context,
  CallsController controller, {
  bool presentSession = false,
}) async {
  if (presentSession && controller.currentSession != null) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CallExperienceScreen(controller: controller),
        fullscreenDialog: true,
      ),
    );
    return;
  }

  if (controller.isPermissionDenied) {
    await showPermissionDeniedDialog(
      context,
      title: controller.permissionDeniedTitle,
      message: controller.errorMessage ??
          'You don’t have permission. Allow it in Settings to continue.',
      onOpenSettings: controller.openSettings,
    );
    controller.clearError();
    return;
  }

  final message = controller.errorMessage;
  if (message == null) {
    return;
  }

  await showErrorDialog(context, message);
  controller.clearError();
}
