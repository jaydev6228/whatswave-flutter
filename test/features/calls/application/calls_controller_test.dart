import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/observability/app_telemetry.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/call_signaling_service.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/calls/domain/call_contact.dart';
import 'package:whatswave/features/calls/domain/call_history_entry.dart';
import 'package:whatswave/features/calls/data/ringtone_player.dart';
import 'package:whatswave/features/calls/domain/call_permissions.dart';
import 'package:whatswave/features/calls/domain/call_session.dart';
import 'package:whatswave/features/calls/domain/call_signal.dart';
import 'package:whatswave/features/calls/domain/group_call_participant.dart';

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

  test('deletes a single call history entry', () async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      durationTickInterval: Duration.zero,
    );

    await controller.loadOverview();
    final initialCount = controller.history.length;
    expect(initialCount, greaterThan(0));

    final entryToDelete = controller.history.first;
    final didDelete = await controller.deleteHistoryEntry(entryToDelete.id);

    expect(didDelete, isTrue);
    expect(controller.history.length, initialCount - 1);
    expect(
      controller.history.any((entry) => entry.id == entryToDelete.id),
      isFalse,
    );
  });

  test('surfaces an error when deleting a call history entry fails', () async {
    final repository = FakeCallsRepository(latency: Duration.zero);
    final controller = CallsController(
      repository: repository,
      permissionService: MemoryAppPermissionService(),
      durationTickInterval: Duration.zero,
    );

    await controller.loadOverview();
    final entryToDelete = controller.history.first;
    repository.failDeleteNext = true;

    final didDelete = await controller.deleteHistoryEntry(entryToDelete.id);

    expect(didDelete, isFalse);
    expect(controller.errorMessage, isNotNull);
    expect(
      controller.history.any((entry) => entry.id == entryToDelete.id),
      isTrue,
    );
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

  group('real (signaling-backed) calls', () {
    const realContact = CallContact(
      id: 'real-contact',
      name: 'Real Person',
      avatarLabel: 'RP',
      accentColor: Color(0xFF123456),
      uid: 'callee-uid',
    );

    test(
        'places a real outgoing call via signaling when the contact has a uid, '
        'and records the callee uid in history', () async {
      final signaling = FakeCallSignalingService();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        signalingService: signaling,
        durationTickInterval: Duration.zero,
      );

      await controller.loadOverview();

      final didStart = await controller.startOutgoingCall(
        contact: realContact,
        type: CallType.audio,
      );

      expect(didStart, isTrue);
      expect(signaling.placedCalleeUid, 'callee-uid');
      expect(controller.currentSession?.phase, CallSessionPhase.ringing);
      expect(controller.currentSession, isNotNull);
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentSession?.callId, isNotNull);
      expect(controller.currentSession?.isReal, isTrue);

      // Ended here (before LiveKit connects -- no tokenService/liveKitUrl
      // wired in this test) so this only exercises signaling + history,
      // not the media connection itself.
      await controller.endCurrentCall();

      expect(controller.currentSession, isNull);
      expect(controller.history.first.uid, 'callee-uid');
      expect(controller.history.first.status, CallHistoryStatus.canceled);
    });

    test('starts a real group call when member uids are provided', () async {
      final signaling = FakeCallSignalingService();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        signalingService: signaling,
        durationTickInterval: Duration.zero,
      );
      await controller.loadOverview();

      final didStart = await controller.startOutgoingCall(
        contact: const CallContact(
          id: 'design-sprint',
          name: 'Design Sprint',
          avatarLabel: 'DS',
          accentColor: Color(0xFF123456),
          isGroup: true,
          memberUids: <String>['uid-ava', 'uid-noah'],
        ),
        type: CallType.audio,
      );

      expect(didStart, isTrue);
      expect(signaling.placedType, CallType.audio);
      expect(controller.currentSession?.contact.isGroup, isTrue);
      expect(controller.currentSession?.phase, CallSessionPhase.ringing);
      expect(controller.currentSession, isNotNull);
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentSession?.isReal, isTrue);

      await controller.endCurrentCall();
      expect(controller.history.first.isGroup, isTrue);
    });

    test('rings on an incoming group call the same way as 1:1', () async {
      final signaling = FakeCallSignalingService();
      final uidController = StreamController<String?>();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        signalingService: signaling,
        currentUserIdStream: uidController.stream,
        durationTickInterval: Duration.zero,
      );

      await controller.loadOverview();
      uidController.add('uid-noah');
      await Future<void>.delayed(Duration.zero);

      final now = DateTime.now();
      signaling.emitIncomingCall(
        CallSignal(
          id: 'room-1_uid-noah',
          callerUid: 'uid-host',
          calleeUid: 'uid-noah',
          roomName: 'room-1',
          type: CallType.audio,
          status: CallSignalStatus.ringing,
          createdAt: now,
          updatedAt: now,
          callerName: 'Jay',
          isGroup: true,
          threadId: 'group-thread',
          threadName: 'Weekend Crew',
          participantUids: const <String>['uid-ava', 'uid-noah'],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentSession?.direction, CallDirection.incoming);
      expect(controller.currentSession?.contact.isGroup, isTrue);
      expect(controller.currentSession?.contact.name, 'Weekend Crew');
      expect(controller.currentSession?.roomName, 'room-1');

      await uidController.close();
    });

    test('shows the group host call screen before remote invites are placed',
        () async {
      final signaling = DelayedFakeCallSignalingService();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        signalingService: signaling,
        durationTickInterval: Duration.zero,
      );
      await controller.loadOverview();

      await controller.startOutgoingCall(
        contact: const CallContact(
          id: 'design-sprint',
          name: 'Design Sprint',
          avatarLabel: 'DS',
          accentColor: Color(0xFF123456),
          isGroup: true,
          memberUids: <String>['uid-ava'],
        ),
        type: CallType.audio,
      );

      expect(controller.currentSession, isNotNull);
      expect(controller.currentSession?.isReal, isFalse);
      expect(signaling.placeGroupCallStarted, isTrue);

      signaling.releasePlaceGroupCall.complete();
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentSession?.isReal, isTrue);
    });

    test('keeps a group host in the call while another member is still ringing',
        () async {
      final signaling = FakeCallSignalingService();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        signalingService: signaling,
        durationTickInterval: Duration.zero,
      );
      await controller.loadOverview();

      await controller.startOutgoingCall(
        contact: const CallContact(
          id: 'design-sprint',
          name: 'Design Sprint',
          avatarLabel: 'DS',
          accentColor: Color(0xFF123456),
          isGroup: true,
          memberUids: <String>['uid-ava', 'uid-noah'],
        ),
        type: CallType.audio,
      );
      await Future<void>.delayed(Duration.zero);

      signaling.setGroupInviteStatus(
        roomName: signaling.lastGroupRoomName!,
        inviteeUid: 'uid-ava',
        status: CallSignalStatus.ended,
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentSession, isNotNull);
    });

    test('ends a group host call once nobody is connected or still ringing',
        () async {
      final signaling = FakeCallSignalingService();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        signalingService: signaling,
        durationTickInterval: Duration.zero,
      );
      await controller.loadOverview();

      await controller.startOutgoingCall(
        contact: const CallContact(
          id: 'design-sprint',
          name: 'Design Sprint',
          avatarLabel: 'DS',
          accentColor: Color(0xFF123456),
          isGroup: true,
          memberUids: <String>['uid-ava', 'uid-noah'],
        ),
        type: CallType.audio,
      );
      await Future<void>.delayed(Duration.zero);

      signaling.setGroupInviteStatus(
        roomName: signaling.lastGroupRoomName!,
        inviteeUid: 'uid-ava',
        status: CallSignalStatus.ended,
      );
      signaling.setGroupInviteStatus(
        roomName: signaling.lastGroupRoomName!,
        inviteeUid: 'uid-noah',
        status: CallSignalStatus.declined,
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentSession, isNull);
      expect(controller.history.first.status, CallHistoryStatus.canceled);
    });

    test(
        'ends a group host call after the no-answer timeout with nobody joined',
        () async {
      final signaling = FakeCallSignalingService();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        signalingService: signaling,
        incomingMissedAfter: Duration.zero,
        durationTickInterval: Duration.zero,
      );
      await controller.loadOverview();

      await controller.startOutgoingCall(
        contact: const CallContact(
          id: 'design-sprint',
          name: 'Design Sprint',
          avatarLabel: 'DS',
          accentColor: Color(0xFF123456),
          isGroup: true,
          memberUids: <String>['uid-ava', 'uid-noah'],
        ),
        type: CallType.audio,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentSession, isNull);
      expect(controller.history.first.status, CallHistoryStatus.canceled);
    });

    test('builds a group participant list for the host', () async {
      final signaling = FakeCallSignalingService();
      final uidController = StreamController<String?>();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        signalingService: signaling,
        currentUserIdStream: uidController.stream,
        durationTickInterval: Duration.zero,
      );

      await controller.loadOverview();
      uidController.add('host-uid');
      await Future<void>.delayed(Duration.zero);

      await controller.startOutgoingCall(
        contact: const CallContact(
          id: 'design-sprint',
          name: 'Design Sprint',
          avatarLabel: 'DS',
          accentColor: Color(0xFF123456),
          isGroup: true,
          memberUids: <String>['uid-ava', 'uid-noah'],
          memberDisplayNames: <String, String>{
            'host-uid': 'Jay',
            'uid-ava': 'Ava Patel',
            'uid-noah': 'Noah Kim',
          },
        ),
        type: CallType.audio,
      );
      await Future<void>.delayed(Duration.zero);

      final participants = controller.groupCallParticipants;
      expect(participants.length, 3);
      expect(
        participants.firstWhere((entry) => entry.uid == 'host-uid').displayName,
        'You',
      );
      expect(
        participants.firstWhere((entry) => entry.uid == 'uid-ava').state,
        GroupCallParticipantState.ringing,
      );

      await uidController.close();
    });

    test('falls back to the simulated call when the contact has no uid',
        () async {
      final signaling = FakeCallSignalingService();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        signalingService: signaling,
        outgoingRingDuration: Duration.zero,
        outgoingConnectingDuration: Duration.zero,
        durationTickInterval: Duration.zero,
      );

      await controller.loadOverview();

      final didStart = await controller.startOutgoingCall(
        contact: controller.favorites.first,
        type: CallType.audio,
      );

      expect(didStart, isTrue);
      expect(signaling.placedCalleeUid, isNull);
      expect(controller.currentSession?.isReal, isFalse);
    });

    test('resolves the real caller identity stamped on an incoming signal',
        () async {
      final signaling = FakeCallSignalingService();
      final uidController = StreamController<String?>();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        signalingService: signaling,
        currentUserIdStream: uidController.stream,
        durationTickInterval: Duration.zero,
      );

      await controller.loadOverview();
      uidController.add('my-uid');
      await Future<void>.delayed(Duration.zero);

      signaling.emitIncomingCall(
        _testSignal(
          id: 'incoming-1',
          callerUid: 'caller-uid',
          calleeUid: 'my-uid',
          callerName: 'Ava Patel',
          callerAvatarLabel: 'AP',
          callerAccentColorArgb: 0xFF25D366,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final contact = controller.currentSession?.contact;
      expect(contact?.name, 'Ava Patel');
      expect(contact?.avatarLabel, 'AP');
      expect(contact?.accentColor, const Color(0xFF25D366));
      expect(contact?.uid, 'caller-uid');

      // Declining (rather than connecting through LiveKit, which this test
      // has no tokenService/liveKitUrl for) also confirms the caller's
      // real uid makes it into history for a redial later.
      await controller.declineIncomingCall();
      expect(controller.history.first.uid, 'caller-uid');
      expect(controller.history.first.status, CallHistoryStatus.declined);

      await uidController.close();
    });

    test(
        'falls back to a placeholder identity when the signal carries no '
        'caller name (e.g. an older-shaped call doc)', () async {
      final signaling = FakeCallSignalingService();
      final uidController = StreamController<String?>();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        signalingService: signaling,
        currentUserIdStream: uidController.stream,
        durationTickInterval: Duration.zero,
      );

      await controller.loadOverview();
      uidController.add('my-uid');
      await Future<void>.delayed(Duration.zero);

      signaling.emitIncomingCall(
        _testSignal(
          id: 'incoming-2',
          callerUid: 'caller-uid',
          calleeUid: 'my-uid',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentSession?.contact.name, 'Caller call');
      expect(controller.currentSession?.contact.avatarLabel, 'CA');

      await uidController.close();
    });

    test(
        'auto-declines an unanswered real incoming call and notifies the caller',
        () async {
      final signaling = FakeCallSignalingService();
      final uidController = StreamController<String?>();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        signalingService: signaling,
        currentUserIdStream: uidController.stream,
        incomingMissedAfter: Duration.zero,
        durationTickInterval: Duration.zero,
      );

      await controller.loadOverview();
      uidController.add('my-uid');
      await Future<void>.delayed(Duration.zero);

      signaling.emitIncomingCall(
        _testSignal(
          id: 'incoming-timeout',
          callerUid: 'caller-uid',
          calleeUid: 'my-uid',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentSession, isNull);
      expect(controller.history.first.status, CallHistoryStatus.missed);
      expect(
        signaling.statusOf('incoming-timeout'),
        CallSignalStatus.declined,
      );

      await uidController.close();
    });

    test('marks the caller session remote-ringing once the callee signals it',
        () async {
      final signaling = FakeCallSignalingService();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        signalingService: signaling,
        durationTickInterval: Duration.zero,
      );

      await controller.loadOverview();
      await controller.startOutgoingCall(
        contact: realContact,
        type: CallType.audio,
      );
      final callId = controller.currentSession!.callId!;
      expect(controller.currentSession?.isRemoteRinging, isFalse);

      await signaling.markCalleeRinging(callId);
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentSession?.isRemoteRinging, isTrue);
    });
  });

  group('ringing', () {
    test('rings on an incoming call and stops when it is accepted', () async {
      final ringtonePlayer = FakeRingtonePlayer();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        ringtonePlayer: ringtonePlayer,
        durationTickInterval: Duration.zero,
      );

      await controller.loadOverview();
      await controller.simulateIncomingCall(
        contact: controller.favorites.first,
        type: CallType.audio,
      );

      expect(ringtonePlayer.playCount, greaterThan(0));
      expect(ringtonePlayer.isRinging, isTrue);

      await controller.acceptIncomingCall();

      expect(ringtonePlayer.isRinging, isFalse);
    });

    test('stops ringing when an incoming call is declined', () async {
      final ringtonePlayer = FakeRingtonePlayer();
      final controller = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
        permissionService: MemoryAppPermissionService(),
        ringtonePlayer: ringtonePlayer,
        durationTickInterval: Duration.zero,
      );

      await controller.loadOverview();
      await controller.simulateIncomingCall(
        contact: controller.favorites.first,
        type: CallType.audio,
      );
      expect(ringtonePlayer.isRinging, isTrue);

      await controller.declineIncomingCall();

      expect(ringtonePlayer.isRinging, isFalse);
    });
  });
}

