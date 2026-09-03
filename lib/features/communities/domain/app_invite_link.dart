import 'community_contact.dart';
import 'community_hub.dart';

/// Cosmetic app-install link for someone not on WhatsWave yet.
String buildCommunityAppInviteLink(CommunityContact contact) {
  final slug = contact.name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return 'https://join.whatswave.app/invite/$slug';
}

/// Shareable link for joining a specific community. [inviteToken] is stored
/// on the community document and checked server-side when join-by-link lands.
String buildCommunityJoinLink(CommunityHub community) {
  final token = community.inviteToken?.trim();
  if (token == null || token.isEmpty) {
    return 'https://join.whatswave.app/community/${community.id}';
  }
  return 'https://join.whatswave.app/community/${community.id}?token=$token';
}
