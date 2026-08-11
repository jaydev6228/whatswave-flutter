import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/calls/domain/call_signal.dart';
import 'package:whatswave/features/calls/domain/group_call_participant.dart';

void main() {
  group('buildGroupCallParticipants', () {
    test('shows host and members with ringing, connected, and declined states',
        () {
      final participants = buildGroupCallParticipants(
        hostUid: 'host',
        memberUids: const <String>['ava', 'noah'],
        displayNames: const <String, String>{
          'host': 'Jay',
          'ava': 'Ava Patel',
          'noah': 'Noah Kim',
        },
        avatarUrls: const <String, String>{},
        inviteStatuses: const <String, CallSignalStatus>{
          'ava': CallSignalStatus.ringing,
          'noah': CallSignalStatus.declined,
        },
        connectedUids: const <String>{'ava'},
        viewerUid: 'host',
        hostConnectedInRoom: true,
      );

      expect(participants.length, 3);
      expect(
        participants.firstWhere((entry) => entry.uid == 'host').state,
        GroupCallParticipantState.connected,
      );
      expect(
        participants.firstWhere((entry) => entry.uid == 'ava').state,
        GroupCallParticipantState.connected,
      );
      expect(
        participants.firstWhere((entry) => entry.uid == 'noah').state,
        GroupCallParticipantState.declined,
      );
      expect(
        participants.firstWhere((entry) => entry.uid == 'host').displayName,
        'You',
      );
    });

    test('marks accepted-but-not-yet-in-room members as connecting', () {
      final participants = buildGroupCallParticipants(
        hostUid: 'host',
        memberUids: const <String>['ava'],
        displayNames: const <String, String>{'host': 'Jay', 'ava': 'Ava'},
        avatarUrls: const <String, String>{},
        inviteStatuses: const <String, CallSignalStatus>{
          'ava': CallSignalStatus.accepted,
        },
        connectedUids: const <String>{},
        viewerUid: 'ava',
        hostConnectedInRoom: true,
      );

      expect(
        participants.firstWhere((entry) => entry.uid == 'ava').state,
        GroupCallParticipantState.connecting,
      );
      expect(
        participants.firstWhere((entry) => entry.uid == 'ava').displayName,
        'You',
      );
    });

    test('derives avatar labels from display names instead of viewer labels',
        () {
      final participants = buildGroupCallParticipants(
        hostUid: 'host',
        memberUids: const <String>['ava'],
        displayNames: const <String, String>{
          'host': 'Jay Patel',
          'ava': 'Ava Patel',
        },
        avatarUrls: const <String, String>{
          'ava': 'https://example.com/ava.jpg',
        },
        inviteStatuses: const <String, CallSignalStatus>{
          'ava': CallSignalStatus.ringing,
        },
        connectedUids: const <String>{},
        viewerUid: 'host',
        hostConnectedInRoom: true,
      );

      expect(
        participants.firstWhere((entry) => entry.uid == 'host').avatarLabel,
        'JP',
      );
      expect(
        participants.firstWhere((entry) => entry.uid == 'ava').avatarLabel,
        'AP',
      );
      expect(
        participants.firstWhere((entry) => entry.uid == 'ava').avatarUrl,
        'https://example.com/ava.jpg',
      );
    });
  });

  group('groupCallParticipantStateLabel', () {
    test('returns user-facing status copy', () {
      expect(
        groupCallParticipantStateLabel(GroupCallParticipantState.ringing),
        'Ringing…',
      );
      expect(
        groupCallParticipantStateLabel(GroupCallParticipantState.connected),
        'In this call',
      );
    });
  });
}
