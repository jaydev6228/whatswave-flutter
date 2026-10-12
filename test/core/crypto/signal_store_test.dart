import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatswave/core/crypto/crypto_box.dart';
import 'package:whatswave/core/crypto/signal_store.dart';

Uint8List pad(String s) => Uint8List.fromList(utf8.encode(s));

/// A fully provisioned device: identity, registration id, pre-keys.
class TestDevice {
  TestDevice(this.uid, this.store, this.identity, this.registrationId,
      this.preKeys, this.signedPreKey);

  final String uid;
  final WhatsWaveSignalStore store;
  final IdentityKeyPair identity;
  final int registrationId;
  final List<PreKeyRecord> preKeys;
  final SignedPreKeyRecord signedPreKey;

  SignalProtocolAddress get address => SignalProtocolAddress(uid, 1);

  /// What this device publishes so others can start a session with it.
  PreKeyBundle bundle() => PreKeyBundle(
        registrationId,
        1,
        preKeys.first.id,
        preKeys.first.getKeyPair().publicKey,
        signedPreKey.id,
        signedPreKey.getKeyPair().publicKey,
        signedPreKey.signature,
        identity.getPublicKey(),
      );
}

Future<TestDevice> buildDevice(String uid) async {
  final db = await freshDatabase();
  // Each simulated device needs its own keystore namespace: the
  // flutter_secure_storage mock is one global map, so without this every
  // device would overwrite the previous one's identity key.
  final store = WhatsWaveSignalStore(
    database: db,
    cryptoBox: CryptoBox(),
    keyNamespace: uid,
  );

  final identity = generateIdentityKeyPair();
  final registrationId = generateRegistrationId(false);
  await store.storeIdentityKeyPair(identity, registrationId);

  final preKeys = generatePreKeys(0, 10);
  for (final k in preKeys) {
    await store.storePreKey(k.id, k);
  }
  final signed = generateSignedPreKey(identity, 0);
  await store.storeSignedPreKey(signed.id, signed);

  return TestDevice(uid, store, identity, registrationId, preKeys, signed);
}

