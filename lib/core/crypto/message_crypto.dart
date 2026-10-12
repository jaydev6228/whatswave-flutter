import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../../features/chats/data/local_message_store.dart';
import 'sender_key_distributor.dart';
import 'signal_identity_service.dart';
import 'signal_store.dart';

/// Turns a message payload into something safe to hand Firestore, and back.
///
/// The interface exists because the local/seeded backend must stay
/// plaintext -- it has no Firebase, no peers and no keys -- and because
/// every widget test in this project runs against that backend.
abstract class MessageCrypto {
  /// Whether messages written through this are encrypted at all.
  bool get isEnabled;

  /// Whether a message to these participants will actually be sealed.
  ///
  /// Must be consulted before encrypting an attachment's bytes. When a
  /// message falls back to plaintext the whole attachment map -- including
  /// the media key -- is written to Firestore in the clear, so encrypting
  /// the bytes anyway would publish the ciphertext and its key side by
  /// side. That is strictly worse than not encrypting: it looks protected
  /// and is not.
  bool canSeal(List<String> participantUids);

  /// Seals [payloadJson] for the other participants.
  ///
  /// Returns null when this thread is not encrypted, which tells the caller
  /// to write a plaintext (schema v1) document instead. Also records the
  /// plaintext locally: a Signal ciphertext is readable only by its
  /// recipient, so without this the sender could not read their own sent
  /// message back.
  Future<String?> sealOutgoing({
    required String threadId,
    required String messageId,
    required List<String> participantUids,
    required String payloadJson,
  });

  /// The plaintext payload for a stored message, or null when it cannot be
  /// read on this device.
  Future<String?> openIncoming({
    required String threadId,
    required String messageId,
    required String senderUid,
    required String cipherText,
  });

  /// Drops local plaintext for a thread, so clearing a chat does not leave
  /// the history recoverable from disk.
  Future<void> forgetThread(String threadId);

  /// Key deliveries this send should carry, committed in the message's own
  /// batch so distribution costs no extra round trip.
  ///
  /// Also the point where a shrunken membership rotates this device's
  /// sending chain: it runs immediately before the encrypt, which closes
  /// the window where a removed member could still read one more message.
  Future<List<PendingKeyDelivery>> prepareGroupSend({
    required String threadId,
    required List<String> participantUids,
  });
}

/// The plaintext pass-through used by the seeded local backend and tests.
class NoopMessageCrypto implements MessageCrypto {
  const NoopMessageCrypto();

  @override
  bool get isEnabled => false;

  @override
  bool canSeal(List<String> participantUids) => false;

  @override
  Future<List<PendingKeyDelivery>> prepareGroupSend({
    required String threadId,
    required List<String> participantUids,
  }) async =>
      const <PendingKeyDelivery>[];

  @override
  Future<String?> sealOutgoing({
    required String threadId,
    required String messageId,
    required List<String> participantUids,
    required String payloadJson,
  }) async =>
      null;

  @override
  Future<String?> openIncoming({
    required String threadId,
    required String messageId,
    required String senderUid,
    required String cipherText,
  }) async =>
      null;

  @override
  Future<void> forgetThread(String threadId) async {}
}

/// Signal-backed [MessageCrypto].
///
/// 1:1 threads use a pairwise Double Ratchet session. Group threads use a
/// sender key: one chain per member per group, distributed to the others
/// over their pairwise sessions, which is what keeps a group send O(1) in
/// ciphertexts rather than one per recipient.
class SignalMessageCrypto implements MessageCrypto {
  SignalMessageCrypto({
    required WhatsWaveSignalStore store,
    required SignalIdentityService identityService,
    required LocalMessageStore localMessages,
    required String Function() currentUid,
    SenderKeyDistributor? senderKeys,
  })  : _store = store,
        _identityService = identityService,
        _localMessages = localMessages,
        _currentUid = currentUid,
        _senderKeys = senderKeys;

  final WhatsWaveSignalStore _store;
  final SignalIdentityService _identityService;
  final LocalMessageStore _localMessages;
  final String Function() _currentUid;

  /// Null leaves group threads on plaintext -- used where no distribution
  /// transport exists.
  final SenderKeyDistributor? _senderKeys;

