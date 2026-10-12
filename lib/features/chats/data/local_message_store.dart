import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/crypto/crypto_box.dart';

/// Decrypted message content, kept on this device.
///
/// Not a cache -- a requirement. A Signal ciphertext decrypts exactly once:
/// `SessionCipher.decrypt` advances the ratchet and consumes the message
/// key, and a second attempt throws. The app re-reads the same message
/// document constantly (every `watchThreads` snapshot, every page back
/// through history, the starred-messages collection-group query, every cold
/// start), so without somewhere to keep the plaintext the second read of any
/// message would fail. Decrypt once on first sight, serve every later read
/// from here.
///
/// Rows are sealed with the device-local key, so the database file is
/// useless to anything that lifts it off the device, and dropping that key
/// on sign-out makes the whole store unreadable in one step.
class LocalMessageStore {
  LocalMessageStore({required Database database, required CryptoBox cryptoBox})
      : _db = database,
        _crypto = cryptoBox;

  final Database _db;
  final CryptoBox _crypto;

  static Future<Database> open({
    required String path,
    DatabaseFactory? factory,
  }) {
    final openDb = factory?.openDatabase ?? openDatabase;
    return openDb(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE messages ('
            'thread_id TEXT NOT NULL, '
            'message_id TEXT NOT NULL, '
            // Digest of the ciphertext this plaintext came from. An edit
            // re-encrypts under the SAME message id, so a store keyed on id
            // alone would keep serving the pre-edit text forever and the
            // edit would silently never appear.
            'cipher_digest TEXT NOT NULL, '
            'plaintext BLOB NOT NULL, '
            'PRIMARY KEY (thread_id, message_id))',
          );
          await db.execute(
            'CREATE INDEX messages_thread ON messages (thread_id)',
          );
        },
      ),
    );
  }

  /// A stable digest of the ciphertext, used to notice re-encryption.
  static String digestOf(String cipherText) =>
      sha256.convert(utf8.encode(cipherText)).toString();

  /// The stored plaintext for this message, or null when there is none for
  /// *this* ciphertext -- either never seen, or re-encrypted since.
  Future<String?> read({
    required String threadId,
    required String messageId,
    required String cipherText,
  }) async {
    final rows = await _db.query(
      'messages',
      columns: <String>['cipher_digest', 'plaintext'],
      where: 'thread_id = ? AND message_id = ?',
      whereArgs: <Object?>[threadId, messageId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    if (rows.first['cipher_digest'] != digestOf(cipherText)) {
      // Same message id, different bytes: an edit. The new ciphertext is a
      // fresh ratchet step whose key has not been consumed, so the caller
      // can and must decrypt it.
      return null;
    }
    final sealed = rows.first['plaintext'];
    if (sealed is! Uint8List) {
      return null;
    }
    try {
      return utf8.decode(await _crypto.open(sealed));
    } on CryptoBoxException {
      // Sealed under a key we no longer have (a restore, or a wipe that was
      // interrupted). Treat as absent rather than failing the read -- worst
      // case the message shows as undecryptable, which is recoverable.
      return null;
    }
  }

  Future<void> write({
    required String threadId,
    required String messageId,
    required String cipherText,
    required String plaintext,
  }) async {
    await _db.insert(
      'messages',
      <String, Object?>{
        'thread_id': threadId,
        'message_id': messageId,
        'cipher_digest': digestOf(cipherText),
        'plaintext':
            await _crypto.seal(Uint8List.fromList(utf8.encode(plaintext))),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Clears one conversation. Pairs with clearing a chat server-side --
  /// without this the history reappears from local disk on the next read.
  Future<void> deleteThread(String threadId) async {
    await _db.delete(
      'messages',
      where: 'thread_id = ?',
      whereArgs: <Object?>[threadId],
    );
  }

  Future<void> deleteMessage({
    required String threadId,
    required String messageId,
  }) async {
    await _db.delete(
      'messages',
      where: 'thread_id = ? AND message_id = ?',
      whereArgs: <Object?>[threadId, messageId],
    );
  }

  Future<int> count() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM messages'),
      ) ??
      0;

  Future<void> wipe() async => _db.delete('messages');
}