class FakeRingtonePlayer implements RingtonePlayer {
  int playCount = 0;
  bool isRinging = false;

  @override
  void play() {
    playCount++;
    isRinging = true;
  }

  @override
  void stop() {
    isRinging = false;
  }
}

CallSignal _testSignal({
  required String id,
  required String callerUid,
  required String calleeUid,
  String? callerName,
  String? callerAvatarLabel,
  int? callerAccentColorArgb,
}) {
  final now = DateTime.now();
  return CallSignal(
    id: id,
    callerUid: callerUid,
    calleeUid: calleeUid,
    roomName: id,
    type: CallType.video,
    status: CallSignalStatus.ringing,
    createdAt: now,
    updatedAt: now,
    callerName: callerName,
    callerAvatarLabel: callerAvatarLabel,
    callerAccentColorArgb: callerAccentColorArgb,
  );
}

/// In-memory [CallSignalingService] test double -- mirrors
/// MemoryCallSignalingService's shape (see call_signaling_service.dart) but
/// exposes emitIncomingCall/placedCalleeUid so tests can drive and observe
/// it directly.
class FakeCallSignalingService implements CallSignalingService {
  final Map<String, CallSignal> _calls = <String, CallSignal>{};
  final StreamController<CallSignal?> _incomingController =
      StreamController<CallSignal?>.broadcast();
  final Map<String, StreamController<CallSignal?>> _callControllers =
      <String, StreamController<CallSignal?>>{};
  final Map<String, StreamController<Map<String, CallSignalStatus>>>
      _groupInviteControllers =
      <String, StreamController<Map<String, CallSignalStatus>>>{};
  final Map<String, Map<String, CallSignalStatus>> _groupInviteStatuses =
      <String, Map<String, CallSignalStatus>>{};
  int _sequence = 0;

