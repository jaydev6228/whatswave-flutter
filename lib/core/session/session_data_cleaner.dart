import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/updates/presentation/widgets/status_media_source.dart';
import '../crypto/crypto_box.dart';

/// Wipes everything this device still holds about the user who is signing out.
///
/// Before this existed, `signOut()` called `FirebaseAuth.signOut()` and
/// nothing else, so the next account signed in on the same device inherited
/// the previous user's **plaintext message history** (the uid-scoped
/// `chat_inbox_cache_v1` entry), their cached media bytes (the `flutter_cache_manager` store), their
/// "about" text, and every privacy/notification preference they had set.
///
/// Deliberately a blanket `SharedPreferences.clear()` rather than a list of
/// the ~20 keys the app writes across six files. Enumerating them is the
/// version that rots: a key added later is a leak nobody notices, and the
/// failure is silent. Everything in this store belongs to this app and none
/// of it should outlive the session -- except the theme, which is a device
/// preference rather than user data and is restored explicitly below so the
/// UI doesn't visibly flip on sign-out.
class SessionDataCleaner {
  const SessionDataCleaner({
    SharedPreferences? preferences,
    BaseCacheManager? mediaCacheManager,
    CryptoBox? cryptoBox,
  })  : _preferences = preferences,
        _mediaCacheManager = mediaCacheManager,
        _cryptoBox = cryptoBox;

  /// Mirrors `AppPreferencesController`'s own key. Duplicated rather than
  /// exported because this class must survive that one being refactored --
  /// if the names drift, the user merely loses their theme on sign-out,
  /// whereas a missed *data* key would be a leak.
  static const String _themeModeKey = 'app_preferences_theme_mode_v1';

  final SharedPreferences? _preferences;
  final BaseCacheManager? _mediaCacheManager;
  final CryptoBox? _cryptoBox;

  /// Must run **before** the auth repository's `signOut()`.
  ///
  /// The caches this clears are keyed by the signed-in uid, which
  /// `ChatInboxCache` and the about-cache read straight off
  /// `FirebaseAuth.instance.currentUser` at call time. After sign-out that
  /// is null, the keys no longer resolve, and the data is stranded on disk
  /// with no owner to clear it.
  Future<void> clearSignedInUserData() async {
    final preferences = _preferences ?? await SharedPreferences.getInstance();

    String? themeMode;
    try {
      themeMode = preferences.getString(_themeModeKey);
    } catch (_) {
      // A read failure here only costs the theme; never block the wipe.
    }

    await preferences.clear();

    if (themeMode != null) {
      await preferences.setString(_themeModeKey, themeMode);
    }

    // Photos, videos and voice notes this device downloaded, keyed by their
    // Storage URL. Plaintext today; still cleared once media is encrypted,
    // because a cache entry proves which objects this user fetched.
    try {
      await (_mediaCacheManager ?? statusMediaCacheManager).emptyCache();
    } catch (error) {
      // Best-effort: a cache that won't empty must not strand the user in a
      // half-signed-out state.
      debugPrint('Could not empty the media cache on sign-out: $error');
    }

    // Last, and the one that makes the rest conclusive. The Signal session
    // database, the local plaintext message store and the sealed inbox
    // cache are all encrypted under this single device key, and none of
    // them is erased row by row -- destroying the key makes every one of
    // them unreadable at once, even if a file survives deletion or is
    // recovered later.
    try {
      await (_cryptoBox ?? CryptoBox()).destroyLocalDataKey();
    } catch (error) {
      debugPrint('Could not destroy the device data key on sign-out: $error');
    }

    // Decrypted attachment copies are the one plaintext artefact the
    // encryption scheme deliberately writes to disk, so destroying the
    // device key does not make them unreadable. They have to be deleted.
    await clearDecryptedMediaCache();
  }
}
