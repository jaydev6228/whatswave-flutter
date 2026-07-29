import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/settings/domain/app_lock_timeout.dart';
import '../../features/settings/domain/privacy_audience.dart';

class AppPreferencesController extends ChangeNotifier {
  AppPreferencesController({
    SharedPreferences? preferences,
    DateTime Function()? nowProvider,
  })  : _preferences = preferences,
        _nowProvider = nowProvider ?? DateTime.now;

  static const _themeModeKey = 'app_preferences_theme_mode_v1';
  static const _notificationsEnabledKey =
      'app_preferences_notifications_enabled_v1';
  static const _readReceiptsEnabledKey =
      'app_preferences_read_receipts_enabled_v1';
  static const _appLockEnabledKey = 'app_preferences_app_lock_enabled_v1';
  static const _appLockTimeoutKey = 'app_preferences_app_lock_timeout_v1';
  static const _lastSeenAudienceKey = 'app_preferences_last_seen_audience_v1';
  static const _profilePhotoAudienceKey =
      'app_preferences_profile_photo_audience_v1';
  static const _statusAudienceKey = 'app_preferences_status_audience_v1';
  static const _groupsAudienceKey = 'app_preferences_groups_audience_v1';
  static const _securityNotificationsKey =
      'app_preferences_security_notifications_v1';

  final DateTime Function() _nowProvider;
  SharedPreferences? _preferences;

  ThemeMode _themeMode = ThemeMode.system;
  bool _notificationsEnabled = true;
  bool _readReceiptsEnabled = true;
  bool _appLockEnabled = false;
  AppLockTimeout _appLockTimeout = AppLockTimeout.immediately;
  PrivacyAudience _lastSeenAudience = PrivacyAudience.contacts;
  PrivacyAudience _profilePhotoAudience = PrivacyAudience.everyone;
  PrivacyAudience _statusAudience = PrivacyAudience.contacts;
  PrivacyAudience _groupsAudience = PrivacyAudience.contacts;
  bool _securityNotificationsEnabled = true;
  bool _hasLoaded = false;
  bool _isLoading = false;
  bool _isAppLocked = false;
  DateTime? _backgroundedAt;
  Future<void> _pendingPersistence = Future<void>.value();

  ThemeMode get themeMode => _themeMode;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get readReceiptsEnabled => _readReceiptsEnabled;
  bool get appLockEnabled => _appLockEnabled;
  AppLockTimeout get appLockTimeout => _appLockTimeout;
  PrivacyAudience get lastSeenAudience => _lastSeenAudience;
  PrivacyAudience get profilePhotoAudience => _profilePhotoAudience;
  PrivacyAudience get statusAudience => _statusAudience;
  PrivacyAudience get groupsAudience => _groupsAudience;
  bool get securityNotificationsEnabled => _securityNotificationsEnabled;
  bool get hasLoaded => _hasLoaded;
  bool get isLoading => _isLoading;
  bool get isAppLocked => _isAppLocked;

