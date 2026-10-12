import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatswave/core/crypto/crypto_box.dart';
import 'package:whatswave/core/crypto/message_crypto.dart';
import 'package:whatswave/core/crypto/sender_key_distributor.dart';
import 'package:whatswave/core/crypto/signal_identity_service.dart';
import 'package:whatswave/core/crypto/signal_store.dart';
import 'package:whatswave/core/media/media_transfer.dart';
import 'package:whatswave/core/media/media_uploader.dart';
import 'package:whatswave/features/chats/data/firestore_chat_repository.dart';
import 'package:whatswave/features/chats/data/local_message_store.dart';

late FakeFirebaseFirestore firestore;

/// One signed-in install, with its own keys and its own repository.
Future<FirestoreChatRepository> buildRepository(String uid) async {
  final dir = await Directory.systemTemp.createTemp('ww_enc_$uid');
  addTearDown(() => dir.delete(recursive: true));

  final box = CryptoBox();
  final store = WhatsWaveSignalStore(
    database: await WhatsWaveSignalStore.openDatabase_(
      path: '${dir.path}/signal.db',
      factory: databaseFactoryFfi,
    ),
    cryptoBox: box,
    keyNamespace: uid,
  );
  final identity = SignalIdentityService(
    store: store,
    firestore: firestore,
    currentUid: () => uid,
  );
  await identity.ensureIdentity();

  return FirestoreChatRepository(
    firestore: firestore,
    // The default is a FirebaseMediaUploader, which resolves
    // FirebaseStorage.instance at construction and needs a live Firebase
    // app. Nothing here uploads, so stub it rather than standing one up.
    mediaUploader: _UnusedMediaUploader(),
    firebaseAuth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, displayName: uid),
    ),
    messageCrypto: SignalMessageCrypto(
      senderKeys: SenderKeyDistributor(
        store: store,
        identityService: identity,
        currentUid: () => uid,
        firestore: firestore,
      ),
      store: store,
      identityService: identity,
      localMessages: LocalMessageStore(
        database: await LocalMessageStore.open(
          path: '${dir.path}/messages.db',
          factory: databaseFactoryFfi,
        ),
        cryptoBox: box,
      ),
      currentUid: () => uid,
    ),
  );
}

