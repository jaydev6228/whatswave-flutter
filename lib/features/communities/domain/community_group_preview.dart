class CommunityGroupPreview {
  const CommunityGroupPreview({
    required this.id,
    required this.name,
    required this.summary,
    required this.memberCount,
    required this.lastActivityAt,
    this.unreadCount = 0,
    this.threadId,
  });

  final String id;
  final String name;
  final String summary;
  final int memberCount;
  final DateTime lastActivityAt;
  final int unreadCount;

  /// Id of the real [ChatThread] backing this group's messaging, once one
  /// has been created (see CommunitiesController's group-thread wiring) --
  /// null until then, since a group needs at least one real, on-WhatsWave
  /// member before a thread can be created.
  final String? threadId;

  CommunityGroupPreview copyWith({
    String? id,
    String? name,
    String? summary,
    int? memberCount,
    DateTime? lastActivityAt,
    int? unreadCount,
    String? threadId,
  }) {
    return CommunityGroupPreview(
      id: id ?? this.id,
      name: name ?? this.name,
      summary: summary ?? this.summary,
      memberCount: memberCount ?? this.memberCount,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      unreadCount: unreadCount ?? this.unreadCount,
      threadId: threadId ?? this.threadId,
    );
  }
}
