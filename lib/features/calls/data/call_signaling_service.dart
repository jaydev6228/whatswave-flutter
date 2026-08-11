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

  /// Starts a group call inviting every uid in [participantUids] (host
  /// excluded). Each invitee watches via [watchIncomingCall].
  Future<CallSignal> placeGroupCall({
    required String threadId,
    required String threadName,
    required List<String> participantUids,
    required CallType type,
    Map<String, String>? participantDisplayNames,
    Map<String, String>? participantAvatarUrls,
  });

  /// The most recent ringing call addressed to [myUid], or null. Matches
  /// both 1:1 ([CallSignal.calleeUid]) and group
  /// ([CallSignal.participantUids]) invites.
  Stream<CallSignal?> watchIncomingCall(String myUid);

  Stream<CallSignal?> watchCall(String callId);

  /// Live map of each invited member's call-doc status for a group host.
  Stream<Map<String, CallSignalStatus>> watchGroupInviteStatuses({
    required String roomName,
    required List<String> participantUids,
  });

  Future<void> updateStatus(String callId, CallSignalStatus status);

  Future<void> markCalleeRinging(String callId);
}

/// Local-only stand-in with no real cross-device delivery.
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
  Future<CallSignal> placeGroupCall({
    required String threadId,
    required String threadName,
    required List<String> participantUids,
    required CallType type,
    Map<String, String>? participantDisplayNames,
    Map<String, String>? participantAvatarUrls,
  }) async {
    final now = DateTime.now();
    final id = 'local-group-call-${_sequence++}';
    final signal = CallSignal(
      id: id,
      callerUid: 'local-caller',
      calleeUid: '',
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
    final controller =
        StreamController<Map<String, CallSignalStatus>>.broadcast();
    return controller.stream;
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
}
