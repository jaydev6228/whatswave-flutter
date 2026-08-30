import '../../../core/utils/phone_number_matching.dart';
import '../../communities/domain/community_contact.dart';

/// Returns WhatsWave contacts matching [rawQuery] by display name, phone
/// number, or published username (with or without a leading "@").
List<CommunityContact> searchWhatsWaveContacts(
  List<CommunityContact> contacts,
  String rawQuery,
) {
  final query = rawQuery.trim();
  if (query.isEmpty) {
    return const <CommunityContact>[];
  }

  final matches = contacts
      .where((contact) => _contactMatchesWhatsWaveSearch(contact, query))
      .toList(growable: false)
    ..sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  return matches;
}

bool _contactMatchesWhatsWaveSearch(
  CommunityContact contact,
  String rawQuery,
) {
  if (!contact.isOnWhatsWave) {
    return false;
  }

  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) {
    return false;
  }

  if (contact.name.toLowerCase().contains(query)) {
    return true;
  }

  if (contact.phoneNumber.toLowerCase().contains(query)) {
    return true;
  }

  final digits = query.replaceAll(RegExp(r'\D'), '');
  if (digits.isNotEmpty) {
    final contactDigits = contact.phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (contactDigits.contains(digits)) {
      return true;
    }
    final key = phoneMatchKey(contact.phoneNumber);
    if (key.contains(digits)) {
      return true;
    }
  }

  final usernameQuery = query.startsWith('@') ? query.substring(1) : query;
  final username = contact.username?.toLowerCase();
  if (username != null &&
      username.isNotEmpty &&
      username.contains(usernameQuery)) {
    return true;
  }

  return false;
}
