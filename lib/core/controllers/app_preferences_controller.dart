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
  static const _mediaAutoDownloadEnabledKey =
      'app_preferences_media_auto_download_enabled_v1';

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
  bool _mediaAutoDownloadEnabled = true;
  bool _hasLoaded = false;
  bool _isLoading = false;
  bool _isAppLocked = false;
  bool _isPrivacyCovered = false;
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
  bool get mediaAutoDownloadEnabled => _mediaAutoDownloadEnabled;
  bool get hasLoaded => _hasLoaded;
  bool get isLoading => _isLoading;
  bool get isAppLocked => _isAppLocked;

  /// Hide the app's content without demanding authentication.
  ///
  /// The OS screenshots the app as it leaves the foreground, and that
  /// screenshot is what the app switcher shows. Locking only on `resumed`
  /// -- which is what this used to do -- means the switcher happily
  /// displays the last open chat to anyone who picks the phone up, app lock
  /// on or not. Covering on the way out puts the cover in the snapshot.
  ///
  /// Deliberately separate from [isAppLocked]: a quick app-switch and back
  /// should not demand Face ID, it should just not leak the screen. Whether
  /// authentication is required on return is still the timeout's call.
  bool get isPrivacyCovered => _isPrivacyCovered;

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
      _mediaAutoDownloadEnabled =
          preferences.getBool(_mediaAutoDownloadEnabledKey) ?? true;
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
      _isPrivacyCovered = false;
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

  void setMediaAutoDownloadEnabled(bool value) {
    if (_mediaAutoDownloadEnabled == value) {
      return;
    }

    _mediaAutoDownloadEnabled = value;
    notifyListeners();
    _queuePersistence();
  }

  void handleLifecycleChange(AppLifecycleState state) {
    if (!_appLockEnabled) {
      return;
    }

    // `inactive` is the earliest warning that the app is leaving the
    // foreground -- it fires as the app switcher opens, before the snapshot
    // is taken -- but it also fires for transient interruptions like a
    // permission dialog or Control Centre. So it covers the screen without
    // starting the background clock.
    if (state == AppLifecycleState.inactive) {
      if (!_isPrivacyCovered) {
        _isPrivacyCovered = true;
        notifyListeners();
      }
      return;
    }

    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _backgroundedAt ??= _nowProvider();
      if (!_isPrivacyCovered) {
        _isPrivacyCovered = true;
        notifyListeners();
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      final wasCovered = _isPrivacyCovered;
      _isPrivacyCovered = false;

      if (backgroundedAt == null) {
        // Never actually backgrounded (a dialog, Control Centre): uncover,
        // but never demand authentication for that.
        if (wasCovered) {
          notifyListeners();
        }
        return;
      }

      _backgroundedAt = null;
      if (_nowProvider().difference(backgroundedAt) >=
          _appLockTimeout.duration) {
        _isAppLocked = true;
      }
      notifyListeners();
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
    _isPrivacyCovered = false;
    _backgroundedAt = null;
    notifyListeners();
  }

  /// Drops every preference back to its default, in memory.
  ///
  /// Pairs with [SessionDataCleaner], which wipes the backing store on
  /// sign-out. Without this the controller would still be holding the
  /// previous user's values and the next `_persistState()` would write them
  /// straight back out, undoing the wipe.
  ///
  /// Deliberately does not persist: leaving the store genuinely empty is the
  /// point, and every field below is already the value a fresh install
  /// starts from.
  void resetToDefaults() {
    _themeMode = ThemeMode.system;
    _notificationsEnabled = true;
    _readReceiptsEnabled = true;
    _appLockEnabled = false;
    _appLockTimeout = AppLockTimeout.immediately;
    _lastSeenAudience = PrivacyAudience.contacts;
    _profilePhotoAudience = PrivacyAudience.everyone;
    _statusAudience = PrivacyAudience.contacts;
    _groupsAudience = PrivacyAudience.contacts;
    _securityNotificationsEnabled = true;
    _mediaAutoDownloadEnabled = true;
    _isAppLocked = false;
    _isPrivacyCovered = false;
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
    await preferences.setBool(
      _mediaAutoDownloadEnabledKey,
      _mediaAutoDownloadEnabled,
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
