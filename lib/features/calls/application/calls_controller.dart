import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/observability/app_telemetry.dart';
import '../../../core/permissions/app_permission_service.dart';
import '../data/calls_repository.dart';
import '../domain/call_contact.dart';
import '../domain/call_history_entry.dart';
import '../domain/call_permissions.dart';
import '../domain/call_session.dart';

class CallsController extends ChangeNotifier {
  CallsController({
    required CallsRepository repository,
    AppPermissionService? permissionService,
    AppTelemetry? telemetry,
    DateTime Function()? now,
    this.outgoingRingDuration = const Duration(milliseconds: 900),
    this.outgoingConnectingDuration = const Duration(milliseconds: 700),
    this.incomingMissedAfter = const Duration(seconds: 18),
    this.durationTickInterval = const Duration(seconds: 1),
  })  : _repository = repository,
        _permissionService = permissionService ?? MemoryAppPermissionService(),
        _telemetry = telemetry ?? NoopAppTelemetry.instance,
        _now = now ?? DateTime.now;

  final CallsRepository _repository;
  final AppPermissionService _permissionService;
  final AppTelemetry _telemetry;
  final DateTime Function() _now;
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

  bool get hasLoaded => _hasLoaded;
  bool get isLoading => _isLoading;
  bool get isClearingHistory => _isClearingHistory;
  String? get errorMessage => _errorMessage;
  List<CallContact> get favorites => List<CallContact>.unmodifiable(_favorites);
  List<CallHistoryEntry> get history =>
      List<CallHistoryEntry>.unmodifiable(_history);
  CallPermissions get permissions => _permissions;
  CallSession? get currentSession => _currentSession;

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
    super.dispose();
  }
}
