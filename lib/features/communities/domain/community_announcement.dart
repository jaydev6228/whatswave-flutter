class CommunityAnnouncement {
  const CommunityAnnouncement({
    required this.headline,
    required this.body,
    required this.publishedAt,
  });

  final String headline;
  final String body;
  final DateTime publishedAt;

  CommunityAnnouncement copyWith({
    String? headline,
    String? body,
    DateTime? publishedAt,
  }) {
    return CommunityAnnouncement(
      headline: headline ?? this.headline,
      body: body ?? this.body,
      publishedAt: publishedAt ?? this.publishedAt,
    );
  }
}
