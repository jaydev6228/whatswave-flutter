import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatswave/core/crypto/crypto_box.dart';
import 'package:whatswave/features/chats/data/pending_send_store.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';
import 'package:whatswave/features/chats/domain/chat_message.dart';

ChatMessage failedMessage(String id, String text) => ChatMessage(
      id: id,
      senderName: 'You',
      senderUid: 'me',
      sentAt: DateTime(2026, 6, 3, 12),
      isFromCurrentUser: true,
      text: text,
      deliveryState: MessageDeliveryState.failed,
    );

void main() {
  late PendingSendStore store;
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final dir = await Directory.systemTemp.createTemp('ww_pending');
    addTearDown(() => dir.delete(recursive: true));
    db = await PendingSendStore.open(
      path: '${dir.path}/pending.db',
      factory: databaseFactoryFfi,
    );
    store = PendingSendStore(database: db, cryptoBox: CryptoBox());
  });

  test('a failed send survives leaving the conversation', () async {
    // The regression this exists for: _localMessages was State and got
    // cleared on thread change, so the "Not sent" bubble and its retry
    // button disappeared when the user backed out.
    await store.remember(threadId: 't1', message: failedMessage('m1', 'hi'));

    final restored = await store.forThread('t1');
    expect(restored, hasLength(1));
    expect(restored.single.text, 'hi');
    expect(restored.single.deliveryState, MessageDeliveryState.failed);
    expect(restored.single.isFromCurrentUser, isTrue);
  });

  test('keeps attachments so a failed photo can be retried', () async {
    await store.remember(
      threadId: 't1',
      message: ChatMessage(
        id: 'm2',
        senderName: 'You',
        sentAt: DateTime(2026, 6, 3, 12),
        isFromCurrentUser: true,
        text: 'look',
        deliveryState: MessageDeliveryState.failed,
        attachments: const <ChatAttachment>[
          ChatAttachment(
            id: 'a1',
            type: ChatAttachmentType.photo,
            title: 'Photo',
            details: '',
            tintColor: Color(0xFF112233),
            localMediaPath: '/tmp/photo.jpg',
          ),
        ],
      ),
    );

    final restored = (await store.forThread('t1')).single;
    expect(restored.attachments, hasLength(1));
    expect(restored.attachments.single.localMediaPath, '/tmp/photo.jpg');
    expect(restored.attachments.single.type, ChatAttachmentType.photo);
  });

  test('returns them oldest first', () async {
    for (var i = 0; i < 3; i++) {
      await store.remember(
        threadId: 't1',
        message: ChatMessage(
          id: 'm$i',
          senderName: 'You',
          sentAt: DateTime(2026, 6, 3, 12, i),
          isFromCurrentUser: true,
          text: 'message $i',
          deliveryState: MessageDeliveryState.failed,
        ),
      );
    }
    expect(
      (await store.forThread('t1')).map((m) => m.text).toList(),
      <String>['message 0', 'message 1', 'message 2'],
    );
  });

  test('forgetting one leaves the others', () async {
    await store.remember(threadId: 't1', message: failedMessage('m1', 'one'));
    await store.remember(threadId: 't1', message: failedMessage('m2', 'two'));

    await store.forget(threadId: 't1', messageId: 'm1');

    final left = await store.forThread('t1');
    expect(left, hasLength(1));
    expect(left.single.text, 'two');
  });

  test('keeps threads apart', () async {
    await store.remember(threadId: 't1', message: failedMessage('m1', 'one'));
    await store.remember(threadId: 't2', message: failedMessage('m1', 'two'));
    expect((await store.forThread('t1')).single.text, 'one');
    expect((await store.forThread('t2')).single.text, 'two');

    await store.forgetThread('t1');
    expect(await store.forThread('t1'), isEmpty);
    expect(await store.forThread('t2'), hasLength(1));
  });

  test('stores the payload sealed, not readable in the file', () async {
    await store.remember(
      threadId: 't1',
      message: failedMessage('m1', 'unsent but private'),
    );
    final raw = (await db.query('pending_sends')).first['payload']! as Uint8List;
    expect(
      String.fromCharCodes(raw),
      isNot(contains('unsent but private')),
      reason: 'an unsent message is still message content',
    );
  });

  test('skips entries it can no longer decrypt', () async {
    // Sign-out destroys the device key. The rows may outlive it; they must
    // not break the next account's conversation load.
    final crypto = CryptoBox();
    final scoped = PendingSendStore(database: db, cryptoBox: crypto);
    await scoped.remember(
      threadId: 't1',
      message: failedMessage('m1', 'previous user'),
    );
    await crypto.destroyLocalDataKey();

    final afterWipe = PendingSendStore(database: db, cryptoBox: CryptoBox());
    expect(await afterWipe.forThread('t1'), isEmpty);
  });
}
