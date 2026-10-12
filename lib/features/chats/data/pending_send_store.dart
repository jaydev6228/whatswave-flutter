import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:sqflite/sqflite.dart';

import '../../../core/crypto/crypto_box.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_message.dart';

/// Outgoing messages that have not made it to the server.
///
/// Before this, a failed send lived only in the conversation screen's
/// `State` and was cleared on thread change -- so backing out of a chat
/// threw away the "Not sent" bubble and the retry button with it. The write
/// may still have been queued by Firestore, so the user was left with no
/// record either way, which is the worst of both.
///
/// Sealed with the device-local key, like every other store here: a pending
/// message is message content that has not been sent yet, not metadata.
class PendingSendStore {
  PendingSendStore({required Database database, required CryptoBox cryptoBox})
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
            'CREATE TABLE pending_sends ('
            'thread_id TEXT NOT NULL, '
            'message_id TEXT NOT NULL, '
            'queued_at INTEGER NOT NULL, '
            'payload BLOB NOT NULL, '
            'PRIMARY KEY (thread_id, message_id))',
          );
          await db.execute(
            'CREATE INDEX pending_thread ON pending_sends (thread_id)',
          );
        },
      ),
    );
  }

  Future<void> remember({
    required String threadId,
    required ChatMessage message,
  }) async {
    await _db.insert(
      'pending_sends',
      <String, Object?>{
        'thread_id': threadId,
        'message_id': message.id,
        'queued_at': message.sentAt.millisecondsSinceEpoch,
        'payload': await _crypto
            .seal(Uint8List.fromList(utf8.encode(jsonEncode(_toJson(message))))),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Oldest first, so they re-render in the order they were written.
  Future<List<ChatMessage>> forThread(String threadId) async {
    final rows = await _db.query(
      'pending_sends',
      where: 'thread_id = ?',
      whereArgs: <Object?>[threadId],
      orderBy: 'queued_at ASC',
    );
    final messages = <ChatMessage>[];
    for (final row in rows) {
      try {
        final payload = row['payload'];
        if (payload is! Uint8List) {
          continue;
        }
        messages.add(
          _fromJson(
            jsonDecode(utf8.decode(await _crypto.open(payload)))
                as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        // Unreadable (sealed under a destroyed key, or corrupt). Skipping
        // beats failing the whole conversation load.
        continue;
      }
    }
    return messages;
  }

  Future<void> forget({
    required String threadId,
    required String messageId,
  }) async {
    await _db.delete(
      'pending_sends',
      where: 'thread_id = ? AND message_id = ?',
      whereArgs: <Object?>[threadId, messageId],
    );
  }

  Future<void> forgetThread(String threadId) async {
    await _db.delete(
      'pending_sends',
      where: 'thread_id = ?',
      whereArgs: <Object?>[threadId],
    );
  }

  Future<void> wipe() async => _db.delete('pending_sends');

  // Only what is needed to re-render the bubble and retry the send. A
  // pending message has no reactions, no stars and no read state yet.
  Map<String, Object?> _toJson(ChatMessage message) => <String, Object?>{
        'id': message.id,
        'senderName': message.senderName,
        'senderUid': message.senderUid,
        'sentAtMs': message.sentAt.millisecondsSinceEpoch,
        'text': message.text,
        'deliveryState': message.deliveryState.name,
        'attachments': message.attachments
            .map(
              (a) => <String, Object?>{
                'id': a.id,
                'type': a.type.name,
                'title': a.title,
                'details': a.details,
                'tintColorArgb': a.tintColor.toARGB32(),
                'aspectRatio': a.aspectRatio,
                'latitude': a.latitude,
                'longitude': a.longitude,
                'localMediaPath': a.localMediaPath,
              },
            )
            .toList(growable: false),
      };

  ChatMessage _fromJson(Map<String, dynamic> map) => ChatMessage(
        id: (map['id'] as String?) ?? '',
        senderName: (map['senderName'] as String?) ?? '',
        senderUid: map['senderUid'] as String?,
        sentAt: DateTime.fromMillisecondsSinceEpoch(
          (map['sentAtMs'] as num?)?.toInt() ?? 0,
        ),
        isFromCurrentUser: true,
        text: (map['text'] as String?) ?? '',
        deliveryState: MessageDeliveryState.values.firstWhere(
          (state) => state.name == map['deliveryState'],
          orElse: () => MessageDeliveryState.failed,
        ),
        attachments: ((map['attachments'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(
              (a) => ChatAttachment(
                id: (a['id'] as String?) ?? '',
                type: ChatAttachmentType.values.firstWhere(
                  (type) => type.name == a['type'],
                  orElse: () => ChatAttachmentType.file,
                ),
                title: (a['title'] as String?) ?? '',
                details: (a['details'] as String?) ?? '',
                tintColor: Color((a['tintColorArgb'] as int?) ?? 0xFF000000),
                aspectRatio: (a['aspectRatio'] as num?)?.toDouble() ?? 1.25,
                latitude: (a['latitude'] as num?)?.toDouble(),
                longitude: (a['longitude'] as num?)?.toDouble(),
                localMediaPath: a['localMediaPath'] as String?,
              ),
            )
            .toList(growable: false),
      );
}
