// Flow 4 of docs/test_strategy.md, "Layer 4": sign out, sign in as a
// different user -- no trace of the first user's data.
//
// This is the flow the plan calls out as guarding a real data-leak path that
// was fixed (`SessionDataCleaner`) and has no test proving it stays fixed.
// It is the one to keep if only one survives.
//
// **Backend: none.** The teardown is entirely device-local. What runs here
// is exactly what `WhatsWaveApp._clearSignedOutUserData` runs, in the same
// order: the crypto scope's wipe, then `SessionDataCleaner`, then the
// preferences reset. `SignalCryptoScope.wipe()` is spelled out step by step
// rather than called, because building the scope reaches
// `FirebaseFirestore.instance` (through `SignalKeyBackupService`) and so
// needs `Firebase.initializeApp` and live credentials, which this flow does
// not otherwise need. If `wipe()` ever grows a step, this test will keep
// passing while the app leaks -- so the body below mirrors it line for line
// and must be updated with it.
//
// **What is real here, and why this cannot be a widget test:** the real
// `SharedPreferences` plugin, the real Keychain/Keystore (both the device
// data key and the Signal identity entries), real sqflite database files,
// the real `flutter_cache_manager` store, and the real temporary directory
// that holds decrypted attachment copies. `test/core/session/
// session_data_cleaner_test.dart` injects a stand-in for every one of those.
//
// NOT covered: the sign-out *button* and `AuthController`'s ordering (the
// unit test covers that), `SignalIdentityService.unpublish` (server side),
// and the second account actually signing in -- "user B" here is a fresh
// `CryptoBox`, which is what a second sign-in gets.
//
// WARNING: this wipes the app's real on-device state -- SharedPreferences,
// the keystore entries and the media cache. Run it on a test device.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/core/crypto/crypto_box.dart';
import 'package:whatswave/core/crypto/signal_store.dart';
import 'package:whatswave/core/session/session_data_cleaner.dart';
import 'package:whatswave/features/chats/data/local_message_store.dart';
import 'package:whatswave/features/chats/data/pending_send_store.dart';
import 'package:whatswave/features/chats/domain/chat_message.dart';

import 'support/device_storage.dart';

const String _threadId = 'ava-patel';
const String _firstUserUid = 'uid-first-user';
const String _secret = 'the first user wrote this';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signing out leaves the next account nothing it can read',
      (tester) async {
    final root = await freshInstallDirectory('flow4_handover');

    // ------------------------------------------------------------------
    // The first user's device state, written through the real stores.
    // ------------------------------------------------------------------
    final crypto = CryptoBox();
    // Read now, so the assertion at the end can show the keystore entry was
    // replaced rather than merely re-read from a cache.
    final keyBefore = await crypto.localDataKey();
    final signalDb = await WhatsWaveSignalStore.openDatabase_(
      path: p.join(root, 'signal.db'),
    );
    final messagesDb =
        await LocalMessageStore.open(path: p.join(root, 'messages.db'));
    final pendingDb =
        await PendingSendStore.open(path: p.join(root, 'pending.db'));
    addTearDown(() async {
      await signalDb.close();
      await messagesDb.close();
      await pendingDb.close();
    });

    final signalStore =
        WhatsWaveSignalStore(database: signalDb, cryptoBox: crypto);
    final messages = LocalMessageStore(database: messagesDb, cryptoBox: crypto);
    final pending = PendingSendStore(database: pendingDb, cryptoBox: crypto);

    await signalStore.storeIdentityKeyPair(generateIdentityKeyPair(), 4242);
    await messages.write(
      threadId: _threadId,
      messageId: 'm-1',
      cipherText: 'sealed-envelope',
      plaintext: _secret,
    );
    await pending.remember(
      threadId: _threadId,
      message: ChatMessage(
        id: 'm-2',
        senderName: 'You',
        senderUid: _firstUserUid,
        sentAt: DateTime(2026, 10, 25, 9),
        isFromCurrentUser: true,
        text: 'never made it to the server',
        deliveryState: MessageDeliveryState.failed,
      ),
    );

    // The real SharedPreferences store: the uid-scoped inbox cache that was
    // the original leak, plus a privacy choice and the theme.
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'chat_inbox_cache_v2:$_firstUserUid',
      await crypto.sealToBase64('{"threads":[{"name":"Ava Patel"}]}'),
    );
    await preferences.setBool(
      'app_preferences_read_receipts_enabled_v1',
      false,
    );
    await preferences.setString('app_preferences_theme_mode_v1', 'dark');

    // A decrypted attachment copy -- the one plaintext artefact the
    // encryption scheme writes to disk on purpose, so destroying the key
    // does not make it unreadable. It has to be deleted.
    final decryptedMedia = File(
      p.join((await getTemporaryDirectory()).path, 'ww-media-flow4.bin'),
    );
    await decryptedMedia.writeAsString('decrypted photo bytes');

    // A copy of a sealed row, to prove the claim `SessionDataCleaner`
    // actually makes: destroying the key makes the stores unreadable "even
    // if a file survives deletion or is recovered later".
    final survivingRow = Map<String, Object?>.from(
      (await pendingDb.query('pending_sends')).single,
    );

    // ------------------------------------------------------------------
    // Sign out. Mirrors WhatsWaveApp._clearSignedOutUserData exactly.
    // ------------------------------------------------------------------
    // SignalCryptoScope.wipe(), step for step:
    await signalStore.wipe();
    await messages.wipe();
    await pending.wipe();
    await crypto.destroyLocalDataKey();
    // ...then the blanket device wipe, with its real collaborators.
    await const SessionDataCleaner().clearSignedInUserData();

    // ------------------------------------------------------------------
    // The second account signs in on the same device.
    // ------------------------------------------------------------------
    final nextCrypto = CryptoBox();

    expect(
      preferences.getKeys(),
      <String>{'app_preferences_theme_mode_v1'},
      reason: 'only the theme is a device preference rather than user data',
    );
    expect(preferences.getString('app_preferences_theme_mode_v1'), 'dark');

    expect(
      await WhatsWaveSignalStore(database: signalDb, cryptoBox: nextCrypto)
          .findIdentityKeyPair(),
      isNull,
      reason: 'the previous identity must be gone from the real keystore',
    );

    final nextMessages =
        LocalMessageStore(database: messagesDb, cryptoBox: nextCrypto);
    expect(
      await nextMessages.read(
        threadId: _threadId,
        messageId: 'm-1',
        cipherText: 'sealed-envelope',
      ),
      isNull,
    );
    expect(await nextMessages.count(), 0);

    expect(decryptedMedia.existsSync(), isFalse);

    // The recovered row: still on disk, and still useless.
    await pendingDb.insert('pending_sends', survivingRow);
    final nextPending =
        PendingSendStore(database: pendingDb, cryptoBox: nextCrypto);
    expect(
      await nextPending.forThread(_threadId),
      isEmpty,
      reason: 'a row sealed under the destroyed key must not be readable',
    );
    expect(
      (await pendingDb.query('pending_sends')),
      hasLength(1),
      reason: 'the row really is still there -- the key is what is gone',
    );

    // And the key really was replaced in the keystore rather than reused.
    expect(await nextCrypto.localDataKey(), isNot(equals(keyBefore)));

    // Nothing the first user wrote is legible anywhere under the app's
    // own storage root.
    expect(await allBytesAsText(root), isNot(contains(_secret)));
  });
}
