import 'community_hub.dart';

/// How a community-backed chat thread maps back to its parent community.
class CommunityThreadContext {
  const CommunityThreadContext({
    required this.community,
    required this.isAnnouncement,
  });

  final CommunityHub community;
  final bool isAnnouncement;
}
