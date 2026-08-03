import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/app_user.dart';
import '../../../core/utils/phone_number_matching.dart';
import 'auth_repository.dart';

/// Real Firebase Phone Auth implementation of [AuthRepository].
///
/// Firebase's User object only knows phoneNumber/displayName/uid — it has no
/// concept of our app's "about" field, so that's stored locally in
/// SharedPreferences keyed by uid until a Slice 3 Firestore adapter takes
/// over full profile storage.
///
/// Also registers the user's phone number in a `phoneDirectory` collection
/// on profile save, so [DeviceContactsService]-sourced contacts can be
/// matched against real registered accounts (see
/// FirestoreCommunitiesRepository).
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    fb_auth.FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final fb_auth.FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  static const _aboutKeyPrefix = 'firebase_auth_about_v1_';

  String? _verificationId;
  String? _pendingPhoneNumber;
  SharedPreferences? _preferences;

  @override
  Future<AppUser?> restoreSession() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return null;
    }
    return _appUserFromFirebaseUser(user);
  }

  @override
  Future<void> requestOtp(String phoneNumber) async {
    final completer = Completer<void>();
    _pendingPhoneNumber = phoneNumber;
    _verificationId = null;

    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (fb_auth.PhoneAuthCredential credential) {
        // Android same-device SIM auto-verification. We intentionally don't
        // auto sign-in here so the flow stays consistent with the app's
        // manual "enter the 6-digit code" UX.
      },
      verificationFailed: (fb_auth.FirebaseAuthException e) {
        if (!completer.isCompleted) {
          completer.completeError(AuthException(_messageFor(e)));
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );

    return completer.future;
  }

  @override
  Future<AuthVerificationResult> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    final verificationId = _verificationId;
    if (verificationId == null || _pendingPhoneNumber != phoneNumber) {
      throw const AuthException(
        'Request a fresh code before entering it here.',
      );
    }

    final credential = fb_auth.PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: code,
    );

    final fb_auth.UserCredential userCredential;
    try {
      userCredential = await _firebaseAuth.signInWithCredential(credential);
    } on fb_auth.FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    }

    final user = userCredential.user;
    if (user == null) {
      throw const AuthException(
        'That code looks wrong. Enter the 6-digit code we sent to continue.',
      );
    }

    final existingAbout = await _readAbout(user.uid);
    final hasCompletedProfile =
        existingAbout != null && (user.displayName ?? '').trim().isNotEmpty;

    if (!hasCompletedProfile) {
      return const AuthVerificationResult.profileRequired();
    }

    return AuthVerificationResult.authenticated(
      await _appUserFromFirebaseUser(user),
    );
  }

  @override
  Future<AppUser> completeProfile({
    required String phoneNumber,
    required String name,
    required String about,
  }) {
    return _saveProfile(name: name, about: about);
  }

  @override
  Future<AppUser> updateCurrentProfile({
    required String name,
    required String about,
  }) {
    return _saveProfile(name: name, about: about);
  }

  Future<AppUser> _saveProfile({
    required String name,
    required String about,
  }) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in again before editing your profile.');
    }

    final trimmedName = name.trim();
    await user.updateDisplayName(trimmedName);
    await _writeAbout(user.uid, about.trim());
    await _registerInPhoneDirectory(user.uid, user.phoneNumber);
    await _registerUserProfile(user.uid, trimmedName);
    await user.reload();

    return _appUserFromFirebaseUser(_firebaseAuth.currentUser ?? user);
  }

  /// Publishes this user's display name/avatar/color to a `userProfiles`
  /// document any other signed-in user can read -- e.g. so
  /// FirestoreChatRepository can show each side of a 1:1 chat the *other*
  /// person's real name, instead of whichever name got baked into the
  /// thread doc by whoever happened to create it. Best-effort, same
  /// reasoning as [_registerInPhoneDirectory].
  Future<void> _registerUserProfile(String uid, String name) async {
    if (name.isEmpty) {
      return;
    }
    try {
      await _firestore.collection('userProfiles').doc(uid).set({
        'name': name,
        'avatarLabel': _avatarLabelForName(name),
        'accentColorArgb': _accentColorForName(name).toARGB32(),
      });
    } on FirebaseException {
      // Best-effort -- see doc comment above.
    }
  }

  /// Registers this user's phone number so device contacts can be matched
  /// against real accounts. Best-effort: a failure here shouldn't block
  /// profile save, since the user is already signed in either way.
  Future<void> _registerInPhoneDirectory(String uid, String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.trim().isEmpty) {
      return;
    }
    final key = phoneMatchKey(phoneNumber);
    if (key.isEmpty) {
      return;
    }
    try {
      await _firestore.collection('phoneDirectory').doc(key).set({
        'uid': uid,
      });
    } on FirebaseException {
      // Best-effort -- see doc comment above.
    }
  }

  Future<AppUser> _appUserFromFirebaseUser(fb_auth.User user) async {
    final name = (user.displayName ?? '').trim();
    final about = await _readAbout(user.uid) ?? '';
    // Keeps userProfiles/{uid} fresh on every session, not just on profile
    // save -- otherwise an account that completed onboarding before this
    // collection existed (or hasn't touched Settings since) never gets a
    // userProfiles doc, and every OTHER user's chat thread with them falls
    // all the way back to the generic "WhatsWave user"/"?" placeholder.
    // Fire-and-forget: best-effort like the rest of this class, and it
    // shouldn't add a network round trip to every app launch/sign-in.
    unawaited(_registerUserProfile(user.uid, name));
    return AppUser(
      name: name,
      phoneNumber: user.phoneNumber ?? '',
      about: about,
      avatarLabel: _avatarLabelForName(name),
      accentColor: _accentColorForName(name),
    );
  }

  Future<SharedPreferences> get _preferencesInstance async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  Future<String?> _readAbout(String uid) async {
    final preferences = await _preferencesInstance;
    return preferences.getString('$_aboutKeyPrefix$uid');
  }

  Future<void> _writeAbout(String uid, String about) async {
    final preferences = await _preferencesInstance;
    await preferences.setString('$_aboutKeyPrefix$uid', about);
  }

  String _messageFor(fb_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-verification-code':
        return 'That code looks wrong. Enter the 6-digit code we sent to continue.';
      case 'invalid-phone-number':
        return 'That phone number looks invalid. Check the digits and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a moment before trying again.';
      case 'quota-exceeded':
        return "We hit today's SMS limit for this project. Try again tomorrow, or add billing in the Firebase console.";
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }

  // Same deterministic avatar/color derivation as FakeAuthRepository, so
  // real and demo users look visually consistent.
  String _avatarLabelForName(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'WW';
    }
    if (parts.length == 1) {
      final clean = parts.first.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      return clean.isEmpty
          ? 'WW'
          : clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Color _accentColorForName(String name) {
    const palette = <Color>[
      AppPalette.emerald,
      AppPalette.green,
      AppPalette.sky,
      AppPalette.purple,
      AppPalette.amber,
    ];
    final hash = name.codeUnits.fold<int>(0, (value, unit) => value + unit);
    return palette[hash % palette.length];
  }
}
