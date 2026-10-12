import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:pointycastle/export.dart';

import 'crypto_box.dart';
import 'signal_identity_service.dart';
import 'signal_store.dart';

/// Argon2id parameters. Stored alongside the blob so a future change can be
/// read back, and authenticated so they cannot be downgraded in transit.
class BackupKdfParameters {
  const BackupKdfParameters({
    this.memoryKib = 65536, // 64 MiB -- the OWASP minimum tier
    this.iterations = 3,
    this.lanes = 4,
  });

  factory BackupKdfParameters.fromJson(Map<String, Object?> json) =>
      BackupKdfParameters(
        memoryKib: (json['m'] as num?)?.toInt() ?? 65536,
        iterations: (json['t'] as num?)?.toInt() ?? 3,
        lanes: (json['p'] as num?)?.toInt() ?? 4,
      );

  final int memoryKib;
  final int iterations;
  final int lanes;

  Map<String, Object?> toJson() => <String, Object?>{
        'kdf': 'argon2id',
        'm': memoryKib,
        't': iterations,
        'p': lanes,
      };
}

class SignalKeyBackupException implements Exception {
  const SignalKeyBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Protects the identity key -- and nothing else -- with a passphrase.
///
/// **What is in the backup: the identity key pair and registration id.**
/// That is the whole payload, a few hundred bytes, and it never changes
/// after creation.
///
/// **What is deliberately NOT in it: session state, sender keys and
/// one-time pre-keys.** Restoring a ratchet is worse than not restoring it.
/// A session record from backup time has a counter behind the peer's, so the
/// next message sent is rejected as a duplicate and everything the peer sent
/// since the backup becomes *permanently* undecryptable -- there is no
/// in-session recovery from that. Starting with no sessions at all costs one
/// extra round trip per conversation and always works, so a restore wipes
/// session state rather than returning it.
///
/// So the backup's actual job is narrow and worth stating plainly: it keeps
/// the identity key, and therefore the safety number, so a reinstall does
/// not make every contact see "security code changed". Resist the urge to
/// put session state back in.
class SignalKeyBackupService {
  SignalKeyBackupService({
    required WhatsWaveSignalStore store,
    required CryptoBox cryptoBox,
    FirebaseFirestore? firestore,
    SignalIdentityService? identityService,
    Future<Uint8List> Function(Argon2Request)? deriveKey,
  })  : _store = store,
        _crypto = cryptoBox,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _identityService = identityService,
        _deriveKey = deriveKey ?? _deriveKeyInIsolate;

  static const int _saltLengthBytes = 16;
  static const int _keyLengthBytes = 32;
  static const int _backupVersion = 1;

  final WhatsWaveSignalStore _store;
  final CryptoBox _crypto;
  final FirebaseFirestore _firestore;
  final SignalIdentityService? _identityService;
  final Future<Uint8List> Function(Argon2Request) _deriveKey;

  DocumentReference<Map<String, dynamic>> _backupDoc(String uid) =>
      _firestore.collection('signalBackups').doc(uid);

  Future<bool> hasBackup(String uid) async =>
      (await _backupDoc(uid).get()).exists;

