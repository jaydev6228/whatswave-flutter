import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatswave/core/crypto/crypto_box.dart';
import 'package:whatswave/core/crypto/safety_number_service.dart';
import 'package:whatswave/core/crypto/signal_store.dart';

Future<WhatsWaveSignalStore> freshStore(String namespace) async {
  final dir = await Directory.systemTemp.createTemp('ww_safety');
  addTearDown(() => dir.delete(recursive: true));
  final db = await WhatsWaveSignalStore.openDatabase_(
    path: '${dir.path}/signal.db',
    factory: databaseFactoryFfi,
  );
  return WhatsWaveSignalStore(
    database: db,
    cryptoBox: CryptoBox(),
    keyNamespace: namespace,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('both sides compute the same number', () async {
    // The entire premise: two people reading digits to each other must see
    // the same digits, or verification means nothing.
    final aliceKeys = generateIdentityKeyPair();
    final bobKeys = generateIdentityKeyPair();

    final aliceStore = await freshStore('alice');
    await aliceStore.storeIdentityKeyPair(aliceKeys, 1);
    await aliceStore.saveIdentity(
      SignalProtocolAddress('bob', 1),
      bobKeys.getPublicKey(),
    );

    final bobStore = await freshStore('bob');
    await bobStore.storeIdentityKeyPair(bobKeys, 2);
    await bobStore.saveIdentity(
      SignalProtocolAddress('alice', 1),
      aliceKeys.getPublicKey(),
    );

    final fromAlice = await SafetyNumberService(store: aliceStore, generate: _sync)
        .safetyNumber(localUid: 'alice', remoteUid: 'bob');
    final fromBob = await SafetyNumberService(store: bobStore, generate: _sync)
        .safetyNumber(localUid: 'bob', remoteUid: 'alice');

    expect(fromAlice, isNotNull);
    expect(fromAlice, equals(fromBob));
    expect(fromAlice!.length, 60);
    expect(RegExp(r'^\d{60}$').hasMatch(fromAlice), isTrue);
  });

  test('a different contact gives a different number', () async {
    final aliceKeys = generateIdentityKeyPair();
    final store = await freshStore('alice');
    await store.storeIdentityKeyPair(aliceKeys, 1);
    await store.saveIdentity(
      SignalProtocolAddress('bob', 1),
      generateIdentityKeyPair().getPublicKey(),
    );
    await store.saveIdentity(
      SignalProtocolAddress('carol', 1),
      generateIdentityKeyPair().getPublicKey(),
    );

    final service = SafetyNumberService(store: store, generate: _sync);
    expect(
      await service.safetyNumber(localUid: 'alice', remoteUid: 'bob'),
      isNot(equals(
        await service.safetyNumber(localUid: 'alice', remoteUid: 'carol'),
      )),
    );
  });

  test("changes when the contact's identity key changes", () async {
    // This is what makes a MITM or a failed restore visible instead of
    // silent: the number the user previously compared stops matching.
    final store = await freshStore('alice');
    await store.storeIdentityKeyPair(generateIdentityKeyPair(), 1);
    final bob = SignalProtocolAddress('bob', 1);

    await store.saveIdentity(bob, generateIdentityKeyPair().getPublicKey());
    final service = SafetyNumberService(store: store, generate: _sync);
    final before =
        await service.safetyNumber(localUid: 'alice', remoteUid: 'bob');

    await store.saveIdentity(bob, generateIdentityKeyPair().getPublicKey());
    final after =
        await service.safetyNumber(localUid: 'alice', remoteUid: 'bob');

    expect(after, isNot(equals(before)));
  });

  test('is null for a contact whose key has never been seen', () async {
    final store = await freshStore('alice');
    await store.storeIdentityKeyPair(generateIdentityKeyPair(), 1);
    expect(
      await SafetyNumberService(store: store, generate: _sync)
          .safetyNumber(localUid: 'alice', remoteUid: 'stranger'),
      isNull,
    );
  });

  test('formats into readable groups', () {
    final formatted = SafetyNumberService.format('1' * 60);
    expect(formatted.replaceAll(RegExp(r'\s'), ''), '1' * 60);
    expect(formatted.split('\n').length, 3,
        reason: 'three lines of five groups, the way Signal shows it');
  });
}

/// Derives in-process. `compute` spawns an isolate, which both slows these
/// tests down and never resolves under a widget-test binding.
Future<String> _sync(SafetyNumberRequest request) async =>
    generateSafetyNumber(request);
