import 'communities_overview.dart';

abstract class CommunitiesRepository {
  Future<CommunitiesOverview> fetchOverview();

  Future<CommunitiesOverview> createCommunity({
    required String title,
    required String description,
  });

  Future<CommunitiesOverview> markCommunityOpened(String communityId);

  Future<CommunitiesOverview> inviteContactToCommunity({
    required String communityId,
    required String contactId,
  });

  Future<CommunitiesOverview> shareAppInvite(String contactId);
}

class CommunitiesRepositoryException implements Exception {
  const CommunitiesRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