  /// Writes the backup. Called once, when the identity is created.
  ///
  /// Written once rather than on a schedule because the payload never
  /// changes -- which also means it can never be stale, removing a whole
  /// class of failure.
  Future<void> createBackup({
    required String uid,
    required String passphrase,
    BackupKdfParameters parameters = const BackupKdfParameters(),
  }) async {
    if (passphrase.isEmpty) {
      throw const SignalKeyBackupException('A passphrase is required.');
    }
    final identity = await _store.findIdentityKeyPair();
    if (identity == null) {
      throw const SignalKeyBackupException('No identity to back up yet.');
    }

    final salt = _crypto.randomBytes(_saltLengthBytes);
    final key = await _deriveKey(
      Argon2Request(passphrase, salt, parameters, _keyLengthBytes),
    );

    final header = <String, Object?>{
      'version': _backupVersion,
      ...parameters.toJson(),
    };
    final payload = jsonEncode(<String, Object?>{
      'identityKeyPair': base64Encode(identity.serialize()),
      'registrationId': await _store.getLocalRegistrationId(),
    });

    // The header is authenticated, not just stored: without this, anyone
    // able to write the document could lower m/t/p and make an offline
    // guessing attack cheap, and the victim's client would cooperate.
    final sealed = _crypto.sealWith(
      key,
      Uint8List.fromList(utf8.encode(payload)),
      aad: Uint8List.fromList(utf8.encode(jsonEncode(header))),
    );

    await _backupDoc(uid).set(<String, Object?>{
      ...header,
      'salt': base64Encode(salt),
      'blob': base64Encode(sealed),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Restores the identity, then clears every scrap of session state.
  ///
  /// Returns false for a wrong passphrase, which is indistinguishable from
  /// a corrupt blob and should be -- both mean "do not trust this".
  Future<bool> restoreBackup({
    required String uid,
    required String passphrase,
  }) async {
    final snapshot = await _backupDoc(uid).get();
    final data = snapshot.data();
    if (data == null) {
      throw const SignalKeyBackupException('There is no backup to restore.');
    }

    final parameters = BackupKdfParameters.fromJson(data);
    final header = <String, Object?>{
      'version': (data['version'] as num?)?.toInt() ?? _backupVersion,
      ...parameters.toJson(),
    };
    final salt = Uint8List.fromList(base64Decode(data['salt']! as String));
    final key = await _deriveKey(
      Argon2Request(passphrase, salt, parameters, _keyLengthBytes),
    );

    final Uint8List opened;
    try {
      opened = _crypto.openWith(
        key,
        Uint8List.fromList(base64Decode(data['blob']! as String)),
        aad: Uint8List.fromList(utf8.encode(jsonEncode(header))),
      );
    } on CryptoBoxException {
      return false;
    }

    final payload = jsonDecode(utf8.decode(opened)) as Map<String, dynamic>;
    final identity = IdentityKeyPair.fromSerialized(
      Uint8List.fromList(base64Decode(payload['identityKeyPair']! as String)),
    );
    final registrationId = (payload['registrationId'] as num).toInt();

    await _store.storeIdentityKeyPair(identity, registrationId);

    // See the class doc: a restored ratchet is unrecoverably desynced, so
    // throw all of it away and let sessions rebuild on next send.
    await _store.clearSessionState();

    // Republish, because the pre-keys just deleted were the ones peers
    // would otherwise fetch, and the signed pre-key is gone too.
    await _identityService?.ensureIdentity();
    return true;
  }

  Future<void> deleteBackup(String uid) async {
    await _backupDoc(uid).delete();
  }
}

/// Everything the derivation needs, in one object so it can cross an
/// isolate boundary.
@immutable
class Argon2Request {
  const Argon2Request(
    this.passphrase,
    this.salt,
    this.parameters,
    this.keyLength,
  );

  final String passphrase;
  final Uint8List salt;
  final BackupKdfParameters parameters;
  final int keyLength;
}

/// pointycastle's Argon2 is pure Dart and takes roughly a second at these
/// parameters -- on the main isolate that is a frozen UI on the one screen
/// where the user is most likely to assume the app has hung.
Future<Uint8List> _deriveKeyInIsolate(Argon2Request request) =>
    compute(deriveBackupKey, request);

/// Top-level so it can run in an isolate. Visible for testing, which also
/// lets a test derive synchronously instead of paying a second per case.
@visibleForTesting
Uint8List deriveBackupKey(Object request) {
  final r = request as Argon2Request;
  final generator = Argon2BytesGenerator()
    ..init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        r.salt,
        desiredKeyLength: r.keyLength,
        iterations: r.parameters.iterations,
        memory: r.parameters.memoryKib,
        lanes: r.parameters.lanes,
      ),
    );
  return generator.process(Uint8List.fromList(utf8.encode(r.passphrase)));
}
