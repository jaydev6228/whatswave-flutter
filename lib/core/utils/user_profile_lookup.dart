import 'package:cloud_firestore/cloud_firestore.dart';

/// A user's publicly-published identity, read from `userProfiles/{uid}` --
/// the one place FirebaseAuthRepository keeps a user's current name/avatar/
/// color fresh on every sign-in (see FirebaseAuthRepository._registerUserProfile).
///
/// Every feature that shows "whose is this" (a chat thread, a call, a
/// story, a community contact) should prefer this over trusting a name
/// snapshot it captured once and never revisited -- otherwise a user who
/// renames themselves in WhatsWave keeps showing their old name everywhere
/// that snapshotted it, until whatever wrote the snapshot happens to write
/// it again.
class UserProfileLookup {
  const UserProfileLookup({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  /// Returns null if [uid] has no published profile yet (e.g. they haven't
  /// signed in since this registry existed) or the read fails for any
  /// reason -- callers should fall back to whatever locally-known identity
  /// they already have rather than treat this as fatal.
  Future<UserProfileSnapshot?> fetch(String uid) async {
    try {
      final doc = await _firestore.collection('userProfiles').doc(uid).get();
      final data = doc.data();
      final name = data?['name'] as String?;
      if (name == null || name.isEmpty) {
        return null;
      }
      return UserProfileSnapshot(
        name: name,
        avatarLabel: data?['avatarLabel'] as String?,
        accentColorArgb: data?['accentColorArgb'] as int?,
      );
    } on FirebaseException {
      return null;
    }
  }
}

class UserProfileSnapshot {
  const UserProfileSnapshot({
    required this.name,
    this.avatarLabel,
    this.accentColorArgb,
  });

  final String name;
  final String? avatarLabel;
  final int? accentColorArgb;
}
