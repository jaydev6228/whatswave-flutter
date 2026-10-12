import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'signal_identity_service.dart';
import 'signal_store.dart';

/// Hands each group member the sending key they need to read your messages.
///
/// There is no server-side fanout here and no Cloud Functions, so this is
/// client-driven: each member distributes **their own** sending key over
/// the pairwise 1:1 sessions. Nobody can distribute anybody else's, because
/// nobody holds anybody else's private sending chain -- any design where
/// they could would be self-defeating.
///
/// Deliveries ride in a per-recipient mailbox rather than the thread's own
/// `messages` subcollection. Putting them in `messages` would break three
/// things: the chat-list preview reads the newest message and would show a
/// key blob; `fetchThreadMessagesPage`'s `limit(limit + 1)` paging
/// arithmetic corrupts if you filter after the limit; and the message
/// create rule forbids non-admin writes to an announcement-only thread, so
/// a member could never distribute a key into one at all.
class SenderKeyDistributor {
  SenderKeyDistributor({
    required WhatsWaveSignalStore store,
    required SignalIdentityService identityService,
    required String Function() currentUid,
    FirebaseFirestore? firestore,
  })  : _store = store,
        _identityService = identityService,
        _currentUid = currentUid,
        _firestore = firestore ?? FirebaseFirestore.instance;

  static const String kDistributionType = 'senderKeyDistribution';

  final WhatsWaveSignalStore _store;
  final SignalIdentityService _identityService;
  final String Function() _currentUid;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _inboxOf(String uid) =>
      _firestore.collection('signalKeyDeliveries').doc(uid).collection('inbox');

  SenderKeyName _ownKeyName(String threadId) =>
      SenderKeyName(threadId, SignalProtocolAddress(_currentUid(), 1));

  /// Makes sure every current member holds this device's sending key.
  ///
  /// Lazy: called from the send path, so a member who never sends never
  /// mints a chain and has nothing to leak. Returns the writes to perform,
  /// so the caller can commit them in the same batch as the message and
  /// pay no extra round trip.
  Future<List<PendingKeyDelivery>> pendingDeliveries({
    required String threadId,
    required List<String> participantUids,
  }) async {
    final me = _currentUid();
    final others =
        participantUids.where((uid) => uid != me).toList(growable: false);
    if (others.isEmpty) {
      return const <PendingKeyDelivery>[];
    }

    final keyName = _ownKeyName(threadId);
    final distribution =
        await GroupSessionBuilder(_store).create(keyName);
    final serialized = base64Encode(distribution.serialize());

    final deliveries = <PendingKeyDelivery>[];
    for (final recipient in others) {
      final sealed = await _sealForRecipient(recipient, serialized);
      if (sealed == null) {
        continue;
      }
      deliveries.add(
        PendingKeyDelivery(
          reference: _inboxOf(recipient).doc(),
          data: <String, Object?>{
            'senderUid': me,
            'threadId': threadId,
            'type': kDistributionType,
            'payload': sealed,
            'createdAt': FieldValue.serverTimestamp(),
          },
        ),
      );
    }
    return deliveries;
  }

  /// Wraps the distribution message in the pairwise session, so only the
  /// intended member can read it.
  Future<String?> _sealForRecipient(String recipient, String payload) async {
    final address = SignalProtocolAddress(recipient, 1);
    if (!await _store.containsSession(address)) {
      final bundle = await _identityService.fetchPreKeyBundle(recipient);
      if (bundle == null) {
        return null;
      }
      await SessionBuilder.fromSignalStore(_store, address)
          .processPreKeyBundle(bundle);
    }
    final ciphertext = await SessionCipher.fromStore(_store, address)
        .encrypt(Uint8List.fromList(utf8.encode(payload)));
    return jsonEncode(<String, Object?>{
      't': ciphertext.getType(),
      'b': base64Encode(ciphertext.serialize()),
    });
  }

  /// Processes everything waiting for this device, then deletes it.
  ///
  /// Must run before decrypting group messages on launch. Deleting is not
  /// cleanup: reprocessing a stale distribution message rolls a chain
  /// backwards, so each one is consumed exactly once.
  Future<int> drainInbox() async {
    final me = _currentUid();
    if (me.isEmpty) {
      return 0;
    }
    final pending = await _inboxOf(me).limit(200).get();
    var processed = 0;

    for (final doc in pending.docs) {
      final data = doc.data();
      try {
        final senderUid = data['senderUid']! as String;
        final threadId = data['threadId']! as String;
        final envelope =
            jsonDecode(data['payload']! as String) as Map<String, dynamic>;
        final type = (envelope['t'] as num).toInt();
        final bytes = Uint8List.fromList(base64Decode(envelope['b']! as String));

        final address = SignalProtocolAddress(senderUid, 1);
        final cipher = SessionCipher.fromStore(_store, address);
        final plain = type == CiphertextMessage.prekeyType
            ? await cipher.decrypt(PreKeySignalMessage(bytes))
            : await cipher
                .decryptFromSignal(SignalMessage.fromSerialized(bytes));

        await GroupSessionBuilder(_store).process(
          SenderKeyName(threadId, address),
          SenderKeyDistributionMessageWrapper.fromSerialized(
            Uint8List.fromList(base64Decode(utf8.decode(plain))),
          ),
        );
        processed++;
      } catch (error) {
        // A delivery we cannot process is dropped rather than retried
        // forever. The sender redistributes on their next send, because
        // the recipient will still be missing from their distributedTo set.
        debugPrint('Discarding an unusable key delivery: $error');
      }
      await doc.reference.delete();
    }
    return processed;
  }

  /// Drops this device's sending chain for a group.
  ///
  /// Called when the membership shrinks. The next send mints a new chain
  /// and redistributes it, so a removed member cannot read anything sent
  /// after they left. Without this, group forward secrecy is a claim
  /// rather than a property.
  Future<void> rotateOwnKey(String threadId) =>
      _store.deleteSenderKeysForGroup(threadId);
}

@immutable
class PendingKeyDelivery {
  const PendingKeyDelivery({required this.reference, required this.data});

  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, Object?> data;
}

/// Lets the repository commit deliveries in the message's own batch.
extension PendingDeliveryBatch on List<PendingKeyDelivery> {
  void addToBatch(WriteBatch batch) {
    for (final delivery in this) {
      batch.set(delivery.reference, delivery.data);
    }
  }
}
