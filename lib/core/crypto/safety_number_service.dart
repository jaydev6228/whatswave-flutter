import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'signal_store.dart';

/// Derives the 60-digit safety number two people can compare out of band.
///
/// Why this is required scope rather than polish: without it, a restore
/// from backup that fails, a reinstall, or an actual man-in-the-middle all
/// look identical to normal operation. Encryption with no way to verify the
/// other end's key authenticates nothing -- it only guarantees that
/// *somebody* holds the key, not that it is the person you think.
class SafetyNumberService {
  SafetyNumberService({
    required WhatsWaveSignalStore store,
    Future<String> Function(SafetyNumberRequest)? generate,
  })  : _store = store,
        // Defaults to an isolate hop. Injectable because `compute` does not
        // resolve under the widget-test binding -- pumpAndSettle waits on
        // frames while the isolate's reply never arrives, and the test
        // simply hangs rather than failing.
        _generate = generate ?? ((r) => compute(generateSafetyNumber, r));

  /// Signal's own iteration count and version, so a number produced here is
  /// the same number any other correct implementation would produce for the
  /// same pair of keys.
  static const int _iterations = 5200;
  static const int _version = 1;

  final WhatsWaveSignalStore _store;
  final Future<String> Function(SafetyNumberRequest) _generate;

  /// The shared number for [localUid] and [remoteUid], or null when the
  /// remote identity has not been seen yet (nothing to verify against).
  ///
  /// Both sides compute the same digits regardless of who asks: the
  /// generator sorts the two halves internally.
  Future<String?> safetyNumber({
    required String localUid,
    required String remoteUid,
  }) async {
    final localIdentity = await _store.findIdentityKeyPair();
    if (localIdentity == null) {
      return null;
    }
    final remoteIdentity = await _store.getIdentity(
      SignalProtocolAddress(remoteUid, 1),
    );
    if (remoteIdentity == null) {
      return null;
    }

    // Runs ~5200 hash iterations; off the main isolate so opening contact
    // info never janks.
    return _generate(
      SafetyNumberRequest(
        localUid: localUid,
        remoteUid: remoteUid,
        localIdentity: localIdentity.getPublicKey().serialize(),
        remoteIdentity: remoteIdentity.serialize(),
      ),
    );
  }

  /// Groups of five, the way Signal and WhatsApp present it -- comparing
  /// 60 digits aloud is only realistic in chunks.
  static String format(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i += 5) {
      if (i > 0) {
        buffer.write(i % 25 == 0 ? '\n' : ' ');
      }
      buffer.write(digits.substring(i, (i + 5).clamp(0, digits.length)));
    }
    return buffer.toString();
  }
}

@immutable
class SafetyNumberRequest {
  const SafetyNumberRequest({
    required this.localUid,
    required this.remoteUid,
    required this.localIdentity,
    required this.remoteIdentity,
  });

  final String localUid;
  final String remoteUid;
  final Uint8List localIdentity;
  final Uint8List remoteIdentity;
}

/// Top-level so it can run in an isolate.
String generateSafetyNumber(SafetyNumberRequest request) {
  final fingerprint = NumericFingerprintGenerator(
    SafetyNumberService._iterations,
  ).createFor(
    SafetyNumberService._version,
    Uint8List.fromList(utf8.encode(request.localUid)),
    IdentityKey.fromBytes(request.localIdentity, 0),
    Uint8List.fromList(utf8.encode(request.remoteUid)),
    IdentityKey.fromBytes(request.remoteIdentity, 0),
  );
  return fingerprint.displayableFingerprint.getDisplayText();
}
