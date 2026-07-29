import '../domain/community_contact.dart';
import '../domain/community_hub.dart';

class CommunitiesOverview {
  const CommunitiesOverview({
    required this.communities,
    required this.contacts,
  });

  final List<CommunityHub> communities;
  final List<CommunityContact> contacts;
}
