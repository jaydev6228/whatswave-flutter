// Flow 1 of docs/test_strategy.md, "Layer 4 -- integration tests on real
// devices": sign in, send a message, force-quit, relaunch -- the message is
// still there.
//
// **Backend: none.** No `Firebase.initializeApp`, no `WW_BACKEND_TARGET`.
// The piece of this flow that can only be proved on a device is the storage
// stack, and it needs no backend: `LocalMessageStore` takes a `Database` and
// a `CryptoBox` and nothing else.
//
// **Why not drive it through the UI.** On the seeded local backend
// (`WW_BACKEND_TARGET=local`) a sent message lives in `FakeChatRepository`'s
// in-memory list, and `SignalCryptoScope` -- which owns `LocalMessageStore`
// -- is only built for the firebase backend (see `main.dart`). So a
// UI-driven version of this flow on the local backend would assert that a
// message survives a relaunch in a build where nothing persists it: it would
// either fail, or pass by re-seeding the same demo data and prove nothing.
// The firebase backend is the one where the message really does survive, and
// that needs live credentials. So this covers the real mechanism directly.
//
// **How "force-quit and relaunch" is simulated, and what that misses:** see
// the comments in the test body.
//
// NOT covered: the Firestore read path that calls into this store, the
// `ChatInboxCache` half of a cold start (it reads
// `FirebaseAuth.instance.currentUser` directly, so it cannot run without a
// signed-in Firebase session), and the sign-in itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:whatswave/core/crypto/crypto_box.dart';
import 'package:whatswave/features/chats/data/local_message_store.dart';

import 'support/device_storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a message that was read once is still readable after a relaunch',
      (tester) async {
    final root = await freshInstallDirectory('flow1_messages');
    final path = p.join(root, 'messages.db');
    // Stands in for the message document's ciphertext. The store is keyed on
    // a digest of it, so it has to be the same string on both sides of the
    // relaunch -- as it is in the app, where it comes from Firestore.
    const cipherText = 'MwohBYc2sealed-envelope-from-firestore';
    const plaintext = 'see you at six';

    // --- before the quit: the message is decrypted once and kept ---------
    var database = await LocalMessageStore.open(path: path);
    await LocalMessageStore(database: database, cryptoBox: CryptoBox()).write(
      threadId: 'ava-patel',
      messageId: 'm-1',
      cipherText: cipherText,
      plaintext: plaintext,
    );

    // "Force-quit": every handle this process holds goes away. This is the
    // honest limit of integration_test -- there is no API to kill and
    // restart the host process, so what is simulated is a *clean* teardown.
    //
    // NOT covered by this: the OS killing the app mid-write (sqflite
    // journal/WAL recovery), a device reboot (which is what actually
    // exercises the Keychain's `first_unlock` accessibility class), and
    // bootstrap/`SignalCryptoScope.create` ordering at launch.
    await database.close();

    // --- the relaunch -----------------------------------------------------
    // Same file, and a brand-new CryptoBox whose in-memory key cache is
    // empty, so the key can only come back out of the real Keychain /
    // Keystore. That is the part no unit test covers: `CryptoBox`'s own
    // tests run against `FlutterSecureStorage.setMockInitialValues`.
    database = await LocalMessageStore.open(path: path);
    final store = LocalMessageStore(database: database, cryptoBox: CryptoBox());

    expect(
      await store.read(
        threadId: 'ava-patel',
        messageId: 'm-1',
        cipherText: cipherText,
      ),
      plaintext,
    );
    await database.close();

    // The read above went through the Keychain rather than finding the text
    // lying around: the file on disk never contains it. Without this the
    // test would still pass if the store silently stopped sealing rows.
    expect(await allBytesAsText(root), isNot(contains(plaintext)));
  });

  testWidgets('a relaunch after sign-out cannot read the message back',
      (tester) async {
    // The other direction of the same property, and the reason flow 1 and
    // flow 4 are one mechanism: persistence across a relaunch is exactly as
    // durable as the Keychain entry, so destroying it is what makes the data
    // gone rather than merely deleted.
    final root = await freshInstallDirectory('flow1_signed_out');
    final path = p.join(root, 'messages.db');
    const cipherText = 'another-sealed-envelope';

    var database = await LocalMessageStore.open(path: path);
    final crypto = CryptoBox();
    await LocalMessageStore(database: database, cryptoBox: crypto).write(
      threadId: 'ava-patel',
      messageId: 'm-1',
      cipherText: cipherText,
      plaintext: 'the previous account said this',
    );
    await crypto.destroyLocalDataKey();
    await database.close();

    database = await LocalMessageStore.open(path: path);
    final store = LocalMessageStore(database: database, cryptoBox: CryptoBox());
    expect(
      await store.read(
        threadId: 'ava-patel',
        messageId: 'm-1',
        cipherText: cipherText,
      ),
      isNull,
      reason: 'the row outlived the key, so it must read as absent',
    );
    expect(await store.count(), 1, reason: 'the row itself is still there');
    await database.close();
  });
}
