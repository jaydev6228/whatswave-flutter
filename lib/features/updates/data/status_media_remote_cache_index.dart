import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which remote story-media URLs this device has written to disk.
///
/// [DefaultCacheManager] does not expose a cheap "list everything" API, and
/// in-memory diffing alone cannot evict orphans after a cold start -- the
/// previous session's URL set is gone once the app process dies. This index
/// is the lightweight ledger we reconcile against the live Firestore feed on
/// every launch and on every live update, so deleted/expired stories are
/// purged even when the owner removed them while our app was fully closed.
class StatusMediaRemoteCacheIndex {
  StatusMediaRemoteCacheIndex({SharedPreferences? preferences})
      : _injectedPreferences = preferences;

  static const String _storageKey = 'status_media_remote_cache_index_v1';

  final SharedPreferences? _injectedPreferences;
  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async {
    return _injectedPreferences ??
        (_preferences ??= await SharedPreferences.getInstance());
  }

  Future<Set<String>> readAll() async {
    final raw = (await _prefs).getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return <String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <String>{};
      }
      return decoded
          .whereType<String>()
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toSet();
    } on FormatException {
      return <String>{};
    }
  }

  Future<void> remember(String remoteUrl) async {
    final path = remoteUrl.trim();
    if (path.isEmpty) {
      return;
    }
    final entries = await readAll();
    if (entries.contains(path)) {
      return;
    }
    entries.add(path);
    await _write(entries);
  }

  Future<void> forget(String remoteUrl) async {
    final path = remoteUrl.trim();
    if (path.isEmpty) {
      return;
    }
    final entries = await readAll();
    if (!entries.remove(path)) {
      return;
    }
    await _write(entries);
  }

  /// Keeps only URLs still referenced by the live story feed.
  Future<void> retainOnly(Set<String> keepRemoteUrls) async {
    final keep = keepRemoteUrls.map((url) => url.trim()).toSet();
    final entries = await readAll();
    final removable = entries.difference(keep);
    if (removable.isEmpty) {
      return;
    }
    entries.removeAll(removable);
    await _write(entries);
  }

  Future<void> clear() async {
    await (await _prefs).remove(_storageKey);
  }

  Future<void> _write(Set<String> entries) async {
    await (await _prefs).setString(
      _storageKey,
      jsonEncode(entries.toList(growable: false)..sort()),
    );
  }
}

/// Records that [remoteUrl] was cached locally so it can be reconciled later.
Future<void> rememberRemoteStoryMediaCached(String remoteUrl) async {
  try {
    await StatusMediaRemoteCacheIndex().remember(remoteUrl);
  } catch (_) {
    // Best-effort only.
  }
}
