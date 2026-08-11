import 'call_signal.dart';

/// WhatsApp-style group host continuation: the host stays in the call while
/// anyone is still connected in the media room, still ringing, or has
/// accepted but not finished joining. Once alone with no pending invites,
/// the host should end the call locally.
bool shouldEndLonelyGroupHostCall({
  required int remoteParticipantCount,
  required Iterable<CallSignalStatus> inviteStatuses,
}) {
  if (remoteParticipantCount > 0) {
    return false;
  }
  for (final status in inviteStatuses) {
    if (status == CallSignalStatus.ringing ||
        status == CallSignalStatus.accepted) {
      return false;
    }
  }
  return true;
}
