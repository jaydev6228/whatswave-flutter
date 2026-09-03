import 'package:flutter/foundation.dart';

/// One in-flight media transfer -- an upload or a download -- as a
/// listenable fraction plus a cancel switch.
///
/// Exists so the code moving the bytes and the bubble drawing the ring
/// never have to know about each other: the sender hands one of these down
/// into the repository, and the same object goes into the bubble's
/// overlay.
///
/// Byte counts arrive per slot (one slot per attachment) rather than as a
/// single running total, because an album uploads its photos in parallel
/// and WhatsApp shows one ring for the whole message rather than one per
/// tile -- summing here is the only place that has every slot's numbers.
class MediaTransfer extends ChangeNotifier {
  final Map<String, (int, int)> _slots = <String, (int, int)>{};
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  /// Null until some slot has reported a total it actually measured, so a
  /// transfer nobody can size spins indeterminately instead of claiming a
  /// percentage that was invented.
  double? get progress {
    if (_slots.isEmpty) {
      return null;
    }
    var transferred = 0;
    var total = 0;
    for (final slot in _slots.values) {
      transferred += slot.$1;
      total += slot.$2;
    }
    if (total <= 0) {
      return null;
    }
    return (transferred / total).clamp(0.0, 1.0);
  }

  void report(String slot, {required int transferred, required int total}) {
    // A cancelled transfer must never crawl forward again: the platform
    // keeps delivering a snapshot or two after cancel() lands, and letting
    // those through moved the ring on a transfer the reader had stopped.
    if (_isCancelled) {
      return;
    }
    _slots[slot] = (transferred, total);
    notifyListeners();
  }

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    notifyListeners();
  }
}
