import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sqflite/sqflite.dart';

import 'crypto_box.dart';

/// Persistent [SignalProtocolStore] for this device.
///
/// Split across two places on purpose:
///
///  * the identity key pair and registration id go in the OS keystore via
///    [CryptoBox]'s secure storage -- tiny, irreplaceable, and the one piece
///    whose loss changes the user's safety number for every contact; and
///  * sessions, pre-keys and sender keys go in sqflite, every row sealed
///    with the device-local key. There can be thousands of these and they
///    are all rebuildable, so they want a database rather than a keystore --
///    Android's secure storage encrypts entry by entry and does not enjoy
///    being used as one.
///
/// Both halves die together on sign-out: dropping the device-local key makes
/// every row here unreadable even if the file survives.
class WhatsWaveSignalStore implements SignalProtocolStore, SenderKeyStore {
  WhatsWaveSignalStore({
    required Database database,
    required CryptoBox cryptoBox,
    FlutterSecureStorage? secureStorage,
    this.keyNamespace = '',
  })  : _db = database,
        _crypto = cryptoBox,
        _secureStorage = secureStorage ?? CryptoBox.defaultSecureStorage;

  /// Suffix for this store's keystore entries.
  ///
  /// Empty in the app, which has one account per device. Tests use it to
  /// give each simulated device its own identity, since the secure-storage
  /// mock is a single global map and every store would otherwise overwrite
  /// the previous one's identity key.
  final String keyNamespace;

  static const String _identityKeyPairBase = 'ww_signal_identity_keypair_v1';
  static const String _registrationIdBase = 'ww_signal_registration_id_v1';

  String get _identityKeyPairName =>
      keyNamespace.isEmpty ? _identityKeyPairBase : '$_identityKeyPairBase:$keyNamespace';
  String get _registrationIdName =>
      keyNamespace.isEmpty ? _registrationIdBase : '$_registrationIdBase:$keyNamespace';

  final Database _db;
  final CryptoBox _crypto;
  final FlutterSecureStorage _secureStorage;

  IdentityKeyPair? _cachedIdentity;
  int? _cachedRegistrationId;

  /// Contacts whose identity key changed since this device last saw it.
  ///
  /// A changed key means either the person reinstalled, or somebody is
  /// impersonating them. The app cannot tell which, and neither can the
  /// protocol -- only the user comparing safety numbers can. So the change
  /// is surfaced rather than swallowed: silently accepting a new key is
  /// exactly what a man-in-the-middle needs.
  final Set<String> _identityChanges = <String>{};

  /// Uids whose safety number has changed and the user has not yet seen.
  Set<String> get changedIdentities => Set<String>.unmodifiable(
        _identityChanges,
      );

  bool hasIdentityChanged(String uid) => _identityChanges.contains(uid);

  /// Called once the user has been told. Does not re-trust anything -- the
  /// new key is already stored; this only clears the notice.
  void acknowledgeIdentityChange(String uid) {
    _identityChanges.remove(uid);
  }

