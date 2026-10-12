import 'dart:io';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatswave/core/crypto/crypto_box.dart';
import 'package:whatswave/core/crypto/signal_key_backup_service.dart';
import 'package:whatswave/core/crypto/signal_store.dart';

/// Real Argon2id, but at toy cost. The production parameters (64 MiB, t=3)
/// take about a second per derivation, which would make this suite crawl --
/// what is under test here is the wiring and the AAD binding, not Argon2.
const BackupKdfParameters fastKdf =
    BackupKdfParameters(memoryKib: 256, iterations: 1, lanes: 1);

Future<Uint8List> deriveFast(Argon2Request r) async => deriveBackupKey(r);

void main() {
  late WhatsWaveSignalStore store;
  late CryptoBox crypto;
  late FakeFirebaseFirestore firestore;
  late SignalKeyBackupService service;
  late IdentityKeyPair identity;

  setUpAll(() {
    sqfliteFfiInit();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final dir = await Directory.systemTemp.createTemp('ww_backup_test');
    addTearDown(() => dir.delete(recursive: true));
    final db = await WhatsWaveSignalStore.openDatabase_(
      path: '${dir.path}/signal.db',
      factory: databaseFactoryFfi,
    );
    crypto = CryptoBox();
    store = WhatsWaveSignalStore(database: db, cryptoBox: crypto);
    firestore = FakeFirebaseFirestore();
    service = SignalKeyBackupService(
      store: store,
      cryptoBox: crypto,
      firestore: firestore,
      deriveKey: deriveFast,
    );

    identity = generateIdentityKeyPair();
    await store.storeIdentityKeyPair(identity, 1234);
  });

  test('restores the same identity, which is the whole point', () async {
    // A reinstall that keeps the identity key keeps the safety number, so
    // contacts are not all told the security code changed.
    await service.createBackup(
      uid: 'alice',
      passphrase: 'correct horse battery staple',
      parameters: fastKdf,
    );

    await store.wipe();
    expect(await store.findIdentityKeyPair(), isNull);

    final ok = await service.restoreBackup(
      uid: 'alice',
      passphrase: 'correct horse battery staple',
    );

    expect(ok, isTrue);
    expect((await store.getIdentityKeyPair()).serialize(),
        equals(identity.serialize()));
    expect(await store.getLocalRegistrationId(), 1234);
  });

  test('rejects a wrong passphrase', () async {
    await service.createBackup(
      uid: 'alice',
      passphrase: 'right',
      parameters: fastKdf,
    );
    await store.wipe();

    expect(
      await service.restoreBackup(uid: 'alice', passphrase: 'wrong'),
      isFalse,
    );
    expect(await store.findIdentityKeyPair(), isNull,
        reason: 'a failed restore must not half-apply');
  });

  test('refuses a downgraded work factor', () async {
    // Anyone able to write the document could otherwise drop m/t/p to
    // something trivial and make offline guessing cheap -- and the victim's
    // own client would happily use the weakened parameters. The header is
    // authenticated, so tampering with it breaks the tag.
    await service.createBackup(
      uid: 'alice',
      passphrase: 'pass',
      parameters: fastKdf,
    );
    await firestore
        .collection('signalBackups')
        .doc('alice')
        .update(<String, Object?>{'m': 8, 't': 1, 'p': 1});
    await store.wipe();

    expect(
      await service.restoreBackup(uid: 'alice', passphrase: 'pass'),
      isFalse,
    );
  });

  test('refuses a tampered blob', () async {
    await service.createBackup(
      uid: 'alice',
      passphrase: 'pass',
      parameters: fastKdf,
    );
    final doc = firestore.collection('signalBackups').doc('alice');
    final blob = (await doc.get()).data()!['blob']! as String;
    await doc.update(<String, Object?>{
      'blob': '${blob.substring(0, blob.length - 4)}AAAA',
    });
    await store.wipe();

    expect(
      await service.restoreBackup(uid: 'alice', passphrase: 'pass'),
      isFalse,
    );
  });

  test('a restore clears session state rather than returning it', () async {
    // Restoring a ratchet is worse than not restoring one: the counter is
    // behind the peer's, the next send is rejected as a duplicate, and
    // everything they sent since is permanently undecryptable.
    await service.createBackup(
      uid: 'alice',
      passphrase: 'pass',
      parameters: fastKdf,
    );
    await store.storeSession(SignalProtocolAddress('bob', 1), SessionRecord());
    expect(
      await store.containsSession(SignalProtocolAddress('bob', 1)),
      isTrue,
    );

    await service.restoreBackup(uid: 'alice', passphrase: 'pass');

    expect(
      await store.containsSession(SignalProtocolAddress('bob', 1)),
      isFalse,
      reason: 'sessions must be rebuilt from scratch, never restored',
    );
    expect(await store.findIdentityKeyPair(), isNotNull,
        reason: 'the identity, by contrast, is exactly what we kept');
  });

  test('does not store the identity key in the clear', () async {
    await service.createBackup(
      uid: 'alice',
      passphrase: 'pass',
      parameters: fastKdf,
    );
    final data = (await firestore
            .collection('signalBackups')
            .doc('alice')
            .get())
        .data()!;
    expect(data['blob'], isNot(contains('identityKeyPair')));
    expect(data.containsKey('salt'), isTrue);
    expect(data['kdf'], 'argon2id');
  });

  test('reports whether a backup exists, for the restore prompt', () async {
    expect(await service.hasBackup('alice'), isFalse);
    await service.createBackup(
      uid: 'alice',
      passphrase: 'pass',
      parameters: fastKdf,
    );
    expect(await service.hasBackup('alice'), isTrue);
    await service.deleteBackup('alice');
    expect(await service.hasBackup('alice'), isFalse);
  });

  test('refuses to back up an empty passphrase', () async {
    expect(
      () => service.createBackup(
        uid: 'alice',
        passphrase: '',
        parameters: fastKdf,
      ),
      throwsA(isA<SignalKeyBackupException>()),
    );
  });

  test('Argon2id is deterministic for the same salt and passphrase', () async {
    final salt = Uint8List.fromList(List<int>.filled(16, 7));
    final a = deriveBackupKey(Argon2Request('pw', salt, fastKdf, 32));
    final b = deriveBackupKey(Argon2Request('pw', salt, fastKdf, 32));
    final c = deriveBackupKey(Argon2Request('other', salt, fastKdf, 32));
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
    expect(a.length, 32);
  });
}