  /// Members this device has already sent its sending key to, per thread.
  /// Kept in memory only: the cost of re-sending after a restart is one
  /// extra write, and the cost of wrongly believing somebody has the key
  /// is a message they cannot read.
  final Map<String, Set<String>> _distributedTo = <String, Set<String>>{};

  @override
  bool get isEnabled => true;

  @override
  bool canSeal(List<String> participantUids) {
    final others =
        participantUids.where((uid) => uid != _currentUid()).toList();
    if (others.isEmpty) {
      return false;
    }
    // Mirrors sealOutgoing's own branching: pairwise always, groups only
    // once there is a way to distribute sender keys. It cannot account for
    // a peer who has published no keys -- that is only discoverable by
    // asking the server -- so media for such a peer is encrypted and then
    // written alongside its key. Narrow enough to accept, and it closes
    // the moment they publish.
    return others.length == 1 || _senderKeys != null;
  }

  @override
  Future<String?> sealOutgoing({
    required String threadId,
    required String messageId,
    required List<String> participantUids,
    required String payloadJson,
  }) async {
    final me = _currentUid();
    final others =
        participantUids.where((uid) => uid != me).toList(growable: false);
    if (others.isEmpty) {
      return null;
    }
    if (others.length > 1) {
      return _sealForGroup(
        threadId: threadId,
        messageId: messageId,
        participantUids: participantUids,
        payloadJson: payloadJson,
      );
    }

    final address = SignalProtocolAddress(others.single, 1);
    if (!await _store.containsSession(address)) {
      final bundle = await _identityService.fetchPreKeyBundle(others.single);
      if (bundle == null) {
        // They have not published keys yet -- an older build, or a profile
        // mid-setup. Falling back to plaintext is the honest outcome: the
        // alternative is a message they can never read.
        return null;
      }
      await SessionBuilder.fromSignalStore(_store, address)
          .processPreKeyBundle(bundle);
    }

    final ciphertext = await SessionCipher.fromStore(_store, address)
        .encrypt(Uint8List.fromList(utf8.encode(payloadJson)));
    // The type matters to the reader: a PreKeySignalMessage opens a new
    // session, a SignalMessage continues one, and they deserialize through
    // different constructors.
    final envelope = jsonEncode(<String, Object?>{
      't': ciphertext.getType(),
      'b': base64Encode(ciphertext.serialize()),
    });

    // The sender cannot decrypt their own outgoing ciphertext -- it is
    // addressed to the recipient's ratchet. Keeping the plaintext here is
    // what lets the sender's own chat list and history render at all.
    //
    // Keyed by the envelope, not by the inner base64: the local store
    // matches on a digest of whatever the caller passes back, and what
    // comes back out of Firestore is the envelope. Keying on anything else
    // is a permanent cache miss, and for the sender's own messages a
    // permanent miss means unreadable.
    await _localMessages.write(
      threadId: threadId,
      messageId: messageId,
      cipherText: envelope,
      plaintext: payloadJson,
    );

    return envelope;
  }

