import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../../core/observability/app_telemetry.dart';
import '../../../core/permissions/app_permission_service.dart';
import '../data/call_signaling_service.dart';
import '../data/calls_repository.dart';
import '../data/livekit_token_service.dart';
import '../domain/call_contact.dart';
import '../domain/call_history_entry.dart';
import '../domain/call_permissions.dart';
import '../domain/call_session.dart';
import '../domain/call_signal.dart';

class CallsController extends ChangeNotifier {
  CallsController({
    required CallsRepository repository,
    AppPermissionService? permissionService,
    AppTelemetry? telemetry,
    DateTime Function()? now,
    CallSignalingService? signalingService,
    LiveKitTokenService? tokenService,
    String? liveKitUrl,
    Stream<String?>? currentUserIdStream,
    this.outgoingRingDuration = const Duration(milliseconds: 900),
    this.outgoingConnectingDuration = const Duration(milliseconds: 700),
    this.incomingMissedAfter = const Duration(seconds: 18),
    this.durationTickInterval = const Duration(seconds: 1),
  })  : _repository = repository,
        _permissionService = permissionService ?? MemoryAppPermissionService(),
        _telemetry = telemetry ?? NoopAppTelemetry.instance,
        _now = now ?? DateTime.now,
        _signalingService = signalingService,
        _tokenService = tokenService,
        _liveKitUrl = liveKitUrl {
    if (currentUserIdStream != null && signalingService != null) {
      _authUidSubscription = currentUserIdStream.listen(_handleUidChanged);
    }
  }

  final CallsRepository _repository;
  final AppPermissionService _permissionService;
  final AppTelemetry _telemetry;
  final DateTime Function() _now;
  final CallSignalingService? _signalingService;
  final LiveKitTokenService? _tokenService;
  final String? _liveKitUrl;
  final Duration outgoingRingDuration;
  final Duration outgoingConnectingDuration;
  final Duration incomingMissedAfter;
  final Duration durationTickInterval;

  bool _hasLoaded = false;
  bool _isLoading = false;
  bool _isClearingHistory = false;
  String? _errorMessage;
  List<CallContact> _favorites = const <CallContact>[];
  List<CallHistoryEntry> _history = const <CallHistoryEntry>[];
  CallPermissions _permissions = const CallPermissions();
  CallSession? _currentSession;
  Timer? _phaseTimer;
  Timer? _durationTicker;
  int _sessionSequence = 0;

  StreamSubscription<String?>? _authUidSubscription;
  StreamSubscription<CallSignal?>? _incomingSignalSubscription;
  StreamSubscription<CallSignal?>? _activeSignalSubscription;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _roomListener;
  lk.LocalVideoTrack? _localVideoTrack;
  lk.VideoTrack? _remoteVideoTrack;

  bool get hasLoaded => _hasLoaded;
  bool get isLoading => _isLoading;
  bool get isClearingHistory => _isClearingHistory;
  String? get errorMessage => _errorMessage;
  List<CallContact> get favorites => List<CallContact>.unmodifiable(_favorites);
  List<CallHistoryEntry> get history =>
      List<CallHistoryEntry>.unmodifiable(_history);
  CallPermissions get permissions => _permissions;
  CallSession? get currentSession => _currentSession;

  /// The local camera preview for a real (LiveKit-backed) call. Null for
  /// simulated calls, or before the camera has connected.
  lk.LocalVideoTrack? get localVideoTrack => _localVideoTrack;

  /// The remote participant's video track for a real call. Null for
  /// simulated calls, audio-only calls, or before the peer's video arrives.
  lk.VideoTrack? get remoteVideoTrack => _remoteVideoTrack;

  Future<void> ensureLoaded() async {
    if (_hasLoaded || _isLoading) {
      return;
    }
    await loadOverview();
  }

