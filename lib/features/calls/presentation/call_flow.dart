import 'package:flutter/material.dart';

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

  await _presentCallExperienceIfNeeded(context, controller);
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

  await _presentCallExperienceIfNeeded(context, controller);
}

Future<void> _presentCallExperienceIfNeeded(
  BuildContext context,
  CallsController controller,
) async {
  if (controller.currentSession != null) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CallExperienceScreen(controller: controller),
        fullscreenDialog: true,
      ),
    );
    return;
  }

  final message = controller.errorMessage;
  if (message == null) {
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
  controller.clearError();
}
