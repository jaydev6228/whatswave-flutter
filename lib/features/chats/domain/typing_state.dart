/// One participant's ephemeral typing activity on a thread.
class TypingParticipantState {
  const TypingParticipantState({
    required this.displayName,
    required this.startedAt,
  });

  final String displayName;
  final DateTime startedAt;
}

/// Entries older than this are treated as stale and ignored client-side.
const Duration kTypingStaleAfter = Duration(seconds: 8);

bool isTypingEntryFresh(
  DateTime startedAt, {
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  return clock.difference(startedAt) <= kTypingStaleAfter;
}

List<TypingParticipantState> resolveActiveTypistsForViewer({
  required String viewerUid,
  Map<String, TypingParticipantState>? typingByUid,
  String? legacyTypingPreview,
  DateTime? now,
}) {
  if (typingByUid != null && typingByUid.isNotEmpty) {
    final active = typingByUid.entries
        .where((entry) => entry.key != viewerUid)
        .map((entry) => entry.value)
        .where((participant) => isTypingEntryFresh(participant.startedAt, now: now))
        .toList(growable: false)
      ..sort(
        (left, right) =>
            left.displayName.toLowerCase().compareTo(right.displayName.toLowerCase()),
      );
    return active;
  }

  final legacy = legacyTypingPreview?.trim() ?? '';
  if (legacy.isEmpty) {
    return const <TypingParticipantState>[];
  }

  return <TypingParticipantState>[
    TypingParticipantState(
      displayName: legacyTypingParticipantName(legacy),
      startedAt: now ?? DateTime.now(),
    ),
  ];
}

String legacyTypingParticipantName(String preview) {
  const suffixes = <String>[
    ' is typing…',
    ' is typing...',
    ' is typing',
  ];
  for (final suffix in suffixes) {
    if (preview.toLowerCase().endsWith(suffix.toLowerCase())) {
      return preview.substring(0, preview.length - suffix.length).trim();
    }
  }
  return preview;
}

String typingListLabel(
  List<TypingParticipantState> typists, {
  required bool isGroup,
}) {
  if (typists.isEmpty) {
    return '';
  }
  if (!isGroup) {
    return 'typing';
  }
  if (typists.length == 1) {
    return typists.first.displayName;
  }
  if (typists.length == 2) {
    return '${typists.first.displayName} and ${typists.last.displayName}';
  }
  return 'Several people';
}

String conversationTypingLine(
  List<TypingParticipantState> typists, {
  required bool isGroup,
}) {
  if (typists.isEmpty) {
    return '';
  }
  if (!isGroup) {
    return 'typing…';
  }
  if (typists.length == 1) {
    return '${typists.first.displayName} is typing…';
  }
  if (typists.length == 2) {
    return '${typists.first.displayName} and ${typists.last.displayName} are typing…';
  }
  return 'Several people are typing…';
}
