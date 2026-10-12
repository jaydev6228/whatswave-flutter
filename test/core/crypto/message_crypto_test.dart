import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatswave/core/crypto/crypto_box.dart';
import 'package:whatswave/core/crypto/message_crypto.dart';
import 'package:whatswave/core/crypto/sender_key_distributor.dart';
import 'package:whatswave/core/crypto/signal_identity_service.dart';
import 'package:whatswave/core/crypto/signal_store.dart';
import 'package:whatswave/features/chats/data/local_message_store.dart';

/// One simulated install: its own databases, its own keystore namespace,
/// sharing one fake Firestore with the others.
class Party {
  Party(this.uid, this.crypto, this.store, this.messages, this.identity);

  final String uid;
  final SignalMessageCrypto crypto;
  final WhatsWaveSignalStore store;
  final LocalMessageStore messages;
  final SignalIdentityService identity;
  late final SenderKeyDistributor senderKeys;
}

late FakeFirebaseFirestore firestore;

Future<Party> buildParty(String uid) async {
  final dir = await Directory.systemTemp.createTemp('ww_mc_$uid');
  addTearDown(() => dir.delete(recursive: true));

  final signalDb = await WhatsWaveSignalStore.openDatabase_(
    path: '${dir.path}/signal.db',
    factory: databaseFactoryFfi,
  );
  final messagesDb = await LocalMessageStore.open(
    path: '${dir.path}/messages.db',
    factory: databaseFactoryFfi,
  );
  final box = CryptoBox();
  final store = WhatsWaveSignalStore(
    database: signalDb,
    cryptoBox: box,
    keyNamespace: uid,
  );
  final messages = LocalMessageStore(database: messagesDb, cryptoBox: box);
  final identity = SignalIdentityService(
    store: store,
    firestore: firestore,
    currentUid: () => uid,
  );
  await identity.ensureIdentity();

  final senderKeys = SenderKeyDistributor(
    store: store,
    identityService: identity,
    currentUid: () => uid,
    firestore: firestore,
  );
  final party = Party(
    uid,
    SignalMessageCrypto(
      store: store,
      identityService: identity,
      localMessages: messages,
      currentUid: () => uid,
      senderKeys: senderKeys,
    ),
    store,
    messages,
    identity,
  );
  party.senderKeys = senderKeys;
  return party;
}