  String? placedCalleeUid;
  CallType? placedType;
  String? lastGroupRoomName;

  String _groupInviteCallId(String roomName, String inviteeUid) =>
      '${roomName}_$inviteeUid';

  @override
  Future<CallSignal> placeGroupCall({
    required String threadId,
    required String threadName,
    required List<String> participantUids,
    required CallType type,
    Map<String, String>? participantDisplayNames,
    Map<String, String>? participantAvatarUrls,
  }) async {
    placedCalleeUid = participantUids.isEmpty ? null : participantUids.first;
    placedType = type;
    final now = DateTime.now();
    final id = 'fake-group-call-${_sequence++}';
    lastGroupRoomName = id;
    final resolvedDisplayNames = <String, String>{
      ...?participantDisplayNames,
      'test-caller-uid': 'Test Host',
    };
    final resolvedAvatarUrls = <String, String>{
      ...?participantAvatarUrls,
    };
    final signal = CallSignal(
      id: id,
      callerUid: 'test-caller-uid',
      calleeUid: '',
      roomName: id,
      type: type,
      status: CallSignalStatus.active,
      createdAt: now,
      updatedAt: now,
      isGroup: true,
      threadId: threadId,
      threadName: threadName,
      participantUids: participantUids,
      participantDisplayNames: resolvedDisplayNames,
      participantAvatarUrls: resolvedAvatarUrls,
    );
    _calls[id] = signal;
    _groupInviteStatuses[id] = <String, CallSignalStatus>{
      for (final uid in participantUids) uid: CallSignalStatus.ringing,
    };
    for (final uid in participantUids) {
      final inviteId = _groupInviteCallId(id, uid);
      _calls[inviteId] = CallSignal(
        id: inviteId,
        callerUid: 'test-caller-uid',
        calleeUid: uid,
        roomName: id,
        type: type,
        status: CallSignalStatus.ringing,
        createdAt: now,
        updatedAt: now,
        isGroup: true,
        threadId: threadId,
        threadName: threadName,
        participantUids: participantUids,
      );
    }
    _emitGroupInviteStatuses(id);
    return signal;
  }