  Future<void> ensureLoaded() async {
    if (_hasLoaded || _isLoading) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final preferences = await _preferencesInstance;
      _themeMode = _themeModeFromStorage(
        preferences.getString(_themeModeKey),
      );
      _notificationsEnabled =
          preferences.getBool(_notificationsEnabledKey) ?? true;
      _readReceiptsEnabled =
          preferences.getBool(_readReceiptsEnabledKey) ?? true;
      _appLockEnabled = preferences.getBool(_appLockEnabledKey) ?? false;
      _appLockTimeout = AppLockTimeout.fromStorage(
        preferences.getString(_appLockTimeoutKey),
      );
      _lastSeenAudience = PrivacyAudience.fromStorage(
        preferences.getString(_lastSeenAudienceKey),
      );
      _profilePhotoAudience = PrivacyAudience.fromStorage(
        preferences.getString(_profilePhotoAudienceKey),
      );
      _statusAudience = PrivacyAudience.fromStorage(
        preferences.getString(_statusAudienceKey),
      );
      _groupsAudience = PrivacyAudience.fromStorage(
        preferences.getString(_groupsAudienceKey),
      );
      _securityNotificationsEnabled =
          preferences.getBool(_securityNotificationsKey) ?? true;
      _hasLoaded = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> waitForPendingPersistence() => _pendingPersistence;

  void setThemeMode(ThemeMode value) {
    if (_themeMode == value) {
      return;
    }

    _themeMode = value;
    notifyListeners();
    _queuePersistence();
  }

  void setNotificationsEnabled(bool value) {
    if (_notificationsEnabled == value) {
      return;
    }

    _notificationsEnabled = value;
    notifyListeners();
    _queuePersistence();
  }

  void setReadReceiptsEnabled(bool value) {
    if (_readReceiptsEnabled == value) {
      return;
    }

    _readReceiptsEnabled = value;
    notifyListeners();
    _queuePersistence();
  }

  void setAppLockEnabled(bool value) {
    if (_appLockEnabled == value) {
      return;
    }

    _appLockEnabled = value;
    if (!value) {
      _isAppLocked = false;
      _backgroundedAt = null;
    }
    notifyListeners();
    _queuePersistence();
  }

  void setAppLockTimeout(AppLockTimeout value) {
    if (_appLockTimeout == value) {
      return;
    }

    _appLockTimeout = value;
    notifyListeners();
    _queuePersistence();
  }

  void setLastSeenAudience(PrivacyAudience value) {
    if (_lastSeenAudience == value) {
      return;
    }

    _lastSeenAudience = value;
    notifyListeners();
    _queuePersistence();
  }

  void setProfilePhotoAudience(PrivacyAudience value) {
    if (_profilePhotoAudience == value) {
      return;
    }

    _profilePhotoAudience = value;
    notifyListeners();
    _queuePersistence();
  }

  void setStatusAudience(PrivacyAudience value) {
    if (_statusAudience == value) {
      return;
    }

    _statusAudience = value;
    notifyListeners();
    _queuePersistence();
  }

  void setGroupsAudience(PrivacyAudience value) {
    if (_groupsAudience == value) {
      return;
    }

    _groupsAudience = value;
    notifyListeners();
    _queuePersistence();
  }

  void setSecurityNotificationsEnabled(bool value) {
    if (_securityNotificationsEnabled == value) {
      return;
    }

    _securityNotificationsEnabled = value;
    notifyListeners();
    _queuePersistence();
  }

  void handleLifecycleChange(AppLifecycleState state) {
    if (!_appLockEnabled) {
      return;
    }

    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _backgroundedAt ??= _nowProvider();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      if (_backgroundedAt == null) {
        return;
      }

      final elapsed = _nowProvider().difference(_backgroundedAt!);
      _backgroundedAt = null;
      if (elapsed >= _appLockTimeout.duration) {
        _isAppLocked = true;
        notifyListeners();
      }
    }
  }

  void lockNow() {
    if (!_appLockEnabled || _isAppLocked) {
      return;
    }

    _isAppLocked = true;
    notifyListeners();
  }

  void unlockApp() {
    if (!_isAppLocked) {
      return;
    }

    _isAppLocked = false;
    _backgroundedAt = null;
    notifyListeners();
  }

  Future<SharedPreferences> get _preferencesInstance async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  void _queuePersistence() {
    _pendingPersistence = _pendingPersistence.then((_) => _persistState());
  }

  Future<void> _persistState() async {
    final preferences = await _preferencesInstance;
    await preferences.setString(_themeModeKey, _themeMode.name);
    await preferences.setBool(
      _notificationsEnabledKey,
      _notificationsEnabled,
    );
    await preferences.setBool(
      _readReceiptsEnabledKey,
      _readReceiptsEnabled,
    );
    await preferences.setBool(
      _appLockEnabledKey,
      _appLockEnabled,
    );
    await preferences.setString(
      _appLockTimeoutKey,
      _appLockTimeout.name,
    );
    await preferences.setString(
      _lastSeenAudienceKey,
      _lastSeenAudience.name,
    );
    await preferences.setString(
      _profilePhotoAudienceKey,
      _profilePhotoAudience.name,
    );
    await preferences.setString(
      _statusAudienceKey,
      _statusAudience.name,
    );
    await preferences.setString(
      _groupsAudienceKey,
      _groupsAudience.name,
    );
    await preferences.setBool(
      _securityNotificationsKey,
      _securityNotificationsEnabled,
    );
  }

  ThemeMode _themeModeFromStorage(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}
