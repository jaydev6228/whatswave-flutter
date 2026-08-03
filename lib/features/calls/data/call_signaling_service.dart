import 'dart:async';

import '../domain/call_history_entry.dart';
import '../domain/call_signal.dart';

/// Cross-device call signaling: lets one device notify another that a call
/// is happening, and lets both sides observe/change its status. Separate
/// from [CallsRepository], which only persists call history.
abstract class CallSignalingService {
  Future<CallSignal> placeCall({
    required String calleeUid,
    required CallType type,
  });

  /// The most recent ringing call addressed to [myUid], or null. Used to
  /// surface an incoming-call UI on the callee's device.
  Stream<CallSignal?> watchIncomingCall(String myUid);

  /// Live updates for a specific call, e.g. so the caller sees when the
  /// callee accepts/declines.
  Stream<CallSignal?> watchCall(String callId);

  Future<void> updateStatus(String callId, CallSignalStatus status);
}

/// Local-only stand-in with no real cross-device delivery -- there's no
/// second device to signal in local mode. Exists purely to satisfy the
/// [CallSignalingService] seam for local/demo builds.
class MemoryCallSignalingService implements CallSignalingService {
  final Map<String, CallSignal> _calls = <String, CallSignal>{};
  final StreamController<CallSignal?> _incomingController =
      StreamController<CallSignal?>.broadcast();
  final Map<String, StreamController<CallSignal?>> _callControllers =
      <String, StreamController<CallSignal?>>{};
  int _sequence = 0;

  @override
  Future<CallSignal> placeCall({
    required String calleeUid,
    required CallType type,
  }) async {
    final now = DateTime.now();
    final id = 'local-call-${_sequence++}';
    final signal = CallSignal(
      id: id,
      callerUid: 'local-caller',
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
  Future<void> updateStatus(String callId, CallSignalStatus status) async {
    final existing = _calls[callId];
    if (existing == null) {
      return;
    }
    final updated = existing.copyWith(status: status, updatedAt: DateTime.now());
    _calls[callId] = updated;
    _callControllers[callId]?.add(updated);
  }
}