Future<void> seedThread(List<String> participants) =>
    firestore.collection('chatThreads').doc('t1').set(<String, Object?>{
      'participantUids': participants,
      'isGroup': participants.length > 2,
      'unreadCounts': <String, Object?>{for (final p in participants) p: 0},
    });

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    firestore = FakeFirebaseFirestore();
  });

  test('a 1:1 send writes ciphertext, and the peer reads it back', () async {
    final alice = await buildRepository('alice');
    final bob = await buildRepository('bob');
    await seedThread(<String>['alice', 'bob']);

    await alice.sendTextMessage(threadId: 't1', text: 'the eagle lands at six');

    // What actually sits in Firestore.
    final stored = (await firestore
            .collection('chatThreads')
            .doc('t1')
            .collection('messages')
            .get())
        .docs
        .single
        .data();

    expect(stored['schemaVersion'], 2);
    expect(stored['text'], isNot(contains('eagle')));
    expect(stored['attachments'], isEmpty,
        reason: 'v2 keeps attachments inside the sealed payload');
    expect(stored['senderUid'], 'alice',
        reason: 'metadata stays plaintext, by design');

    // And the recipient gets the real thing.
    final thread = await bob.fetchThreadWithMessages('t1');
    expect(thread.messages.single.text, 'the eagle lands at six');
    expect(thread.messages.single.isUndecryptable, isFalse);
  });

  test('the sender reads their own message back', () async {
    final alice = await buildRepository('alice');
    await buildRepository('bob');
    await seedThread(<String>['alice', 'bob']);

    await alice.sendTextMessage(threadId: 't1', text: 'my own words');

    final thread = await alice.fetchThreadWithMessages('t1');
    expect(thread.messages.single.text, 'my own words');
  });

  test('an outsider sees an undecryptable placeholder, not the text',
      () async {
    final alice = await buildRepository('alice');
    await buildRepository('bob');
    final eve = await buildRepository('eve');
    await seedThread(<String>['alice', 'bob', 'eve']);
    // Force the 1:1 path even though eve is in the roster, by sealing to a
    // two-person thread and then having eve read it.
    await firestore.collection('chatThreads').doc('t1').update(
      <String, Object?>{'participantUids': <String>['alice', 'bob']},
    );

    await alice.sendTextMessage(threadId: 't1', text: 'not for eve');

    await firestore.collection('chatThreads').doc('t1').update(
      <String, Object?>{'participantUids': <String>['alice', 'bob', 'eve']},
    );
    final thread = await eve.fetchThreadWithMessages('t1');
    expect(thread.messages.single.text, isEmpty);
    expect(thread.messages.single.isUndecryptable, isTrue);
  });

  test('a legacy plaintext message still renders', () async {
    // No backfill, no migration: documents written before encryption
    // existed have no schemaVersion and are read exactly as before.
    final bob = await buildRepository('bob');
    await seedThread(<String>['alice', 'bob']);
    await firestore
        .collection('chatThreads')
        .doc('t1')
        .collection('messages')
        .doc('legacy')
        .set(<String, Object?>{
      'senderUid': 'alice',
      'senderName': 'Alice',
      'text': 'written before encryption',
      'attachments': <Object?>[],
      'deliveryState': 'delivered',
    });

    final thread = await bob.fetchThreadWithMessages('t1');
    expect(thread.messages.single.text, 'written before encryption');
    expect(thread.messages.single.isUndecryptable, isFalse);
  });

  test('v1 and v2 messages coexist in one thread', () async {
    final alice = await buildRepository('alice');
    final bob = await buildRepository('bob');
    await seedThread(<String>['alice', 'bob']);

    await firestore
        .collection('chatThreads')
        .doc('t1')
        .collection('messages')
        .doc('a-legacy')
        .set(<String, Object?>{
      'senderUid': 'alice',
      'senderName': 'Alice',
      'text': 'old message',
      'attachments': <Object?>[],
      'sentAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
    await alice.sendTextMessage(threadId: 't1', text: 'new message');

    final thread = await bob.fetchThreadWithMessages('t1');
    expect(
      thread.messages.map((m) => m.text).toList(),
      containsAll(<String>['old message', 'new message']),
    );
  });

  test('a group message is encrypted and every member can read it',
      () async {
    // This is the test that would have caught sender keys being built but
    // never wired: the unit tests distributed keys by hand, so they passed
    // while the real send path was silently writing plaintext.
    final alice = await buildRepository('alice');
    final bob = await buildRepository('bob');
    final carol = await buildRepository('carol');
    await seedThread(<String>['alice', 'bob', 'carol']);

    await alice.sendTextMessage(threadId: 't1', text: 'group hello');

    final stored = (await firestore
            .collection('chatThreads')
            .doc('t1')
            .collection('messages')
            .get())
        .docs
        .single
        .data();
    expect(stored['schemaVersion'], 2,
        reason: 'a group send must not fall back to plaintext');
    expect(stored['text'], isNot(contains('group hello')));

    // The sender key rode along in the same batch, so each member can
    // drain it and read the message.
    for (final member in <FirestoreChatRepository>[bob, carol]) {
      final thread = await member.fetchThreadWithMessages('t1');
      expect(thread.messages.single.text, 'group hello');
    }
  });

  test('a group send hands out sender keys in the same write', () async {
    final alice = await buildRepository('alice');
    await buildRepository('bob');
    await buildRepository('carol');
    await seedThread(<String>['alice', 'bob', 'carol']);

    await alice.sendTextMessage(threadId: 't1', text: 'hello');

    for (final recipient in <String>['bob', 'carol']) {
      final inbox = await firestore
          .collection('signalKeyDeliveries')
          .doc(recipient)
          .collection('inbox')
          .get();
      expect(inbox.docs, isNotEmpty,
          reason: '$recipient should have been sent a sender key');
      expect(inbox.docs.first.data()['senderUid'], 'alice');
    }
  });

  test('the sealed payload hides attachment metadata too', () async {
    final alice = await buildRepository('alice');
    final bob = await buildRepository('bob');
    await seedThread(<String>['alice', 'bob']);

    await alice.sendTextMessage(threadId: 't1', text: 'see attached');
    final stored = (await firestore
            .collection('chatThreads')
            .doc('t1')
            .collection('messages')
            .get())
        .docs
        .single
        .data();

    // The envelope is opaque JSON of {t, b} -- no payload field leaks.
    final envelope = jsonDecode(stored['text']! as String)
        as Map<String, dynamic>;
    expect(envelope.keys.toSet(), <String>{'t', 'b'});

    final thread = await bob.fetchThreadWithMessages('t1');
    expect(thread.messages.single.text, 'see attached');
  });
}

class _UnusedMediaUploader implements MediaUploader {
  @override
  Future<String> uploadFile(
    File file, {
    required String storagePath,
    String? contentType,
    MediaTransfer? transfer,
    String transferSlot = 'file',
  }) async =>
      throw UnsupportedError('These tests send text only.');
}
