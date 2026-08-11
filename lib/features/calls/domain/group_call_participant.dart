import 'call_signal.dart';

enum GroupCallParticipantState {
  connected,
  connecting,
  ringing,
  declined,
  unavailable,
}

class GroupCallParticipantView {
  const GroupCallParticipantView({
    required this.uid,
    required this.displayName,
    required this.avatarLabel,
    required this.state,
    required this.isSelf,
    required this.isHost,
    this.avatarUrl,
  });

  final String uid;
  final String displayName;
  final String avatarLabel;
  final GroupCallParticipantState state;
  final bool isSelf;
  final bool isHost;
  final String? avatarUrl;
}

GroupCallParticipantState groupCallParticipantStateForInvite({
  required CallSignalStatus inviteStatus,
  required bool isConnectedInRoom,
}) {
  if (isConnectedInRoom) {
    return GroupCallParticipantState.connected;
  }
  return switch (inviteStatus) {
    CallSignalStatus.ringing => GroupCallParticipantState.ringing,
    CallSignalStatus.accepted => GroupCallParticipantState.connecting,
    CallSignalStatus.declined => GroupCallParticipantState.declined,
    CallSignalStatus.ended => GroupCallParticipantState.unavailable,
    CallSignalStatus.active => GroupCallParticipantState.unavailable,
  };
}

String groupCallParticipantStateLabel(GroupCallParticipantState state) {
  return switch (state) {
    GroupCallParticipantState.connected => 'In this call',
    GroupCallParticipantState.connecting => 'Connecting…',
    GroupCallParticipantState.ringing => 'Ringing…',
    GroupCallParticipantState.declined => 'Declined',
    GroupCallParticipantState.unavailable => 'Unavailable',
  };
}

List<GroupCallParticipantView> buildGroupCallParticipants({
  required String hostUid,
  required List<String> memberUids,
  required Map<String, String> displayNames,
  required Map<String, String> avatarUrls,
  required Map<String, CallSignalStatus> inviteStatuses,
  required Set<String> connectedUids,
  required String? viewerUid,
  required bool hostConnectedInRoom,
}) {
  final orderedUids = <String>[hostUid, ...memberUids.where((uid) => uid != hostUid)];

  int rank(GroupCallParticipantState state) {
    return switch (state) {
      GroupCallParticipantState.connected => 0,
      GroupCallParticipantState.connecting => 1,
      GroupCallParticipantState.ringing => 2,
      GroupCallParticipantState.declined => 3,
      GroupCallParticipantState.unavailable => 4,
    };
  }

  String nameFor(String uid, {required bool isHost}) {
    if (viewerUid != null && uid == viewerUid) {
      return 'You';
    }
    final resolved = displayNames[uid]?.trim();
    if (resolved != null && resolved.isNotEmpty) {
      return resolved;
    }
    if (isHost) {
      return 'Group host';
    }
    return 'Member ${uid.substring(0, uid.length >= 4 ? 4 : uid.length)}';
  }

  String initialsFromDisplayName(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0])
        .take(2)
        .join();
    final clean = parts.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (clean.isEmpty) {
      return 'WW';
    }
    return clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
  }

  String avatarLabelFor(String uid, {required bool isHost}) {
    final resolved = displayNames[uid]?.trim();
    if (resolved != null && resolved.isNotEmpty) {
      return initialsFromDisplayName(resolved);
    }
    if (isHost) {
      return 'H';
    }
    if (uid.length >= 2) {
      return uid.substring(0, 2).toUpperCase();
    }
    return 'WW';
  }

  final views = orderedUids.map((uid) {
    final isHost = uid == hostUid;
    final isSelf = viewerUid != null && uid == viewerUid;
    final isConnectedInRoom =
        connectedUids.contains(uid) || (isHost && hostConnectedInRoom);
    final inviteStatus =
        inviteStatuses[uid] ?? CallSignalStatus.ringing;
    final state = isHost
        ? (isConnectedInRoom
            ? GroupCallParticipantState.connected
            : GroupCallParticipantState.connecting)
        : groupCallParticipantStateForInvite(
            inviteStatus: inviteStatus,
            isConnectedInRoom: isConnectedInRoom,
          );
    final displayName = nameFor(uid, isHost: isHost);
    return GroupCallParticipantView(
      uid: uid,
      displayName: displayName,
      avatarLabel: avatarLabelFor(uid, isHost: isHost),
      avatarUrl: avatarUrls[uid],
      state: state,
      isSelf: isSelf,
      isHost: isHost,
    );
  }).toList(growable: false);

  views.sort((a, b) {
    final rankCompare = rank(a.state).compareTo(rank(b.state));
    if (rankCompare != 0) {
      return rankCompare;
    }
    if (a.isHost != b.isHost) {
      return a.isHost ? -1 : 1;
    }
    return a.uid.compareTo(b.uid);
  });

  return views;
}
