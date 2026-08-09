import 'dart:io';

import '../../../core/models/app_user.dart';

abstract class AuthRepository {
  Future<AppUser?> restoreSession();

  Future<void> requestOtp(String phoneNumber);

  Future<AuthVerificationResult> verifyOtp({
    required String phoneNumber,
    required String code,
  });

  Future<AppUser> completeProfile({
    required String phoneNumber,
    required String name,
    required String about,
  });

  Future<AppUser> updateCurrentProfile({
    required String name,
    required String about,
  });

  /// Uploads [photo] as the caller's profile photo and returns the updated
  /// [AppUser] with [AppUser.avatarUrl] pointing at it.
  Future<AppUser> updateAvatar(File photo);

  Future<void> signOut();
}

class AuthVerificationResult {
  const AuthVerificationResult._({this.user});

  const AuthVerificationResult.authenticated(AppUser user) : this._(user: user);

  const AuthVerificationResult.profileRequired() : this._();

  final AppUser? user;

  bool get needsProfile => user == null;
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
