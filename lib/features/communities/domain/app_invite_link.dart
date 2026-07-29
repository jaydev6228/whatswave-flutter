import 'community_contact.dart';

String buildCommunityAppInviteLink(CommunityContact contact) {
  final slug = contact.name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return 'https://join.whatswave.app/invite/$slug';
}
