import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/observability/app_telemetry.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/calls/domain/call_history_entry.dart';
import 'package:whatswave/features/calls/domain/call_permissions.dart';
import 'package:whatswave/features/calls/domain/call_session.dart';

void main() {
  test(
      'requests native-style permissions for a video call and records history on end',
      () async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      outgoingRingDuration: Duration.zero,
      outgoingConnectingDuration: Duration.zero,
      durationTickInterval: Duration.zero,
    );

    await controller.loadOverview();

    final contact = controller.favorites.first;
    final didStartImmediately = await controller.startOutgoingCall(
      contact: contact,
      type: CallType.video,
    );

    expect(didStartImmediately, isTrue);
    expect(controller.currentSession, isNotNull);
    expect(controller.currentSession?.phase, CallSessionPhase.connected);
    expect(controller.currentSession?.isVideo, isTrue);
    expect(controller.permissions.microphone, CallPermissionStatus.granted);
    expect(controller.permissions.camera, CallPermissionStatus.granted);

    await controller.endCurrentCall();

    expect(controller.currentSession, isNull);
    expect(controller.history.first.contactId, contact.id);
    expect(controller.history.first.status, CallHistoryStatus.completed);
    expect(controller.history.first.type, CallType.video);
  });

  test('marks an unanswered incoming call as missed', () async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      incomingMissedAfter: Duration.zero,
      durationTickInterval: Duration.zero,
    );

    await controller.loadOverview();

    final contact = controller.favorites[1];
    final didStart = await controller.simulateIncomingCall(
      contact: contact,
      type: CallType.audio,
    );

    expect(didStart, isTrue);
    expect(controller.currentSession, isNull);
    expect(controller.history.first.contactId, contact.id);
    expect(controller.history.first.status, CallHistoryStatus.missed);
    expect(controller.history.first.type, CallType.audio);
  });

  test('surfaces a transient load error and succeeds on retry', () async {
    final controller = CallsController(
      repository: FakeCallsRepository(
        latency: Duration.zero,
        failFetchOnce: true,
      ),
      permissionService: MemoryAppPermissionService(),
      durationTickInterval: Duration.zero,
    );

    await controller.loadOverview();

    expect(controller.hasLoaded, isFalse);
    expect(controller.errorMessage, 'Transient calls failure');

    await controller.loadOverview();

    expect(controller.hasLoaded, isTrue);
    expect(controller.errorMessage, isNull);
    expect(controller.favorites, isNotEmpty);
    expect(controller.history, isNotEmpty);
  });

  test('keeps the call closed when microphone access is denied', () async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(
        grantMicrophoneOnRequest: false,
      ),
      durationTickInterval: Duration.zero,
    );

    await controller.loadOverview();

    final didStart = await controller.startOutgoingCall(
      contact: controller.favorites.first,
      type: CallType.audio,
    );

    expect(didStart, isFalse);
    expect(controller.currentSession, isNull);
    expect(
      controller.errorMessage,
      'Microphone access is required for audio calls.',
    );
    expect(controller.permissions.microphone, CallPermissionStatus.denied);
  });

  test('records call-control telemetry across a connected video call',
      () async {
    final telemetry = LocalAppTelemetry(debugSink: (_) {});
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      telemetry: telemetry,
      outgoingRingDuration: Duration.zero,
      outgoingConnectingDuration: Duration.zero,
      durationTickInterval: Duration.zero,
    );

    await controller.loadOverview();

    final didStart = await controller.startOutgoingCall(
      contact: controller.favorites.first,
      type: CallType.video,
    );

    expect(didStart, isTrue);

    controller.toggleSpeaker();
    controller.toggleMute();
    controller.toggleLocalVideo();
    controller.switchCamera();
    await controller.endCurrentCall();

    final eventNames = telemetry.breadcrumbs
        .map((event) => event.name)
        .toList(growable: false);
    expect(
      eventNames,
      containsAllInOrder(<String>[
        'calls_overview_loaded',
        'call_permissions_requested',
        'call_permissions_granted',
        'call_outgoing_started',
        'call_connected',
        'call_speaker_toggled',
        'call_mute_toggled',
        'call_video_toggled',
        'call_camera_switched',
        'call_session_finished',
      ]),
    );

    final speakerEvent = telemetry.breadcrumbs.firstWhere(
      (event) => event.name == 'call_speaker_toggled',
    );
    expect(speakerEvent.attributes['enabled'], 'false');

    final cameraEvent = telemetry.breadcrumbs.firstWhere(
      (event) => event.name == 'call_camera_switched',
    );
    expect(cameraEvent.attributes['camera_position'], 'back');
  });

  test('records permission-denial telemetry for blocked video calls', () async {
    final telemetry = LocalAppTelemetry(debugSink: (_) {});
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(
        grantCameraOnRequest: false,
      ),
      telemetry: telemetry,
      durationTickInterval: Duration.zero,
    );

    await controller.loadOverview();

    final didStart = await controller.startOutgoingCall(
      contact: controller.favorites.first,
      type: CallType.video,
    );

    expect(didStart, isFalse);

    final deniedEvent = telemetry.breadcrumbs.firstWhere(
      (event) => event.name == 'call_permissions_denied',
    );
    expect(deniedEvent.attributes['type'], 'video');
    expect(deniedEvent.attributes['missing_permissions'], 'camera');
    expect(deniedEvent.attributes['camera'], 'denied');
  });
}
