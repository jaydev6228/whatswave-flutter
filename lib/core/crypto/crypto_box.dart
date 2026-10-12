import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

/// Thrown when sealed data cannot be opened: wrong key, or tampering.
class CryptoBoxException implements Exception {
  const CryptoBoxException(this.message);

  final String message;

  @override
  String toString() => 'CryptoBoxException: $message';
}

/// AES-256-GCM at rest, keyed by one device-local key held in the OS keystore.
///
/// Everything this app persists locally that derives from decrypted message
/// content goes through here: the Signal session store, the local plaintext
/// message store, and the chat inbox cache. One key rather than several so
/// that sign-out has exactly one thing to destroy -- deleting it makes every
/// one of those stores unreadable at once, which is the property that makes
/// "wipe the previous user's data" actually true rather than best-effort.
///
/// The key never leaves the device and is never backed up: it protects data
/// that is itself rebuildable from the server, so losing it costs a resync,
/// not history. The identity key, which is *not* rebuildable, is handled
/// separately by the passphrase backup.
class CryptoBox {
  CryptoBox({FlutterSecureStorage? secureStorage, Random? random})
      : _secureStorage = secureStorage ?? defaultSecureStorage,
        _random = random ?? Random.secure();

  /// `first_unlock` rather than the default `unlocked`: the app is woken in
  /// the background to handle pushes and must be able to decrypt then. The
  /// data still stays encrypted until the device has been unlocked once
  /// since boot.
  static const FlutterSecureStorage defaultSecureStorage =
      FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    // The Android defaults are already RSA-OAEP key wrapping over AES-GCM.
    // The one default worth overriding is resetOnError, which is true and
    // silently wipes the whole store when a read fails -- acceptable for a
    // cache, not for something holding an E2EE identity key, where a
    // transient Keystore error would destroy the user's identity and every
    // contact's safety number with it. Fail loudly instead.
    aOptions: AndroidOptions(resetOnError: false),
  );

  static const String _localDataKeyName = 'ww_local_data_key_v1';
  static const int _keyLengthBytes = 32; // AES-256
  static const int _nonceLengthBytes = 12; // GCM standard
  static const int _macLengthBits = 128;

  final FlutterSecureStorage _secureStorage;
  final Random _random;

  Uint8List? _cachedKey;
  Future<Uint8List>? _pendingKey;

  /// Loads the device-local key, creating it on first use.
  ///
  /// Single-flight on purpose. Caching only the resolved value is not
  /// enough: two seals racing on a fresh install would both find no stored
  /// key, both generate a *different* one, and both write -- after which
  /// everything sealed with the loser's key is permanently unopenable. The
  /// `??=` is safe without a lock because there is no await between the
  /// read and the assignment.
  Future<Uint8List> localDataKey() {
    final cached = _cachedKey;
    if (cached != null) {
      return Future<Uint8List>.value(cached);
    }
    return _pendingKey ??= _loadOrCreateLocalDataKey();
  }

  Future<Uint8List> _loadOrCreateLocalDataKey() async {
    final stored = await _secureStorage.read(key: _localDataKeyName);
    if (stored != null) {
      final decoded = base64Decode(stored);
      if (decoded.length == _keyLengthBytes) {
        return _cachedKey = Uint8List.fromList(decoded);
      }
      // A key of the wrong length can only be corruption. Replacing it
      // orphans whatever it encrypted, which is recoverable (a resync);
      // carrying on with it is not.
    }
    final fresh = randomBytes(_keyLengthBytes);
    await _secureStorage.write(
      key: _localDataKeyName,
      value: base64Encode(fresh),
    );
    return _cachedKey = fresh;
  }

  /// Destroys the key, which renders every local encrypted store unreadable.
  Future<void> destroyLocalDataKey() async {
    _cachedKey = null;
    _pendingKey = null;
    await _secureStorage.delete(key: _localDataKeyName);
  }

  Uint8List randomBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// nonce ‖ ciphertext ‖ tag, under the device-local key.
  Future<Uint8List> seal(Uint8List plaintext) async =>
      sealWith(await localDataKey(), plaintext);

  Future<Uint8List> open(Uint8List sealed) async =>
      openWith(await localDataKey(), sealed);

  Future<String> sealToBase64(String plaintext) async =>
      base64Encode(await seal(Uint8List.fromList(utf8.encode(plaintext))));

  Future<String> openFromBase64(String sealed) async =>
      utf8.decode(await open(Uint8List.fromList(base64Decode(sealed))));

  /// Explicit-key variants, for data keyed by something other than the
  /// device key -- the passphrase backup, and per-attachment media keys.
  Uint8List sealWith(Uint8List key, Uint8List plaintext, {Uint8List? aad}) {
    final nonce = randomBytes(_nonceLengthBytes);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          _macLengthBits,
          nonce,
          aad ?? Uint8List(0),
        ),
      );
    final body = cipher.process(plaintext);
    return Uint8List.fromList(<int>[...nonce, ...body]);
  }

  Uint8List openWith(Uint8List key, Uint8List sealed, {Uint8List? aad}) {
    if (sealed.length <= _nonceLengthBytes) {
      throw const CryptoBoxException('Sealed data is too short to be valid.');
    }
    final nonce = Uint8List.sublistView(sealed, 0, _nonceLengthBytes);
    final body = Uint8List.sublistView(sealed, _nonceLengthBytes);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          _macLengthBits,
          nonce,
          aad ?? Uint8List(0),
        ),
      );
    try {
      return cipher.process(body);
    } on InvalidCipherTextException {
      // GCM cannot distinguish a wrong key from altered bytes, and it should
      // not try: both mean "do not trust this".
      throw const CryptoBoxException(
        'Could not open sealed data: wrong key or the data was altered.',
      );
    }
  }
}
