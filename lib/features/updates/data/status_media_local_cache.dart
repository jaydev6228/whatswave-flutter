import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers, per status segment, the device-local file the media was
/// captured from -- so the device that posted a status can render it
/// straight off disk instead of downloading its own upload back.
///
/// Posting repoints a segment's `localMediaPath` at the Firebase Storage
/// download URL, because that is the only path other devices can resolve.
/// That URL is then what comes back on the next snapshot, so without this
/// the poster re-fetches bytes it already has -- the spinner you see on your
/// own story seconds after posting.
///
/// Deliberately *not* part of [StatusStorySegment]'s JSON: a path under this
/// device's app container is meaningless (and mildly identifying) on anyone
/// else's phone, so it never goes near the shared document. It lives here,
/// keyed by segment id, and is reattached at read time.
///
/// Entries are pruned when their file disappears or their segment expires,
/// so this stays bounded by the handful of statuses live at once.
class StatusMediaLocalCache {
  StatusMediaLocalCache({SharedPreferences? preferences})
      : _injectedPreferences = preferences;

  static const String _storageKey = 'status_media_local_paths_v1';

  final SharedPreferences? _injectedPreferences;
  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async {
    return _injectedPreferences ??
        (_preferences ??= await SharedPreferences.getInstance());
  }

  Future<Map<String, String>> _read() async {
    final raw = (await _prefs).getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return <String, String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, String>{};
      }
      return <String, String>{
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } on FormatException {
      // Corrupt entry is not worth failing a status read over -- the only
      // cost of starting empty is one cold fetch.
      return <String, String>{};
    }
  }

  Future<void> _write(Map<String, String> entries) async {
    await (await _prefs).setString(_storageKey, jsonEncode(entries));
  }

  /// Associates [segmentId] with the on-device file it was posted from.
  Future<void> remember(String segmentId, String? localPath) async {
    final path = localPath?.trim();
    if (segmentId.isEmpty || path == null || path.isEmpty) {
      return;
    }
    // Only a real file is worth remembering; an asset or an https URL
    // already resolves fine without this.
    if (!File(path).existsSync()) {
      return;
    }
    final entries = await _read();
    entries[segmentId] = path;
    await _write(entries);
  }

  /// The remembered file for [segmentId], or null if there isn't one or it
  /// has since been deleted (by the OS clearing caches, or the user).
  Future<String?> pathFor(String segmentId) async {
    final path = (await _read())[segmentId];
    if (path == null) {
      return null;
    }
    if (!File(path).existsSync()) {
      await forget(<String>{segmentId});
      return null;
    }
    return path;
  }

  /// Same as [pathFor] for many ids at once, so reading a story costs one
  /// preferences read rather than one per segment.
  Future<Map<String, String>> pathsFor(Iterable<String> segmentIds) async {
    final wanted = segmentIds.toSet();
    if (wanted.isEmpty) {
      return const <String, String>{};
    }
    final entries = await _read();
    final resolved = <String, String>{};
    final stale = <String>{};
    for (final id in wanted) {
      final path = entries[id];
      if (path == null) {
        continue;
      }
      if (File(path).existsSync()) {
        resolved[id] = path;
      } else {
        stale.add(id);
      }
    }
    if (stale.isNotEmpty) {
      await forget(stale);
    }
    return resolved;
  }

  /// Drops entries for segments that are gone (expired or deleted).
  Future<void> forget(Set<String> segmentIds) async {
    if (segmentIds.isEmpty) {
      return;
    }
    final entries = await _read();
    var changed = false;
    for (final id in segmentIds) {
      if (entries.remove(id) != null) {
        changed = true;
      }
    }
    if (changed) {
      await _write(entries);
    }
  }

  /// Drops everything except [keepSegmentIds] -- called with the live
  /// segment ids after a story read, so expired statuses don't accumulate.
  Future<void> retainOnly(Set<String> keepSegmentIds) async {
    final entries = await _read();
    final removable = entries.keys.toSet().difference(keepSegmentIds);
    await forget(removable);
  }
}
