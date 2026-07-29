class CommunityGroupPreview {
  const CommunityGroupPreview({
    required this.id,
    required this.name,
    required this.summary,
    required this.memberCount,
    required this.lastActivityAt,
    this.unreadCount = 0,
  });

  final String id;
  final String name;
  final String summary;
  final int memberCount;
  final DateTime lastActivityAt;
  final int unreadCount;

  CommunityGroupPreview copyWith({
    String? id,
    String? name,
    String? summary,
    int? memberCount,
    DateTime? lastActivityAt,
    int? unreadCount,
  }) {
    return CommunityGroupPreview(
      id: id ?? this.id,
      name: name ?? this.name,
      summary: summary ?? this.summary,
      memberCount: memberCount ?? this.memberCount,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