/// A database nobody else shares.
///
/// Not `inMemoryDatabasePath`: that is the literal string ':memory:', and
/// sqflite-ffi hands back the *same* in-memory database for it within a
/// process. Rows written by one test -- sealed with that test's device key,
/// which setUp then throws away -- survived into the next one and failed to
/// decrypt there, which looked exactly like a crypto bug.
int _dbCounter = 0;
Future<Database> freshDatabase() async {
  final dir = await Directory.systemTemp.createTemp('ww_signal_test');
  addTearDown(() => dir.delete(recursive: true));
  return WhatsWaveSignalStore.openDatabase_(
    path: '${dir.path}/signal_${_dbCounter++}.db',
    factory: databaseFactoryFfi,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('WhatsWaveSignalStore persistence', () {
    test('round-trips every record type', () async {
      final d = await buildDevice('alice');

      expect((await d.store.getIdentityKeyPair()).serialize(),
          equals(d.identity.serialize()));
      expect(await d.store.getLocalRegistrationId(), d.registrationId);
      expect(await d.store.containsPreKey(0), isTrue);
      expect((await d.store.loadPreKey(0)).id, 0);
      expect(await d.store.containsSignedPreKey(0), isTrue);
      expect(await d.store.remainingPreKeyCount(), 10);

      await d.store.removePreKey(0);
      expect(await d.store.containsPreKey(0), isFalse);
      expect(await d.store.remainingPreKeyCount(), 9);
    });

    test('stores rows encrypted, not in the clear', () async {
      // The database file is the thing a backup extractor or a forensic
      // tool gets hold of. Nothing readable should be in it.
      final db = await freshDatabase();
      final store = WhatsWaveSignalStore(database: db, cryptoBox: CryptoBox());
      final identity = generateIdentityKeyPair();
      await store.storeIdentityKeyPair(identity, 42);
      await store.saveIdentity(
        SignalProtocolAddress('bob', 1),
        identity.getPublicKey(),
      );

      final raw = (await db.query('identities')).first['key']! as Uint8List;
      expect(
        raw,
        isNot(equals(identity.getPublicKey().serialize())),
        reason: 'the stored bytes must not be the key itself',
      );
      // And it must still decrypt back to the real thing.
      final back = await store.getIdentity(SignalProtocolAddress('bob', 1));
      expect(back, equals(identity.getPublicKey()));
    });

    test('reports a changed identity, which is the safety-number warning',
        () async {
      final db = await freshDatabase();
      final store = WhatsWaveSignalStore(database: db, cryptoBox: CryptoBox());
      final bob = SignalProtocolAddress('bob', 1);
      final first = generateIdentityKeyPair().getPublicKey();
      final second = generateIdentityKeyPair().getPublicKey();

      expect(await store.saveIdentity(bob, first), isFalse,
          reason: 'first sighting is not a change');
      expect(await store.saveIdentity(bob, first), isFalse,
          reason: 'same key again is not a change');
      expect(await store.saveIdentity(bob, second), isTrue,
          reason: 'a different key for a known contact IS a change');
    });

    test('clearSessionState keeps the identity but drops sessions', () async {
      final d = await buildDevice('alice');
      await d.store.storeSession(
        SignalProtocolAddress('bob', 1),
        SessionRecord(),
      );
      expect(await d.store.containsSession(SignalProtocolAddress('bob', 1)),
          isTrue);

      await d.store.clearSessionState();

      expect(await d.store.containsSession(SignalProtocolAddress('bob', 1)),
          isFalse);
      expect(await d.store.remainingPreKeyCount(), 0);
      expect(
        await d.store.findIdentityKeyPair(),
        isNotNull,
        reason: 'a restore keeps the identity and rebuilds sessions lazily',
      );
    });

    test('wipe removes the identity too', () async {
      final d = await buildDevice('alice');
      await d.store.wipe();
      expect(await d.store.findIdentityKeyPair(), isNull);
    });
  });

  group('end-to-end 1:1', () {
    test('Alice and Bob exchange messages through the persistent store',
        () async {
      final alice = await buildDevice('alice');
      final bob = await buildDevice('bob');

      // Alice starts a session from Bob's published bundle.
      await SessionBuilder.fromSignalStore(alice.store, bob.address)
          .processPreKeyBundle(bob.bundle());

      final aliceCipher =
          SessionCipher.fromStore(alice.store, bob.address);
      final outgoing = await aliceCipher.encrypt(pad('hello bob'));

      // Over the wire it is opaque.
      expect(utf8.decode(outgoing.serialize(), allowMalformed: true),
          isNot(contains('hello bob')));

      final bobCipher = SessionCipher.fromStore(bob.store, alice.address);
      final decrypted = await bobCipher.decrypt(
        PreKeySignalMessage(outgoing.serialize()),
      );
      expect(utf8.decode(decrypted), 'hello bob');

      // And back the other way, now that a session exists both sides.
      final reply = await bobCipher.encrypt(pad('hello alice'));
      final decryptedReply = await aliceCipher
          .decryptFromSignal(SignalMessage.fromSerialized(reply.serialize()));
      expect(utf8.decode(decryptedReply), 'hello alice');
    });

    test('a ciphertext decrypts exactly once', () async {
      // The constraint the whole design rests on: decrypting advances the
      // ratchet and consumes the message key. Every re-read of a message
      // document has to be served from the local plaintext store instead,
      // or history silently breaks.
      final alice = await buildDevice('alice');
      final bob = await buildDevice('bob');
      await SessionBuilder.fromSignalStore(alice.store, bob.address)
          .processPreKeyBundle(bob.bundle());

      final outgoing =
          await SessionCipher.fromStore(alice.store, bob.address)
              .encrypt(pad('only once'));
      final bobCipher = SessionCipher.fromStore(bob.store, alice.address);

      expect(
        utf8.decode(
          await bobCipher.decrypt(PreKeySignalMessage(outgoing.serialize())),
        ),
        'only once',
      );
      await expectLater(
        bobCipher.decrypt(PreKeySignalMessage(outgoing.serialize())),
        throwsA(isA<Exception>()),
        reason: 'a second decrypt of the same bytes must not succeed',
      );
    });

    test('messages arriving out of order still decrypt', () async {
      final alice = await buildDevice('alice');
      final bob = await buildDevice('bob');
      await SessionBuilder.fromSignalStore(alice.store, bob.address)
          .processPreKeyBundle(bob.bundle());
      final aliceCipher = SessionCipher.fromStore(alice.store, bob.address);

      final first = await aliceCipher.encrypt(pad('one'));
      final second = await aliceCipher.encrypt(pad('two'));
      final third = await aliceCipher.encrypt(pad('three'));

      final bobCipher = SessionCipher.fromStore(bob.store, alice.address);
      // Third, then first, then second -- the ratchet keeps skipped keys.
      expect(
        utf8.decode(
          await bobCipher.decrypt(PreKeySignalMessage(third.serialize())),
        ),
        'three',
      );
      expect(
        utf8.decode(
          await bobCipher.decrypt(PreKeySignalMessage(first.serialize())),
        ),
        'one',
      );
      expect(
        utf8.decode(
          await bobCipher.decrypt(PreKeySignalMessage(second.serialize())),
        ),
        'two',
      );
    });
  });

  group('end-to-end group (sender keys)', () {
    test('a group member can read a message, and a removed one cannot',
        () async {
      final alice = await buildDevice('alice');
      final bob = await buildDevice('bob');
      final carol = await buildDevice('carol');

      const groupId = 'thread-1';
      final aliceInGroup =
          SenderKeyName(groupId, SignalProtocolAddress('alice', 1));

      // Alice mints her sending key and distributes it to the others.
      final distribution =
          await GroupSessionBuilder(alice.store).create(aliceInGroup);
      for (final member in <TestDevice>[bob, carol]) {
        await GroupSessionBuilder(member.store).process(
          aliceInGroup,
          SenderKeyDistributionMessageWrapper.fromSerialized(
            distribution.serialize(),
          ),
        );
      }

      final ciphertext = await GroupCipher(alice.store, aliceInGroup)
          .encrypt(pad('group message'));

      expect(
        utf8.decode(await GroupCipher(bob.store, aliceInGroup)
            .decrypt(ciphertext)),
        'group message',
      );

      // Carol leaves: Alice drops her sending chain, so the next message
      // uses a key Carol was never given.
      await alice.store.deleteSenderKeysForGroup(groupId);
      final rotatedDistribution =
          await GroupSessionBuilder(alice.store).create(aliceInGroup);
      await GroupSessionBuilder(bob.store).process(
        aliceInGroup,
        SenderKeyDistributionMessageWrapper.fromSerialized(
          rotatedDistribution.serialize(),
        ),
      );

      final afterRemoval = await GroupCipher(alice.store, aliceInGroup)
          .encrypt(pad('bob only'));

      expect(
        utf8.decode(await GroupCipher(bob.store, aliceInGroup)
            .decrypt(afterRemoval)),
        'bob only',
        reason: 'a remaining member who got the new key can still read',
      );
      await expectLater(
        GroupCipher(carol.store, aliceInGroup).decrypt(afterRemoval),
        throwsA(isA<Exception>()),
        reason: 'the removed member must not be able to read later messages',
      );
    });
  });
}
