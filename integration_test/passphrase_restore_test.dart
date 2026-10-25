// Flow 3 of docs/test_strategy.md, "Layer 4": fresh install, restore from
// passphrase -- the safety number is unchanged.
//
// **Backend: none, with the backup document faked.** The backup blob lives
// in a `signalBackups/{uid}` Firestore document, and `fake_cloud_firestore`
// (already a dev dependency) stands in for it. That is deliberate and worth
// being plain about: Firestore here is a key-value box for one opaque,
// AEAD-sealed blob, so faking it removes nothing from what this flow
// asserts. The `firestore.rules` suite (`npm run test:rules`) covers who may
// read and write that document; this covers the crypto.
//
// What IS real, and is the entire reason this runs on a device:
//
//  * **Argon2id at production parameters (64 MiB, t=3) in a real isolate**
//    via `compute`. The unit test deliberately injects `deriveKey` with
//    toy parameters so the suite does not crawl, so nothing until now has
//    run the real derivation, and nothing has run it off the main isolate.
//  * **The real Keychain / Keystore.** The identity key pair and
//    registration id live in secure storage, not sqflite (see
//    `WhatsWaveSignalStore`), under their real production entry names --
//    not the `keyNamespace` seam the unit tests use.
//  * **The real sqflite plugin** for pre-keys, signed pre-keys and the
//    pinned identities table.
//  * **The safety number in a real isolate** -- 5200 hash iterations
//    through `compute`, the default the app ships. The widget tests inject
//    a synchronous generator because `compute` does not resolve under the
//    widget-test binding.
//
// NOT covered: the real Firestore document (rules, offline behaviour,
// server timestamps), the passphrase-backup *screen*, and a genuine OS
// reinstall -- "fresh install" here is a wipe of the keystore entries plus a
// new database file, which is what a reinstall leaves behind but not how it
// gets there.
//
// WARNING: this flow writes and then deletes the app's real production
// keystore entries (`ww_signal_identity_keypair_v1`,
// `ww_signal_registration_id_v1`, `ww_local_data_key_v1`). Run it on a test
// device or a fresh simulator, never on a device holding an account you care
// about.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:path/path.dart' as p;
import 'package:whatswave/core/crypto/crypto_box.dart';
import 'package:whatswave/core/crypto/safety_number_service.dart';
import 'package:whatswave/core/crypto/signal_identity_service.dart';
import 'package:whatswave/core/crypto/signal_key_backup_service.dart';
import 'package:whatswave/core/crypto/signal_store.dart';

import 'support/device_storage.dart';

const String _uid = 'alice';
const String _peerUid = 'bob';
const String _passphrase = 'correct horse battery staple';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('restoring from a passphrase keeps the safety number',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    // The contact's published identity key. It does not change across our
    // reinstall, so the only thing that can move the safety number is our
    // own half of it.
    final peerAddress = SignalProtocolAddress(_peerUid, 1);
    final peerIdentity = generateIdentityKeyPair().getPublicKey();

    // --- the install that creates the backup -----------------------------
    final firstRoot = await freshInstallDirectory('flow3_install_1');
    var database = await WhatsWaveSignalStore.openDatabase_(
      path: p.join(firstRoot, 'signal.db'),
    );
    var crypto = CryptoBox();
    var store = WhatsWaveSignalStore(database: database, cryptoBox: crypto);
    await SignalIdentityService(
      store: store,
      firestore: firestore,
      currentUid: () => _uid,
    ).ensureIdentity();
    await store.saveIdentity(peerAddress, peerIdentity);

    final safetyNumberBefore = await SafetyNumberService(store: store)
        .safetyNumber(localUid: _uid, remoteUid: _peerUid);
    expect(safetyNumberBefore, isNotNull);
    expect(safetyNumberBefore, hasLength(60));

    // Real Argon2id at the shipped parameters, in a real isolate. Takes
    // about a second; that is the point.
    await SignalKeyBackupService(
      store: store,
      cryptoBox: crypto,
      firestore: firestore,
    ).createBackup(uid: _uid, passphrase: _passphrase);

    // --- the "fresh install" ---------------------------------------------
    // `wipe()` is what clears the two keystore entries that hold the
    // identity -- deleting the database file alone would NOT, which is
    // exactly the trap a device test exists to catch: the identity would
    // still be found and the assertion below would pass for the wrong
    // reason.
    await store.wipe();
    await crypto.destroyLocalDataKey();
    await database.close();

    final secondRoot = await freshInstallDirectory('flow3_install_2');
    database = await WhatsWaveSignalStore.openDatabase_(
      path: p.join(secondRoot, 'signal.db'),
    );
    crypto = CryptoBox();
    store = WhatsWaveSignalStore(database: database, cryptoBox: crypto);
    addTearDown(() async {
      await store.wipe();
      await crypto.destroyLocalDataKey();
      await database.close();
    });
    expect(
      await store.findIdentityKeyPair(),
      isNull,
      reason: 'the reinstall must start with no identity at all',
    );

    // The control, and the failure this flow guards: a reinstall that does
    // NOT restore generates a new identity, and every contact is told the
    // security code changed.
    final identityService = SignalIdentityService(
      store: store,
      firestore: firestore,
      currentUid: () => _uid,
    );
    await identityService.ensureIdentity();
    await store.saveIdentity(peerAddress, peerIdentity);
    expect(
      await SafetyNumberService(store: store)
          .safetyNumber(localUid: _uid, remoteUid: _peerUid),
      isNot(safetyNumberBefore),
    );

    // --- the restore ------------------------------------------------------
    final restored = await SignalKeyBackupService(
      store: store,
      cryptoBox: crypto,
      firestore: firestore,
      identityService: identityService,
    ).restoreBackup(uid: _uid, passphrase: _passphrase);
    expect(restored, isTrue);

    // `restoreBackup` clears session state but not the pinned identities
    // table, so the contact's key is still here -- as it would be after a
    // re-fetch from the key directory.
    expect(
      await SafetyNumberService(store: store)
          .safetyNumber(localUid: _uid, remoteUid: _peerUid),
      safetyNumberBefore,
    );
  });
}
