import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/calls/domain/call_signal.dart';
import 'package:whatswave/features/calls/domain/group_call_continuation.dart';

void main() {
  group('shouldEndLonelyGroupHostCall', () {
    test('stays active while someone is still connected', () {
      expect(
        shouldEndLonelyGroupHostCall(
          remoteParticipantCount: 1,
          inviteStatuses: const <CallSignalStatus>[
            CallSignalStatus.ended,
            CallSignalStatus.ringing,
          ],
        ),
        isFalse,
      );
    });

    test('stays active while another member is still ringing', () {
      expect(
        shouldEndLonelyGroupHostCall(
          remoteParticipantCount: 0,
          inviteStatuses: const <CallSignalStatus>[
            CallSignalStatus.ended,
            CallSignalStatus.ringing,
          ],
        ),
        isFalse,
      );
    });

    test('stays active while someone accepted but has not joined yet', () {
      expect(
        shouldEndLonelyGroupHostCall(
          remoteParticipantCount: 0,
          inviteStatuses: const <CallSignalStatus>[
            CallSignalStatus.accepted,
            CallSignalStatus.ringing,
          ],
        ),
        isFalse,
      );
    });

    test('ends when alone and every invite is terminal', () {
      expect(
        shouldEndLonelyGroupHostCall(
          remoteParticipantCount: 0,
          inviteStatuses: const <CallSignalStatus>[
            CallSignalStatus.ended,
            CallSignalStatus.declined,
          ],
        ),
        isTrue,
      );
    });

    test('ends when nobody ever answered', () {
      expect(
        shouldEndLonelyGroupHostCall(
          remoteParticipantCount: 0,
          inviteStatuses: const <CallSignalStatus>[
            CallSignalStatus.declined,
            CallSignalStatus.declined,
          ],
        ),
        isTrue,
      );
    });
  });
}