  Future<void> loadOverview() async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final overview = await _repository.fetchOverview();
      _favorites = overview.favorites;
      _history = overview.history;
      _permissions = await _permissionService.callPermissionsStatus();
      _hasLoaded = true;
      _telemetry.recordInteraction(
        'calls_overview_loaded',
        attributes: <String, Object?>{
          'favorites_count': _favorites.length,
          'history_count': _history.length,
          ..._permissionTelemetryAttributes(_permissions),
        },
      );
    } on CallsRepositoryException catch (error, stackTrace) {
      _errorMessage = error.message;
      _telemetry.recordError(
        error,
        stackTrace,
        source: 'calls_overview',
        fatal: false,
      );
    } catch (error, stackTrace) {
      _errorMessage = 'We could not load your calls right now.';
      _telemetry.recordError(
        error,
        stackTrace,
        source: 'calls_overview',
        fatal: false,
      );
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> clearHistory() async {
    if (_isClearingHistory) {
      return;
    }

    _isClearingHistory = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _history = await _repository.clearHistory();
      _telemetry.recordInteraction(
        'call_history_cleared',
        attributes: <String, Object?>{
          'history_count': _history.length,
        },
      );
    } on CallsRepositoryException catch (error, stackTrace) {
      _errorMessage = error.message;
      _telemetry.recordError(
        error,
        stackTrace,
        source: 'call_history_clear',
        fatal: false,
      );
    } catch (error, stackTrace) {
      _errorMessage = 'We could not clear recent calls right now.';
      _telemetry.recordError(
        error,
        stackTrace,
        source: 'call_history_clear',
        fatal: false,
      );
    }

    _isClearingHistory = false;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }

    _errorMessage = null;
    notifyListeners();
  }

  void resetPermissions() {
    _permissions = const CallPermissions();
    _errorMessage = null;
    _telemetry.recordInteraction('call_permissions_reset');
    notifyListeners();
  }

  Future<bool> startOutgoingCall({
    required CallContact contact,
    required CallType type,
  }) async {
    if (_currentSession != null) {
      _errorMessage = 'Finish the current call before starting another one.';
      _telemetry.recordInteraction(
        'call_start_blocked',
        attributes: <String, Object?>{
          'reason': 'call_already_active',
          'type': type.name,
          'contact_id': contact.id,
        },
      );
      notifyListeners();
      return false;
    }

    if (!await _ensurePermissions(type)) {
      return false;
    }

    final calleeUid = contact.uid;
    final signaling = _signalingService;
    if (calleeUid != null && signaling != null) {
      return _beginRealOutgoingSession(
        contact: contact,
        type: type,
        calleeUid: calleeUid,
        signaling: signaling,
      );
    }

    _telemetry.recordInteraction(
      'call_outgoing_started',
      attributes: _callAttributes(
        contact: contact,
        type: type,
      ),
    );
    _beginOutgoingSession(contact: contact, type: type);
    return true;
  }

  Future<bool> _beginRealOutgoingSession({
    required CallContact contact,
    required CallType type,
    required String calleeUid,
    required CallSignalingService signaling,
  }) async {
    _cancelTimers();
    _errorMessage = null;

    try {
      final signal = await signaling.placeCall(
        calleeUid: calleeUid,
        type: type,
      );
      final session = CallSession(
        id: 'call-${_sessionSequence++}',
        contact: contact,
        type: type,
        direction: CallDirection.outgoing,
        phase: CallSessionPhase.ringing,
        createdAt: _now(),
        isSpeakerOn: type == CallType.video,
        isLocalVideoEnabled: type == CallType.video,
        callId: signal.id,
      );
      _currentSession = session;
      _telemetry.recordInteraction(
        'call_outgoing_started',
        attributes: _callAttributes(
          contact: contact,
          type: type,
          extra: <String, Object?>{'real': true},
        ),
      );
      notifyListeners();
      _watchActiveSignal(signal.id);
      return true;
    } catch (error, stackTrace) {
      _errorMessage = 'We could not start that call right now.';
      _telemetry.recordError(
        error,
        stackTrace,
        source: 'call_place',
        fatal: false,
        attributes: <String, Object?>{
          'contact_id': contact.id,
          'type': type.name,
        },
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> simulateIncomingCall({
    required CallContact contact,
    required CallType type,
  }) async {
    if (_currentSession != null) {
      _errorMessage = 'Finish the current call before starting another one.';
      _telemetry.recordInteraction(
        'call_incoming_blocked',
        attributes: <String, Object?>{
          'reason': 'call_already_active',
          'type': type.name,
          'contact_id': contact.id,
        },
      );
      notifyListeners();
      return false;
    }

    _cancelTimers();
    _errorMessage = null;
    final session = CallSession(
      id: 'call-${_sessionSequence++}',
      contact: contact,
      type: type,
      direction: CallDirection.incoming,
      phase: CallSessionPhase.incoming,
      createdAt: _now(),
      isSpeakerOn: type == CallType.video,
      isLocalVideoEnabled: type == CallType.video,
    );
    _currentSession = session;
    _telemetry.recordInteraction(
      'call_incoming_simulated',
      attributes: _sessionTelemetryAttributes(session),
    );
    notifyListeners();

    _schedulePhaseTimer(incomingMissedAfter, () {
      final current = _currentSession;
      if (current == null ||
          current.id != session.id ||
          current.phase != CallSessionPhase.incoming) {
        return;
      }
      _finishSession(status: CallHistoryStatus.missed);
    });
    return true;
  }

  Future<bool> acceptIncomingCall() async {
    final session = _currentSession;
    if (session == null || session.phase != CallSessionPhase.incoming) {
      return false;
    }

    if (!await _ensurePermissions(session.type)) {
      return false;
    }

    _telemetry.recordInteraction(
      'call_incoming_accepted',
      attributes: _sessionTelemetryAttributes(session),
    );

    if (session.isReal) {
      try {
        await _signalingService!.updateStatus(
          session.callId!,
          CallSignalStatus.accepted,
        );
      } catch (error, stackTrace) {
        _errorMessage = 'We could not accept that call right now.';
        _telemetry.recordError(
          error,
          stackTrace,
          source: 'call_accept',
          fatal: false,
        );
        notifyListeners();
        return false;
      }
      // Joining LiveKit happens in _handleSignalUpdate, reacting to our own
      // status write above via the watchCall subscription already started
      // by _handleIncomingSignal.
      return true;
    }

    _transitionToConnecting(session.id);
    return true;
  }

  Future<void> declineIncomingCall() async {
    final session = _currentSession;
    if (session == null) {
      return;
    }

    if (session.phase == CallSessionPhase.incoming) {
      _telemetry.recordInteraction(
        'call_incoming_declined',
        attributes: _sessionTelemetryAttributes(session),
      );
      if (session.isReal) {
        try {
          await _signalingService!
              .updateStatus(session.callId!, CallSignalStatus.declined);
        } catch (_) {
          // Best-effort -- we're finishing the local session regardless.
        }
      }
      await _finishSession(status: CallHistoryStatus.declined);
      return;
    }

    await endCurrentCall();
  }

  Future<void> endCurrentCall() async {
    final session = _currentSession;
    if (session == null) {
      return;
    }

    if (session.isReal) {
      try {
        await _signalingService!
            .updateStatus(session.callId!, CallSignalStatus.ended);
      } catch (_) {
        // Best-effort -- we're finishing the local session regardless.
      }
    }

    final status = switch (session.phase) {
      CallSessionPhase.connected => CallHistoryStatus.completed,
      CallSessionPhase.incoming => CallHistoryStatus.declined,
      _ => session.direction == CallDirection.outgoing
          ? CallHistoryStatus.canceled
          : CallHistoryStatus.failed,
    };
    await _finishSession(status: status);
  }

  void toggleMute() {
    final session = _currentSession;
    if (session == null) {
      return;
    }

    final isMuted = !session.isMuted;
    _currentSession = session.copyWith(isMuted: isMuted);
    if (session.isReal) {
      unawaited(_room?.localParticipant?.setMicrophoneEnabled(!isMuted));
    }
    _telemetry.recordInteraction(
      'call_mute_toggled',
      attributes: _sessionTelemetryAttributes(
        _currentSession!,
        extra: <String, Object?>{
          'enabled': isMuted,
        },
      ),
    );
    notifyListeners();
  }

  void toggleSpeaker() {
    final session = _currentSession;
    if (session == null) {
      return;
    }

    final isSpeakerOn = !session.isSpeakerOn;
    _currentSession = session.copyWith(isSpeakerOn: isSpeakerOn);
    if (session.isReal) {
      unawaited(
        lk.AudioManager.instance.setSpeakerOutputPreferred(isSpeakerOn),
      );
    }
    _telemetry.recordInteraction(
      'call_speaker_toggled',
      attributes: _sessionTelemetryAttributes(
        _currentSession!,
        extra: <String, Object?>{
          'enabled': isSpeakerOn,
        },
      ),
    );
    notifyListeners();
  }

  void toggleLocalVideo() {
    final session = _currentSession;
    if (session == null || !session.isVideo) {
      return;
    }

    final isLocalVideoEnabled = !session.isLocalVideoEnabled;
    _currentSession = session.copyWith(
      isLocalVideoEnabled: !session.isLocalVideoEnabled,
    );
    if (session.isReal) {
      unawaited(_setRealCamera(isLocalVideoEnabled));
    }
    _telemetry.recordInteraction(
      'call_video_toggled',
      attributes: _sessionTelemetryAttributes(
        _currentSession!,
        extra: <String, Object?>{
          'enabled': isLocalVideoEnabled,
        },
      ),
    );
    notifyListeners();
  }

  void switchCamera() {
    final session = _currentSession;
    if (session == null || !session.isVideo) {
      return;
    }

    final isFrontCamera = !session.isFrontCamera;
    _currentSession = session.copyWith(isFrontCamera: isFrontCamera);
    if (session.isReal) {
      unawaited(
        _localVideoTrack?.setCameraPosition(
          isFrontCamera ? lk.CameraPosition.front : lk.CameraPosition.back,
        ),
      );
    }
    _telemetry.recordInteraction(
      'call_camera_switched',
      attributes: _sessionTelemetryAttributes(
        _currentSession!,
        extra: <String, Object?>{
          'camera_position': isFrontCamera ? 'front' : 'back',
        },
      ),
    );
    notifyListeners();
  }

  Future<bool> _ensurePermissions(CallType type) async {
    _telemetry.recordInteraction(
      'call_permissions_requested',
      attributes: <String, Object?>{
        'type': type.name,
      },
    );
    try {
      _permissions = await _permissionService.requestCallPermissions(type);
    } catch (error, stackTrace) {
      _errorMessage = 'We could not check call permissions right now.';
      _telemetry.recordError(
        error,
        stackTrace,
        source: 'call_permissions',
        fatal: false,
        attributes: <String, Object?>{
          'type': type.name,
        },
      );
      notifyListeners();
      return false;
    }

    final missingPermissions = _permissions.missingFor(type);
    if (missingPermissions.isEmpty) {
      _errorMessage = null;
      _telemetry.recordInteraction(
        'call_permissions_granted',
        attributes: <String, Object?>{
          'type': type.name,
          ..._permissionTelemetryAttributes(_permissions),
        },
      );
      notifyListeners();
      return true;
    }

    _errorMessage = _permissionDeniedMessage(
      type: type,
      permissions: missingPermissions,
    );
    _telemetry.recordInteraction(
      'call_permissions_denied',
      attributes: <String, Object?>{
        'type': type.name,
        'missing_permissions':
            missingPermissions.map((permission) => permission.name).join(','),
        ..._permissionTelemetryAttributes(_permissions),
      },
    );
    notifyListeners();
    return false;
  }

  void _beginOutgoingSession({
    required CallContact contact,
    required CallType type,
  }) {
    _cancelTimers();
    final session = CallSession(
      id: 'call-${_sessionSequence++}',
      contact: contact,
      type: type,
      direction: CallDirection.outgoing,
      phase: CallSessionPhase.ringing,
      createdAt: _now(),
      isSpeakerOn: type == CallType.video,
      isLocalVideoEnabled: type == CallType.video,
    );
    _currentSession = session;
    _errorMessage = null;
    notifyListeners();

    _schedulePhaseTimer(outgoingRingDuration, () {
      final current = _currentSession;
      if (current == null || current.id != session.id) {
        return;
      }
      _transitionToConnecting(session.id);
    });
  }

  void _transitionToConnecting(String sessionId) {
    _phaseTimer?.cancel();
    final session = _currentSession;
    if (session == null || session.id != sessionId) {
      return;
    }

    _currentSession = session.copyWith(phase: CallSessionPhase.connecting);
    notifyListeners();

    _schedulePhaseTimer(outgoingConnectingDuration, () {
      final current = _currentSession;
      if (current == null || current.id != sessionId) {
        return;
      }

      _currentSession = current.copyWith(
        phase: CallSessionPhase.connected,
        connectedAt: _now(),
        setConnectedAt: true,
      );
      _telemetry.recordInteraction(
        'call_connected',
        attributes: _sessionTelemetryAttributes(_currentSession!),
      );
      _startDurationTicker();
      notifyListeners();
    });
  }

  void _handleUidChanged(String? uid) {
    _incomingSignalSubscription?.cancel();
    _incomingSignalSubscription = null;
    final signaling = _signalingService;
    if (uid == null || signaling == null) {
      return;
    }
    _incomingSignalSubscription =
        signaling.watchIncomingCall(uid).listen(_handleIncomingSignal);
  }

  void _handleIncomingSignal(CallSignal? signal) {
    if (signal == null || _currentSession != null) {
      // Either nothing ringing, or we're already on a call -- a real
      // product would auto-decline or queue a second incoming call;
      // out of scope here.
      return;
    }

    _cancelTimers();
    _errorMessage = null;
    // We only know the caller's uid at this point -- no contact-name
    // resolution against device contacts/Firestore yet, so the incoming
    // call surfaces with a placeholder identity. A known, documented gap.
    final contact = CallContact(
      id: signal.callerUid,
      name: 'Caller ${signal.callerUid.substring(0, 4)}',
      avatarLabel: signal.callerUid.substring(0, 2).toUpperCase(),
      accentColor: Colors.teal,
      uid: signal.callerUid,
    );
    final session = CallSession(
      id: 'call-${_sessionSequence++}',
      contact: contact,
      type: signal.type,
      direction: CallDirection.incoming,
      phase: CallSessionPhase.incoming,
      createdAt: _now(),
      isSpeakerOn: signal.type == CallType.video,
      isLocalVideoEnabled: signal.type == CallType.video,
      callId: signal.id,
    );
    _currentSession = session;
    _telemetry.recordInteraction(
      'call_incoming_real',
      attributes: _sessionTelemetryAttributes(session),
    );
    notifyListeners();
    _watchActiveSignal(signal.id);
  }

  void _watchActiveSignal(String callId) {
    _activeSignalSubscription?.cancel();
    _activeSignalSubscription =
        _signalingService!.watchCall(callId).listen(_handleSignalUpdate);
  }

  Future<void> _handleSignalUpdate(CallSignal? signal) async {
    final session = _currentSession;
    if (session == null || signal == null || signal.id != session.callId) {
      return;
    }

    switch (signal.status) {
      case CallSignalStatus.ringing:
        return;
      case CallSignalStatus.accepted:
        if (session.phase == CallSessionPhase.connecting ||
            session.phase == CallSessionPhase.connected) {
          return;
        }
        await _joinLiveKitRoomAndConnect(session, signal.roomName);
        return;
      case CallSignalStatus.declined:
        await _finishSession(status: CallHistoryStatus.declined);
        return;
      case CallSignalStatus.ended:
        final status = session.phase == CallSessionPhase.connected
            ? CallHistoryStatus.completed
            : (session.direction == CallDirection.outgoing
                ? CallHistoryStatus.canceled
                : CallHistoryStatus.missed);
        await _finishSession(status: status);
        return;
    }
  }

  Future<void> _joinLiveKitRoomAndConnect(
    CallSession session,
    String roomName,
  ) async {
    _currentSession = session.copyWith(phase: CallSessionPhase.connecting);
    notifyListeners();

    final tokenService = _tokenService;
    final liveKitUrl = _liveKitUrl;
    if (tokenService == null || liveKitUrl == null) {
      _errorMessage = 'Calling is not fully configured on this build.';
      _telemetry.recordError(
        StateError('Missing LiveKit token service or URL'),
        StackTrace.current,
        source: 'call_livekit_connect',
        fatal: false,
      );
      notifyListeners();
      await _finishSession(status: CallHistoryStatus.failed);
      return;
    }

    try {
      final token = await tokenService.fetchToken(roomName);
      final room = lk.Room();
      await room.connect(liveKitUrl, token);

      final roomListener = room.createListener();
      roomListener.on<lk.TrackSubscribedEvent>((event) {
        if (event.track is lk.VideoTrack) {
          _remoteVideoTrack = event.track as lk.VideoTrack;
          notifyListeners();
        }
      });

      lk.LocalTrackPublication? cameraPub;
      if (session.isVideo) {
        try {
          cameraPub = await room.localParticipant?.setCameraEnabled(true);
        } catch (_) {
          // Camera unavailable (e.g. iOS Simulator has no real
          // AVCaptureDevice) -- non-fatal, mirrors LiveKitTestScreen.
        }
      }
      await room.localParticipant?.setMicrophoneEnabled(true);

      final current = _currentSession;
      if (current == null || current.id != session.id) {
        // Session was ended locally while we were still connecting.
        await roomListener.dispose();
        await room.disconnect();
        await room.dispose();
        return;
      }

      _room = room;
      _roomListener = roomListener;
      _localVideoTrack = cameraPub?.track as lk.LocalVideoTrack?;
      _currentSession = current.copyWith(
        phase: CallSessionPhase.connected,
        connectedAt: _now(),
        setConnectedAt: true,
      );
      _telemetry.recordInteraction(
        'call_connected',
        attributes: _sessionTelemetryAttributes(_currentSession!),
      );
      _startDurationTicker();
      notifyListeners();
    } catch (error, stackTrace) {
      _errorMessage = 'We could not connect that call.';
      _telemetry.recordError(
        error,
        stackTrace,
        source: 'call_livekit_connect',
        fatal: false,
      );
      notifyListeners();
      await _finishSession(status: CallHistoryStatus.failed);
    }
  }

  Future<void> _setRealCamera(bool enabled) async {
    try {
      final pub = await _room?.localParticipant?.setCameraEnabled(enabled);
      _localVideoTrack = enabled ? pub?.track as lk.LocalVideoTrack? : null;
      notifyListeners();
    } catch (_) {
      // Camera unavailable (e.g. iOS Simulator) -- non-fatal.
    }
  }

  Future<void> _teardownRealCallResources() async {
    await _activeSignalSubscription?.cancel();
    _activeSignalSubscription = null;
    final room = _room;
    final roomListener = _roomListener;
    _room = null;
    _roomListener = null;
    _localVideoTrack = null;
    _remoteVideoTrack = null;
    await roomListener?.dispose();
    await room?.disconnect();
    await room?.dispose();
  }

  Future<void> _finishSession({
    required CallHistoryStatus status,
  }) async {
    final session = _currentSession;
    if (session == null) {
      return;
    }

    final finishedAt = _now();
    final historyEntry = CallHistoryEntry(
      id: '${session.id}-${finishedAt.microsecondsSinceEpoch}',
      contactId: session.contact.id,
      name: session.contact.name,
      avatarLabel: session.contact.avatarLabel,
      accentColor: session.contact.accentColor,
      startedAt: session.connectedAt ?? session.createdAt,
      type: session.type,
      direction: session.direction,
      status: status,
      durationSeconds: session.phase == CallSessionPhase.connected
          ? session.elapsedSeconds(finishedAt)
          : 0,
      isGroup: session.contact.isGroup,
    );
    final durationSeconds = historyEntry.durationSeconds;

    _history = List<CallHistoryEntry>.unmodifiable([
      historyEntry,
      ..._history,
    ]);
    _currentSession = null;
    _cancelTimers();
    unawaited(_teardownRealCallResources());
    _telemetry.recordInteraction(
      'call_session_finished',
      attributes: _sessionTelemetryAttributes(
        session,
        extra: <String, Object?>{
          'status': status.name,
          'duration_seconds': durationSeconds,
        },
      ),
    );
    notifyListeners();

    try {
      _history = await _repository.saveHistoryEntry(historyEntry);
    } on CallsRepositoryException catch (error, stackTrace) {
      _errorMessage = error.message;
      _telemetry.recordError(
        error,
        stackTrace,
        source: 'call_history_save',
        fatal: false,
        attributes: <String, Object?>{
          'status': status.name,
          'contact_id': session.contact.id,
          'type': session.type.name,
        },
      );
    } catch (error, stackTrace) {
      _errorMessage = 'We could not update recent calls right now.';
      _telemetry.recordError(
        error,
        stackTrace,
        source: 'call_history_save',
        fatal: false,
        attributes: <String, Object?>{
          'status': status.name,
          'contact_id': session.contact.id,
          'type': session.type.name,
        },
      );
    }

    notifyListeners();
  }

  Map<String, Object?> _callAttributes({
    CallContact? contact,
    CallType? type,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    return <String, Object?>{
      if (type != null) 'type': type.name,
      if (contact != null) 'contact_id': contact.id,
      ...extra,
    };
  }

  Map<String, Object?> _sessionTelemetryAttributes(
    CallSession session, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    return _callAttributes(
      contact: session.contact,
      type: session.type,
      extra: <String, Object?>{
        'session_id': session.id,
        'direction': session.direction.name,
        'phase': session.phase.name,
        ...extra,
      },
    );
  }

  Map<String, Object?> _permissionTelemetryAttributes(
    CallPermissions permissions,
  ) {
    return <String, Object?>{
      'microphone': permissions.microphone.name,
      'camera': permissions.camera.name,
    };
  }

  void _schedulePhaseTimer(Duration duration, VoidCallback action) {
    _phaseTimer?.cancel();
    if (duration == Duration.zero) {
      action();
      return;
    }

    _phaseTimer = Timer(duration, action);
  }

  void _startDurationTicker() {
    _durationTicker?.cancel();
    if (durationTickInterval == Duration.zero) {
      return;
    }

    _durationTicker = Timer.periodic(durationTickInterval, (_) {
      final session = _currentSession;
      if (session == null || session.phase != CallSessionPhase.connected) {
        _durationTicker?.cancel();
        _durationTicker = null;
        return;
      }
      notifyListeners();
    });
  }

  void _cancelTimers() {
    _phaseTimer?.cancel();
    _phaseTimer = null;
    _durationTicker?.cancel();
    _durationTicker = null;
  }

  String _permissionDeniedMessage({
    required CallType type,
    required List<CallPermission> permissions,
  }) {
    final labels = permissions
        .map((permission) => permission.label.toLowerCase())
        .toList();
    if (labels.length == 1) {
      return '${permissions.first.label} access is required for ${type.label.toLowerCase()} calls.';
    }
    return '${labels.first[0].toUpperCase()}${labels.first.substring(1)} and ${labels.last} access are required for ${type.label.toLowerCase()} calls.';
  }

  @override
  void dispose() {
    _cancelTimers();
    _authUidSubscription?.cancel();
    _incomingSignalSubscription?.cancel();
    unawaited(_teardownRealCallResources());
    super.dispose();
  }
}
