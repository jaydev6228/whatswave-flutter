import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/app_user.dart';
import 'auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    AppUser? restoredUser,
    Map<String, AppUser>? knownUsers,
    this.latency = const Duration(milliseconds: 450),
    this.persistSession = false,
  })  : _currentUser = restoredUser,
        _knownUsers = <String, AppUser>{...?(knownUsers)} {
    if (restoredUser != null) {
      _knownUsers[restoredUser.phoneNumber] = restoredUser;
    }
  }

  static const _persistedCurrentUserKey = 'demo_auth_current_user_v1';
  static const _persistedKnownUsersKey = 'demo_auth_known_users_v1';

  final Duration latency;
  final bool persistSession;
  final Map<String, AppUser> _knownUsers;
  final Set<String> _requestedPhones = <String>{};
  AppUser? _currentUser;
  SharedPreferences? _preferences;
  bool _didHydratePersistedState = false;

  Future<void> _wait() => Future<void>.delayed(latency);

  @override
  Future<AppUser?> restoreSession() async {
    await _hydratePersistedState();
    await _wait();
    await _persistCurrentState();
    return _currentUser;
  }

  @override
  Future<void> requestOtp(String phoneNumber) async {
    await _hydratePersistedState();
    await _wait();

    if (phoneNumber.endsWith('0000')) {
      throw const AuthException(
        'We could not send a code to that number right now. Try again in a moment.',
      );
    }

    _requestedPhones.add(phoneNumber);
  }

  @override
  Future<AuthVerificationResult> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    await _hydratePersistedState();
    await _wait();

    if (!_requestedPhones.contains(phoneNumber)) {
      throw const AuthException(
        'Request a fresh code before entering it here.',
      );
    }

    if (code != '123456') {
      throw const AuthException(
        'That code looks wrong. Enter the 6-digit code we sent to continue.',
      );
    }

    final existingUser = _knownUsers[phoneNumber];
    if (existingUser != null) {
      _currentUser = existingUser;
      await _persistCurrentState();
      return AuthVerificationResult.authenticated(existingUser);
    }

    return const AuthVerificationResult.profileRequired();
  }

  @override
  Future<AppUser> completeProfile({
    required String phoneNumber,
    required String name,
    required String about,
  }) async {
    await _hydratePersistedState();
    await _wait();

    final trimmedName = name.trim();
    if (trimmedName.toLowerCase() == 'error') {
      throw const AuthException(
        'We could not finish setting up your profile. Please try again.',
      );
    }

    final user = AppUser(
      name: trimmedName,
      phoneNumber: phoneNumber,
      about: about.trim(),
      avatarLabel: _avatarLabelForName(trimmedName),
      accentColor: _accentColorForName(trimmedName),
    );
    _knownUsers[phoneNumber] = user;
    _currentUser = user;
    await _persistCurrentState();
    return user;
  }

  @override
  Future<AppUser> updateCurrentProfile({
    required String name,
    required String about,
  }) async {
    await _hydratePersistedState();
    await _wait();

    final currentUser = _currentUser;
    if (currentUser == null) {
      throw const AuthException(
        'Sign in again before editing your profile.',
      );
    }

    final trimmedName = name.trim();
    if (trimmedName.toLowerCase() == 'error') {
      throw const AuthException(
        'We could not save your profile changes. Please try again.',
      );
    }

    final updatedUser = currentUser.copyWith(
      name: trimmedName,
      about: about.trim(),
      avatarLabel: _avatarLabelForName(trimmedName),
      accentColor: _accentColorForName(trimmedName),
    );
    _currentUser = updatedUser;
    _knownUsers[updatedUser.phoneNumber] = updatedUser;
    await _persistCurrentState();
    return updatedUser;
  }

  @override
  Future<void> signOut() async {
    await _hydratePersistedState();
    await _wait();

    _currentUser = null;
    await _persistCurrentState();
  }

  Future<void> _hydratePersistedState() async {
    if (!persistSession || _didHydratePersistedState) {
      return;
    }

    _didHydratePersistedState = true;
    final preferences = await _preferencesInstance;
    final persistedKnownUsers =
        preferences.getStringList(_persistedKnownUsersKey) ?? const <String>[];
    for (final encodedUser in persistedKnownUsers) {
      final user = _decodeUser(encodedUser);
      if (user != null) {
        _knownUsers[user.phoneNumber] = user;
      }
    }

    final restoredUser =
        _decodeUser(preferences.getString(_persistedCurrentUserKey));
    if (restoredUser != null) {
      _currentUser = restoredUser;
      _knownUsers[restoredUser.phoneNumber] = restoredUser;
    }
  }

  Future<void> _persistCurrentState() async {
    if (!persistSession) {
      return;
    }

    final preferences = await _preferencesInstance;
    if (_currentUser == null) {
      await preferences.remove(_persistedCurrentUserKey);
    } else {
      await preferences.setString(
        _persistedCurrentUserKey,
        _encodeUser(_currentUser!),
      );
    }
    await preferences.setStringList(
      _persistedKnownUsersKey,
      _knownUsers.values.map(_encodeUser).toList(growable: false),
    );
  }

  Future<SharedPreferences> get _preferencesInstance async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  String _encodeUser(AppUser user) {
    return jsonEncode(<String, Object>{
      'name': user.name,
      'phoneNumber': user.phoneNumber,
      'about': user.about,
      'avatarLabel': user.avatarLabel,
      'accentColor': user.accentColor.toARGB32(),
    });
  }

  AppUser? _decodeUser(String? serialized) {
    if (serialized == null || serialized.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(serialized);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final name = decoded['name'];
      final phoneNumber = decoded['phoneNumber'];
      final about = decoded['about'];
      final avatarLabel = decoded['avatarLabel'];
      final accentColorValue = decoded['accentColor'];
      if (name is! String ||
          phoneNumber is! String ||
          about is! String ||
          avatarLabel is! String) {
        return null;
      }

      final colorValue = switch (accentColorValue) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value),
        _ => null,
      };
      if (colorValue == null) {
        return null;
      }

      return AppUser(
        name: name,
        phoneNumber: phoneNumber,
        about: about,
        avatarLabel: avatarLabel,
        accentColor: Color(colorValue),
      );
    } catch (_) {
      return null;
    }
  }

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