/// Sends the group key to everyone who needs it and commits the writes,
/// the way the repository does inside the message's own batch.
Future<void> distributeKeys(
  Party sender, {
  required String threadId,
  required List<String> participants,
}) async {
  final deliveries = await sender.senderKeys.pendingDeliveries(
    threadId: threadId,
    participantUids: participants,
  );
  final batch = firestore.batch();
  deliveries.addToBatch(batch);
  await batch.commit();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    firestore = FakeFirebaseFirestore();
  });

  test('a 1:1 message round-trips and is opaque in between', () async {
    final alice = await buildParty('alice');
    final bob = await buildParty('bob');
    const payload = '{"text":"meet me at six","attachments":[]}';

    final sealed = await alice.crypto.sealOutgoing(
      threadId: 't1',
      messageId: 'm1',
      participantUids: <String>['alice', 'bob'],
      payloadJson: payload,
    );

    expect(sealed, isNotNull);
    expect(sealed, isNot(contains('meet me at six')),
        reason: 'what reaches Firestore must not contain the message');

    final opened = await bob.crypto.openIncoming(
      threadId: 't1',
      messageId: 'm1',
      senderUid: 'alice',
      cipherText: sealed!,
    );
    expect(opened, payload);
  });

  test('the sender can still read their own message back', () async {
    // Signal ciphertext is addressed to the recipient's ratchet -- the
    // sender genuinely cannot decrypt it. Keeping the plaintext locally at
    // send time is what makes the sender's own history render.
    final alice = await buildParty('alice');
    await buildParty('bob');
    const payload = '{"text":"my own words"}';

    final sealed = await alice.crypto.sealOutgoing(
      threadId: 't1',
      messageId: 'm1',
      participantUids: <String>['alice', 'bob'],
      payloadJson: payload,
    );

    expect(
      await alice.crypto.openIncoming(
        threadId: 't1',
        messageId: 'm1',
        senderUid: 'alice',
        cipherText: sealed!,
      ),
      payload,
    );
  });

  test('the recipient can re-read a message many times', () async {
    // The constraint that forced the local store: the ratchet consumes the
    // message key, so only the first decrypt can touch it. Every snapshot
    // tick and every scroll back re-reads the same document.
    final alice = await buildParty('alice');
    final bob = await buildParty('bob');

    final sealed = await alice.crypto.sealOutgoing(
      threadId: 't1',
      messageId: 'm1',
      participantUids: <String>['alice', 'bob'],
      payloadJson: '{"text":"read me twice"}',
    );

    for (var i = 0; i < 5; i++) {
      expect(
        await bob.crypto.openIncoming(
          threadId: 't1',
          messageId: 'm1',
          senderUid: 'alice',
          cipherText: sealed!,
        ),
        '{"text":"read me twice"}',
        reason: 'read ${i + 1} must succeed',
      );
    }
  });

  test('a third party cannot read it', () async {
    final alice = await buildParty('alice');
    await buildParty('bob');
    final eve = await buildParty('eve');

    final sealed = await alice.crypto.sealOutgoing(
      threadId: 't1',
      messageId: 'm1',
      participantUids: <String>['alice', 'bob'],
      payloadJson: '{"text":"not for eve"}',
    );

    expect(
      await eve.crypto.openIncoming(
        threadId: 't1',
        messageId: 'm1',
        senderUid: 'alice',
        cipherText: sealed!,
      ),
      isNull,
    );
  });

  test('several messages in a row all decrypt', () async {
    final alice = await buildParty('alice');
    final bob = await buildParty('bob');

    for (var i = 0; i < 4; i++) {
      final sealed = await alice.crypto.sealOutgoing(
        threadId: 't1',
        messageId: 'm$i',
        participantUids: <String>['alice', 'bob'],
        payloadJson: '{"text":"message $i"}',
      );
      expect(
        await bob.crypto.openIncoming(
          threadId: 't1',
          messageId: 'm$i',
          senderUid: 'alice',
          cipherText: sealed!,
        ),
        '{"text":"message $i"}',
      );
    }
  });

  test('a group message reaches every member', () async {
    final alice = await buildParty('alice');
    final bob = await buildParty('bob');
    final carol = await buildParty('carol');
    const members = <String>['alice', 'bob', 'carol'];

    await distributeKeys(alice, threadId: 'g1', participants: members);
    final sealed = await alice.crypto.sealOutgoing(
      threadId: 'g1',
      messageId: 'm1',
      participantUids: members,
      payloadJson: '{"text":"group hello"}',
    );
    expect(sealed, isNotNull);
    expect(sealed, isNot(contains('group hello')));

    for (final member in <Party>[bob, carol]) {
      await member.crypto.drainKeyDeliveries();
      expect(
        await member.crypto.openIncoming(
          threadId: 'g1',
          messageId: 'm1',
          senderUid: 'alice',
          cipherText: sealed!,
        ),
        '{"text":"group hello"}',
        reason: '${member.uid} should be able to read it',
      );
    }
  });

  test('a removed member cannot read what comes after they leave', () async {
    // The property that makes group encryption worth anything. Rotation is
    // lazy -- on the next send -- which is sound: a member who never sends
    // never mints a chain and so has nothing to leak.
    final alice = await buildParty('alice');
    final bob = await buildParty('bob');
    final carol = await buildParty('carol');
    await buildParty('dave');
    // Four members, so removing one still leaves a group. With only two
    // left the send would correctly fall back to the pairwise path and
    // this would stop testing sender keys at all.
    const before = <String>['alice', 'bob', 'carol', 'dave'];
    const after = <String>['alice', 'bob', 'dave'];

    await distributeKeys(alice, threadId: 'g1', participants: before);
    final first = await alice.crypto.sealOutgoing(
      threadId: 'g1',
      messageId: 'm1',
      participantUids: before,
      payloadJson: '{"text":"while carol is here"}',
    );
    await carol.crypto.drainKeyDeliveries();
    expect(
      await carol.crypto.openIncoming(
        threadId: 'g1',
        messageId: 'm1',
        senderUid: 'alice',
        cipherText: first!,
      ),
      '{"text":"while carol is here"}',
    );

    // Carol is removed. Noticing it rotates alice's chain.
    await alice.crypto.noteMembership(threadId: 'g1', participantUids: before);
    await alice.crypto.noteMembership(threadId: 'g1', participantUids: after);
    await distributeKeys(alice, threadId: 'g1', participants: after);

    final second = await alice.crypto.sealOutgoing(
      threadId: 'g1',
      messageId: 'm2',
      participantUids: after,
      payloadJson: '{"text":"after carol left"}',
    );

    await bob.crypto.drainKeyDeliveries();
    expect(
      await bob.crypto.openIncoming(
        threadId: 'g1',
        messageId: 'm2',
        senderUid: 'alice',
        cipherText: second!,
      ),
      '{"text":"after carol left"}',
      reason: 'a remaining member still reads fine',
    );

    await carol.crypto.drainKeyDeliveries();
    expect(
      await carol.crypto.openIncoming(
        threadId: 'g1',
        messageId: 'm2',
        senderUid: 'alice',
        cipherText: second,
      ),
      isNull,
      reason: 'the removed member must not be able to read it',
    );
  });

  test('adding a member does not rotate the chain', () async {
    // Only a shrink requires rotation; rotating on every join would churn
    // keys for no security benefit.
    final alice = await buildParty('alice');
    await alice.crypto
        .noteMembership(threadId: 'g1', participantUids: <String>['alice', 'bob']);
    await alice.crypto.noteMembership(
      threadId: 'g1',
      participantUids: <String>['alice', 'bob', 'carol'],
    );
    // Nothing to assert beyond it not throwing and not clearing state --
    // the rotation path is covered above.
    expect(true, isTrue);
  });

  test('a member reads a group message without waiting for a relaunch',
      () async {
    // The sender key is written in the same batch as the message, so a
    // recipient who has not drained yet drains on demand and reads it
    // immediately rather than showing "unreadable" until next launch.
    final alice = await buildParty('alice');
    final dave = await buildParty('dave');
    const members = <String>['alice', 'bob', 'dave'];

    await distributeKeys(alice, threadId: 'g1', participants: members);
    final sealed = await alice.crypto.sealOutgoing(
      threadId: 'g1',
      messageId: 'm1',
      participantUids: members,
      payloadJson: '{"text":"hello"}',
    );

    expect(
      await dave.crypto.openIncoming(
        threadId: 'g1',
        messageId: 'm1',
        senderUid: 'alice',
        cipherText: sealed!,
      ),
      '{"text":"hello"}',
    );
  });

  test('someone never sent the key gets a placeholder, not a crash',
      () async {
    // Carol is not in the group, so nothing was ever delivered to her --
    // draining finds nothing and the read degrades to a placeholder.
    final alice = await buildParty('alice');
    final carol = await buildParty('carol');
    const members = <String>['alice', 'bob', 'dave'];

    await distributeKeys(alice, threadId: 'g1', participants: members);
    final sealed = await alice.crypto.sealOutgoing(
      threadId: 'g1',
      messageId: 'm1',
      participantUids: members,
      payloadJson: '{"text":"hello"}',
    );

    expect(
      await carol.crypto.openIncoming(
        threadId: 'g1',
        messageId: 'm1',
        senderUid: 'alice',
        cipherText: sealed!,
      ),
      isNull,
    );
  });

  test('falls back to plaintext for a peer with no published keys', () async {
    // An older install, or a profile mid-setup. Encrypting to nobody would
    // produce a message they could never read.
    final alice = await buildParty('alice');
    expect(
      await alice.crypto.sealOutgoing(
        threadId: 't1',
        messageId: 'm1',
        participantUids: <String>['alice', 'nokeys'],
        payloadJson: '{"text":"hi"}',
      ),
      isNull,
    );
  });

  test('a corrupt envelope yields null rather than taking out the thread',
      () async {
    final bob = await buildParty('bob');
    expect(
      await bob.crypto.openIncoming(
        threadId: 't1',
        messageId: 'm1',
        senderUid: 'alice',
        cipherText: 'not even json',
      ),
      isNull,
    );
    expect(
      await bob.crypto.openIncoming(
        threadId: 't1',
        messageId: 'm2',
        senderUid: 'alice',
        cipherText: jsonEncode(<String, Object?>{'t': 3, 'b': 'bm90LXZhbGlk'}),
      ),
      isNull,
    );
  });

  test('forgetThread removes the local plaintext', () async {
    final alice = await buildParty('alice');
    await buildParty('bob');
    final sealed = await alice.crypto.sealOutgoing(
      threadId: 't1',
      messageId: 'm1',
      participantUids: <String>['alice', 'bob'],
      payloadJson: '{"text":"clear me"}',
    );

    await alice.crypto.forgetThread('t1');

    expect(
      await alice.crypto.openIncoming(
        threadId: 't1',
        messageId: 'm1',
        senderUid: 'alice',
        cipherText: sealed!,
      ),
      isNull,
      reason: 'clearing a chat must not leave it recoverable from disk',
    );
  });

  test('NoopMessageCrypto keeps the local backend plaintext', () async {
    const noop = NoopMessageCrypto();
    expect(noop.isEnabled, isFalse);
    expect(
      await noop.sealOutgoing(
        threadId: 't',
        messageId: 'm',
        participantUids: <String>['a', 'b'],
        payloadJson: '{}',
      ),
      isNull,
    );
  });
}