  /// Creates the tables. Safe to call on every launch.
  static Future<Database> openDatabase_({
    required String path,
    DatabaseFactory? factory,
  }) {
    final open = factory?.openDatabase ?? openDatabase;
    return open(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          // `record` is always a CryptoBox-sealed blob, never plaintext.
          await db.execute(
            'CREATE TABLE pre_keys (id INTEGER PRIMARY KEY, record BLOB NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE signed_pre_keys (id INTEGER PRIMARY KEY, record BLOB NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE sessions ('
            'name TEXT NOT NULL, device_id INTEGER NOT NULL, '
            'record BLOB NOT NULL, PRIMARY KEY (name, device_id))',
          );
          await db.execute(
            'CREATE TABLE identities (name TEXT PRIMARY KEY, key BLOB NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE sender_keys (id TEXT PRIMARY KEY, record BLOB NOT NULL)',
          );
        },
      ),
    );
  }

  Future<Uint8List> _seal(Uint8List value) => _crypto.seal(value);

  Future<Uint8List> _open(Object? stored) async {
    if (stored is! Uint8List) {
      throw const CryptoBoxException('Expected a sealed blob.');
    }
    return _crypto.open(stored);
  }

  // ---------------------------------------------------------------- identity

  /// Installs a freshly generated (or restored) identity.
  Future<void> storeIdentityKeyPair(
    IdentityKeyPair identityKeyPair,
    int registrationId,
  ) async {
    _cachedIdentity = identityKeyPair;
    _cachedRegistrationId = registrationId;
    await _secureStorage.write(
      key: _identityKeyPairName,
      value: base64Encode(identityKeyPair.serialize()),
    );
    await _secureStorage.write(
      key: _registrationIdName,
      value: registrationId.toString(),
    );
  }

  /// Null before an identity exists -- the signal to generate or restore one.
  Future<IdentityKeyPair?> findIdentityKeyPair() async {
    final cached = _cachedIdentity;
    if (cached != null) {
      return cached;
    }
    final stored = await _secureStorage.read(key: _identityKeyPairName);
    if (stored == null) {
      return null;
    }
    return _cachedIdentity =
        IdentityKeyPair.fromSerialized(base64Decode(stored));
  }

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async {
    final pair = await findIdentityKeyPair();
    if (pair == null) {
      throw StateError(
        'No Signal identity on this device yet. '
        'ensureSignalIdentity() must run before any encryption.',
      );
    }
    return pair;
  }

  @override
  Future<int> getLocalRegistrationId() async {
    final cached = _cachedRegistrationId;
    if (cached != null) {
      return cached;
    }
    final stored = await _secureStorage.read(key: _registrationIdName);
    if (stored == null) {
      throw StateError('No Signal registration id on this device yet.');
    }
    return _cachedRegistrationId = int.parse(stored);
  }

  @override
  Future<bool> saveIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
  ) async {
    if (identityKey == null) {
      return false;
    }
    final existing = await getIdentity(address);
    await _db.insert(
      'identities',
      <String, Object?>{
        'name': address.getName(),
        'key': await _seal(identityKey.serialize()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // True means "this replaced a DIFFERENT key". A first sighting is not
    // a change -- there was nothing to compare against.
    final changed = existing != null && existing != identityKey;
    if (changed) {
      _identityChanges.add(address.getName());
    }
    return changed;
  }

  @override
  Future<bool> isTrustedIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
    Direction direction,
  ) async {
    if (identityKey == null) {
      return false;
    }
    final known = await getIdentity(address);
    // Trust on first use, then pin. A changed key is surfaced to the user by
    // saveIdentity's return value rather than silently blocking the message,
    // which matches how Signal and WhatsApp behave: the message arrives and
    // the conversation says the safety number changed.
    return known == null || known == identityKey;
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final rows = await _db.query(
      'identities',
      columns: <String>['key'],
      where: 'name = ?',
      whereArgs: <Object?>[address.getName()],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return IdentityKey.fromBytes(await _open(rows.first['key']), 0);
  }

  // ---------------------------------------------------------------- pre-keys

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final rows = await _db.query(
      'pre_keys',
      columns: <String>['record'],
      where: 'id = ?',
      whereArgs: <Object?>[preKeyId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw InvalidKeyIdException('No pre-key $preKeyId on this device.');
    }
    return PreKeyRecord.fromBuffer(await _open(rows.first['record']));
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    await _db.insert(
      'pre_keys',
      <String, Object?>{'id': preKeyId, 'record': await _seal(record.serialize())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<bool> containsPreKey(int preKeyId) async =>
      Sqflite.firstIntValue(await _db.rawQuery(
        'SELECT COUNT(*) FROM pre_keys WHERE id = ?',
        <Object?>[preKeyId],
      )) !=
      0;

  @override
  Future<void> removePreKey(int preKeyId) async {
    // One-time pre-keys are exactly that: consumed on use and never reissued.
    await _db.delete('pre_keys', where: 'id = ?', whereArgs: <Object?>[preKeyId]);
  }

  /// How many one-time pre-keys are left, so they can be topped up before
  /// running out -- a peer that finds none cannot start a session.
  Future<int> remainingPreKeyCount() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM pre_keys'),
      ) ??
      0;

  // --------------------------------------------------------- signed pre-keys

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final rows = await _db.query(
      'signed_pre_keys',
      columns: <String>['record'],
      where: 'id = ?',
      whereArgs: <Object?>[signedPreKeyId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw InvalidKeyIdException(
        'No signed pre-key $signedPreKeyId on this device.',
      );
    }
    return SignedPreKeyRecord.fromSerialized(await _open(rows.first['record']));
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async {
    final rows = await _db.query('signed_pre_keys', columns: <String>['record']);
    return <SignedPreKeyRecord>[
      for (final row in rows)
        SignedPreKeyRecord.fromSerialized(await _open(row['record'])),
    ];
  }

  @override
  Future<void> storeSignedPreKey(
    int signedPreKeyId,
    SignedPreKeyRecord record,
  ) async {
    await _db.insert(
      'signed_pre_keys',
      <String, Object?>{
        'id': signedPreKeyId,
        'record': await _seal(record.serialize()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async =>
      Sqflite.firstIntValue(await _db.rawQuery(
        'SELECT COUNT(*) FROM signed_pre_keys WHERE id = ?',
        <Object?>[signedPreKeyId],
      )) !=
      0;

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    await _db.delete(
      'signed_pre_keys',
      where: 'id = ?',
      whereArgs: <Object?>[signedPreKeyId],
    );
  }

  // ---------------------------------------------------------------- sessions

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final rows = await _db.query(
      'sessions',
      columns: <String>['record'],
      where: 'name = ? AND device_id = ?',
      whereArgs: <Object?>[address.getName(), address.getDeviceId()],
      limit: 1,
    );
    if (rows.isEmpty) {
      // A fresh record, not an error: this is how a first conversation
      // starts.
      return SessionRecord();
    }
    return SessionRecord.fromSerialized(await _open(rows.first['record']));
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    final rows = await _db.query(
      'sessions',
      columns: <String>['device_id'],
      where: 'name = ? AND device_id != ?',
      whereArgs: <Object?>[name, 1],
    );
    return <int>[for (final row in rows) row['device_id']! as int];
  }

  @override
  Future<void> storeSession(
    SignalProtocolAddress address,
    SessionRecord record,
  ) async {
    await _db.insert(
      'sessions',
      <String, Object?>{
        'name': address.getName(),
        'device_id': address.getDeviceId(),
        'record': await _seal(record.serialize()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async =>
      Sqflite.firstIntValue(await _db.rawQuery(
        'SELECT COUNT(*) FROM sessions WHERE name = ? AND device_id = ?',
        <Object?>[address.getName(), address.getDeviceId()],
      )) !=
      0;

  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    await _db.delete(
      'sessions',
      where: 'name = ? AND device_id = ?',
      whereArgs: <Object?>[address.getName(), address.getDeviceId()],
    );
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    await _db.delete('sessions', where: 'name = ?', whereArgs: <Object?>[name]);
  }

  // ------------------------------------------------------------- sender keys

  @override
  Future<void> storeSenderKey(
    SenderKeyName senderKeyName,
    SenderKeyRecord record,
  ) async {
    await _db.insert(
      'sender_keys',
      <String, Object?>{
        'id': _senderKeyId(senderKeyName),
        'record': await _seal(record.serialize()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<SenderKeyRecord> loadSenderKey(SenderKeyName senderKeyName) async {
    final rows = await _db.query(
      'sender_keys',
      columns: <String>['record'],
      where: 'id = ?',
      whereArgs: <Object?>[_senderKeyId(senderKeyName)],
      limit: 1,
    );
    if (rows.isEmpty) {
      return SenderKeyRecord();
    }
    return SenderKeyRecord.fromSerialized(await _open(rows.first['record']));
  }

  /// Drops this device's own sending key for a group.
  ///
  /// Called when the membership shrinks: the next send then mints a new
  /// chain and redistributes it, so a removed member cannot read anything
  /// sent after they left. Without this, forward secrecy for groups is just
  /// a claim.
  Future<void> deleteSenderKeysForGroup(String groupId) async {
    await _db.delete(
      'sender_keys',
      where: 'id LIKE ?',
      whereArgs: <Object?>['${_escapeLike(groupId)}::%'],
    );
  }

  String _senderKeyId(SenderKeyName name) =>
      '${name.groupId}::${name.sender.getName()}::${name.sender.getDeviceId()}';

  String _escapeLike(String value) =>
      value.replaceAll('%', r'\%').replaceAll('_', r'\_');

  // ----------------------------------------------------------------- wiping

  /// Removes every session, pre-key and sender key, keeping the identity.
  ///
  /// This is the restore path, not the sign-out path. A restored identity
  /// must start from no session state at all: a stale ratchet puts this
  /// device behind the peer's counter, and the resulting desync is
  /// permanent rather than transient. Rebuilding sessions lazily costs one
  /// round trip and always works.
  Future<void> clearSessionState() async {
    await _db.delete('sessions');
    await _db.delete('sender_keys');
    await _db.delete('pre_keys');
    await _db.delete('signed_pre_keys');
  }

  /// Everything, identity included. The sign-out path.
  Future<void> wipe() async {
    await clearSessionState();
    await _db.delete('identities');
    _identityChanges.clear();
    _cachedIdentity = null;
    _cachedRegistrationId = null;
    await _secureStorage.delete(key: _identityKeyPairName);
    await _secureStorage.delete(key: _registrationIdName);
  }
}
