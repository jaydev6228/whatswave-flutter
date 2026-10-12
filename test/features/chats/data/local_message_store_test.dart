import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatswave/core/crypto/crypto_box.dart';
import 'package:whatswave/features/chats/data/local_message_store.dart';

void main() {
  late LocalMessageStore store;
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    // A file per test, not ':memory:' -- sqflite-ffi reuses one in-memory
    // database per process, which leaks rows between tests.
    final dir = await Directory.systemTemp.createTemp('ww_msg_store');
    addTearDown(() => dir.delete(recursive: true));
    db = await LocalMessageStore.open(
      path: '${dir.path}/messages.db',
      factory: databaseFactoryFfi,
    );
    store = LocalMessageStore(database: db, cryptoBox: CryptoBox());
  });

  test('returns null for a message it has never seen', () async {
    expect(
      await store.read(threadId: 't1', messageId: 'm1', cipherText: 'abc'),
      isNull,
    );
  });

  test('serves the plaintext back for the same ciphertext', () async {
    // The whole point: the second read of a message must not need to
    // decrypt again, because the ratchet will not allow it.
    await store.write(
      threadId: 't1',
      messageId: 'm1',
      cipherText: 'abc',
      plaintext: '{"text":"hello"}',
    );
    expect(
      await store.read(threadId: 't1', messageId: 'm1', cipherText: 'abc'),
      '{"text":"hello"}',
    );
    // Repeatedly, as watchThreads would.
    for (var i = 0; i < 5; i++) {
      expect(
        await store.read(threadId: 't1', messageId: 'm1', cipherText: 'abc'),
        '{"text":"hello"}',
      );
    }
  });

  test('returns null when the ciphertext changed, which is an edit', () async {
    // An edit re-encrypts under the SAME message id. Keyed on id alone, the
    // store would serve the stale text forever and the edit would silently
    // never appear -- the bug this digest column exists to prevent.
    await store.write(
      threadId: 't1',
      messageId: 'm1',
      cipherText: 'original-ciphertext',
      plaintext: '{"text":"before"}',
    );
    expect(
      await store.read(
        threadId: 't1',
        messageId: 'm1',
        cipherText: 'edited-ciphertext',
      ),
      isNull,
      reason: 'new bytes must force a fresh decrypt',
    );

    await store.write(
      threadId: 't1',
      messageId: 'm1',
      cipherText: 'edited-ciphertext',
      plaintext: '{"text":"after"}',
    );
    expect(
      await store.read(
        threadId: 't1',
        messageId: 'm1',
        cipherText: 'edited-ciphertext',
      ),
      '{"text":"after"}',
    );
    expect(await store.count(), 1, reason: 'an edit replaces, not appends');
  });

  test('stores plaintext sealed, not readable in the file', () async {
    await store.write(
      threadId: 't1',
      messageId: 'm1',
      cipherText: 'abc',
      plaintext: 'meet me at the usual place',
    );
    final raw = (await db.query('messages')).first['plaintext']! as Uint8List;
    expect(
      String.fromCharCodes(raw),
      isNot(contains('usual place')),
      reason: 'the database file must not contain readable message text',
    );
  });

  test('keeps threads separate', () async {
    await store.write(
      threadId: 't1',
      messageId: 'm1',
      cipherText: 'c',
      plaintext: 'one',
    );
    await store.write(
      threadId: 't2',
      messageId: 'm1',
      cipherText: 'c',
      plaintext: 'two',
    );
    expect(
      await store.read(threadId: 't1', messageId: 'm1', cipherText: 'c'),
      'one',
    );
    expect(
      await store.read(threadId: 't2', messageId: 'm1', cipherText: 'c'),
      'two',
    );
  });

  test('deleteThread clears only that conversation', () async {
    // Clearing a chat server-side has to clear here too, or the history
    // comes straight back from local disk on the next read.
    await store.write(
      threadId: 't1',
      messageId: 'm1',
      cipherText: 'c',
      plaintext: 'one',
    );
    await store.write(
      threadId: 't2',
      messageId: 'm1',
      cipherText: 'c',
      plaintext: 'two',
    );

    await store.deleteThread('t1');

    expect(
      await store.read(threadId: 't1', messageId: 'm1', cipherText: 'c'),
      isNull,
    );
    expect(
      await store.read(threadId: 't2', messageId: 'm1', cipherText: 'c'),
      'two',
    );
  });

  test('reads as absent once the device key is destroyed', () async {
    // Sign-out drops the key; the rows survive but are inert.
    final crypto = CryptoBox();
    final scoped = LocalMessageStore(database: db, cryptoBox: crypto);
    await scoped.write(
      threadId: 't1',
      messageId: 'm1',
      cipherText: 'c',
      plaintext: 'previous user history',
    );
    await crypto.destroyLocalDataKey();

    final afterWipe =
        LocalMessageStore(database: db, cryptoBox: CryptoBox());
    expect(
      await afterWipe.read(threadId: 't1', messageId: 'm1', cipherText: 'c'),
      isNull,
    );
  });
}