  @override
  Future<CallSignal> placeCall({
    required String calleeUid,
    required CallType type,
  }) async {
    placedCalleeUid = calleeUid;
    placedType = type;
    final now = DateTime.now();
    final id = 'fake-call-${_sequence++}';
    final signal = CallSignal(
      id: id,
      callerUid: 'test-caller-uid',
      calleeUid: calleeUid,
      roomName: id,
      type: type,
      status: CallSignalStatus.ringing,
      createdAt: now,
      updatedAt: now,
    );
    _calls[id] = signal;
    return signal;
  }

  @override
  Stream<CallSignal?> watchIncomingCall(String myUid) {
    return _incomingController.stream;
  }

  @override
  Stream<CallSignal?> watchCall(String callId) {
    return _callControllers
        .putIfAbsent(callId, () => StreamController<CallSignal?>.broadcast())
        .stream;
  }

  @override
  Stream<Map<String, CallSignalStatus>> watchGroupInviteStatuses({
    required String roomName,
    required List<String> participantUids,
  }) {
    final controller = _groupInviteControllers.putIfAbsent(
      roomName,
      () => StreamController<Map<String, CallSignalStatus>>.broadcast(),
    );
    final initial = _groupInviteStatuses[roomName];
    if (initial != null) {
      Future<void>.microtask(
        () => controller.add(Map<String, CallSignalStatus>.from(initial)),
      );
    }
    return controller.stream;
  }