  @override
  Future<String?> openIncoming({
    required String threadId,
    required String messageId,
    required String senderUid,
    required String cipherText,
  }) async {
    // Local first, always. A Signal ciphertext decrypts exactly once, so a
    // re-read that reached the ratchet would throw rather than return the
    // message again.
    final cached = await _localMessages.read(
      threadId: threadId,
      messageId: messageId,
      cipherText: cipherText,
    );
    if (cached != null) {
      return cached;
    }

    if (senderUid == _currentUid()) {
      // Our own message, with no local copy: sent from another install.
      // Nothing can recover it -- the ciphertext was addressed to the peer.
      return null;
    }

    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(cipherText) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
    final type = (envelope['t'] as num?)?.toInt();
    final body = envelope['b'];
    if (type == null || body is! String) {
      return null;
    }

    final address = SignalProtocolAddress(senderUid, 1);
    final bytes = Uint8List.fromList(base64Decode(body));

    try {
      final Uint8List plaintext;
      if (type == CiphertextMessage.senderKeyType) {
        // A group message, encrypted under the sender's own chain for this
        // thread, which requires their distribution message to have been
        // processed first.
        final keyName = SenderKeyName(threadId, address);
        try {
          plaintext = await GroupCipher(_store, keyName).decrypt(bytes);
        } on NoSessionException {
          // Their key is probably sitting in our inbox right now: it was
          // written in the same batch as this message. Draining on demand
          // and retrying means a group message is readable the moment it
          // lands, rather than only after the next app launch.
          await _senderKeys?.drainInbox();
          final retried =
              await GroupCipher(_store, keyName).decrypt(bytes);
          final payload = utf8.decode(retried);
          await _localMessages.write(
            threadId: threadId,
            messageId: messageId,
            cipherText: cipherText,
            plaintext: payload,
          );
          return payload;
        }
      } else {
        final cipher = SessionCipher.fromStore(_store, address);
        plaintext = type == CiphertextMessage.prekeyType
            ? await cipher.decrypt(PreKeySignalMessage(bytes))
            : await cipher
                .decryptFromSignal(SignalMessage.fromSerialized(bytes));
      }
      final payload = utf8.decode(plaintext);
      await _localMessages.write(
        threadId: threadId,
        messageId: messageId,
        cipherText: cipherText,
        plaintext: payload,
      );
      return payload;
    } catch (error) {
      // Undecryptable: a message from before this device joined, a session
      // that was reset, or a genuinely corrupt envelope. The UI shows a
      // placeholder rather than an empty bubble; never rethrow, or one bad
      // message takes down the whole thread.
      debugPrint('Could not decrypt $threadId/$messageId: $error');
      return null;
    }
  }

  /// Encrypts once for the whole group, under this device's sender key.
  Future<String?> _sealForGroup({
    required String threadId,
    required String messageId,
    required List<String> participantUids,
    required String payloadJson,
  }) async {
    final senderKeys = _senderKeys;
    if (senderKeys == null) {
      return null;
    }

    final keyName =
        SenderKeyName(threadId, SignalProtocolAddress(_currentUid(), 1));
    final ciphertext = await GroupCipher(_store, keyName)
        .encrypt(Uint8List.fromList(utf8.encode(payloadJson)));

    final envelope = jsonEncode(<String, Object?>{
      't': CiphertextMessage.senderKeyType,
      'b': base64Encode(ciphertext),
      // The reader needs to know whose chain to decrypt with, and
      // senderUid on the document is plaintext anyway.
      'g': threadId,
    });

    await _localMessages.write(
      threadId: threadId,
      messageId: messageId,
      cipherText: envelope,
      plaintext: payloadJson,
    );
    return envelope;
  }

  @override
  Future<List<PendingKeyDelivery>> prepareGroupSend({
    required String threadId,
    required List<String> participantUids,
  }) async {
    final senderKeys = _senderKeys;
    if (senderKeys == null ||
        participantUids.where((uid) => uid != _currentUid()).length < 2) {
      return const <PendingKeyDelivery>[];
    }
    await noteMembership(
      threadId: threadId,
      participantUids: participantUids,
    );
    return senderKeys.pendingDeliveries(
      threadId: threadId,
      participantUids: participantUids,
    );
  }

  /// Membership shrank: drop this device's sending chain so the next send
  /// mints a new one that the departed member was never given.
  ///
  /// Detection has to happen on read rather than in `removeGroupMember`,
  /// because the communities repository edits `chatThreads.participantUids`
  /// directly and would bypass any hook placed there.
  Future<void> noteMembership({
    required String threadId,
    required List<String> participantUids,
  }) async {
    final known = _distributedTo[threadId];
    if (known == null) {
      _distributedTo[threadId] = participantUids.toSet();
      return;
    }
    final current = participantUids.toSet();
    if (known.difference(current).isEmpty) {
      // Nobody left -- additions alone never require a rotation.
      _distributedTo[threadId] = known.union(current);
      return;
    }
    await _senderKeys?.rotateOwnKey(threadId);
    _distributedTo.remove(threadId);
  }

  /// Processes any sender keys waiting for this device.
  Future<void> drainKeyDeliveries() async {
    await _senderKeys?.drainInbox();
  }

  @override
  Future<void> forgetThread(String threadId) {
    _distributedTo.remove(threadId);
    return _localMessages.deleteThread(threadId);
  }
}