  void setGroupInviteStatus({
    required String roomName,
    required String inviteeUid,
    required CallSignalStatus status,
  }) {
    final statuses = _groupInviteStatuses.putIfAbsent(
      roomName,
      () => <String, CallSignalStatus>{},
    );
    statuses[inviteeUid] = status;
    final inviteId = _groupInviteCallId(roomName, inviteeUid);
    final existing = _calls[inviteId];
    if (existing != null) {
      _calls[inviteId] = existing.copyWith(
        status: status,
        updatedAt: DateTime.now(),
      );
    }
    _emitGroupInviteStatuses(roomName);
  }

  void _emitGroupInviteStatuses(String roomName) {
    final statuses = _groupInviteStatuses[roomName];
    if (statuses == null) {
      return;
    }
    _groupInviteControllers[roomName]?.add(
      Map<String, CallSignalStatus>.from(statuses),
    );
  }

  @override
  Future<void> updateStatus(String callId, CallSignalStatus status) async {
    final existing = _calls[callId];
    if (existing == null) {
      return;
    }
    final updated =
        existing.copyWith(status: status, updatedAt: DateTime.now());
    _calls[callId] = updated;
    _callControllers[callId]?.add(updated);
  }

  @override
  Future<void> markCalleeRinging(String callId) async {
    final existing = _calls[callId];
    if (existing == null) {
      return;
    }
    final updated = existing.copyWith(
      calleeRinging: true,
      updatedAt: DateTime.now(),
    );
    _calls[callId] = updated;
    _callControllers[callId]?.add(updated);
  }

  void emitIncomingCall(CallSignal signal) {
    _calls[signal.id] = signal;
    _incomingController.add(signal);
  }

  CallSignalStatus? statusOf(String callId) => _calls[callId]?.status;
}

class DelayedFakeCallSignalingService extends FakeCallSignalingService {
  final Completer<void> releasePlaceGroupCall = Completer<void>();
  var placeGroupCallStarted = false;

  @override
  Future<CallSignal> placeGroupCall({
    required String threadId,
    required String threadName,
    required List<String> participantUids,
    required CallType type,
    Map<String, String>? participantDisplayNames,
    Map<String, String>? participantAvatarUrls,
  }) async {
    placeGroupCallStarted = true;
    await releasePlaceGroupCall.future;
    return super.placeGroupCall(
      threadId: threadId,
      threadName: threadName,
      participantUids: participantUids,
      type: type,
      participantDisplayNames: participantDisplayNames,
      participantAvatarUrls: participantAvatarUrls,
    );
  }
}
