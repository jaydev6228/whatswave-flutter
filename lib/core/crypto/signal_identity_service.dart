import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'signal_store.dart';

/// Publishes this device's public key material and fetches other people's.
///
/// The split that matters: everything written to Firestore here is PUBLIC
/// key material. Private keys never leave [WhatsWaveSignalStore] and never
/// touch the network. A server that is entirely hostile learns who has an
/// identity and what their public keys are, which is exactly what a public
/// key is for.
class SignalIdentityService {
  SignalIdentityService({
    required WhatsWaveSignalStore store,
    FirebaseFirestore? firestore,
    String? Function()? currentUid,
  })  : _store = store,
        _firestore = firestore ?? FirebaseFirestore.instance,
        // Takes just the uid rather than the whole FirebaseAuth: it is all
        // this service needs, and it keeps the class testable without
        // standing up an auth mock.
        _currentUid =
            currentUid ?? (() => fb_auth.FirebaseAuth.instance.currentUser?.uid);

  /// One device per account for now, so the Signal device id is always 1.
  /// Multi-device would make this a real per-installation id.
  static const int deviceId = 1;

  /// How many one-time pre-keys to publish, and the point at which to top
  /// up. Each is consumed by one new conversation; running out means nobody
  /// can start a session with you until you come back online.
  static const int preKeyBatchSize = 100;
  static const int preKeyLowWaterMark = 20;

  final WhatsWaveSignalStore _store;
  final FirebaseFirestore _firestore;
  final String? Function() _currentUid;

  CollectionReference<Map<String, dynamic>> get _identities =>
      _firestore.collection('signalIdentities');

  CollectionReference<Map<String, dynamic>> _preKeysOf(String uid) =>
      _firestore.collection('signalPreKeys').doc(uid).collection('keys');

  /// Creates and publishes an identity if this device has none.
  ///
  /// Idempotent and safe to call on every launch. Returns false when there
  /// is no signed-in user, so callers can simply fire it and forget.
  Future<bool> ensureIdentity() async {
    final uid = _currentUid();
    if (uid == null) {
      return false;
    }

    if (await _store.findIdentityKeyPair() != null) {
      // Already have one: just make sure we have not run low on pre-keys.
      await topUpPreKeys(uid);
      return true;
    }

    final identity = generateIdentityKeyPair();
    final registrationId = generateRegistrationId(false);
    await _store.storeIdentityKeyPair(identity, registrationId);

    final signedPreKey = generateSignedPreKey(identity, 0);
    await _store.storeSignedPreKey(signedPreKey.id, signedPreKey);

    await _identities.doc(uid).set(<String, Object?>{
      'registrationId': registrationId,
      'deviceId': deviceId,
      'identityKey': base64Encode(identity.getPublicKey().serialize()),
      'signedPreKeyId': signedPreKey.id,
      'signedPreKey':
          base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
      'signedPreKeySignature': base64Encode(signedPreKey.signature),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _publishPreKeys(uid, start: 1, count: preKeyBatchSize);
    return true;
  }

  /// Publishes more one-time pre-keys when the pool runs low.
  Future<void> topUpPreKeys(String uid) async {
    final remaining = await _store.remainingPreKeyCount();
    if (remaining > preKeyLowWaterMark) {
      return;
    }
    // Start past the highest id ever used so a recipient never sees an id
    // collide with one they have already consumed.
    final start = DateTime.now().millisecondsSinceEpoch % 0xFFFFFF;
    await _publishPreKeys(uid, start: start, count: preKeyBatchSize);
  }

  Future<void> _publishPreKeys(
    String uid, {
    required int start,
    required int count,
  }) async {
    final preKeys = generatePreKeys(start, count);
    final batch = _firestore.batch();
    for (final preKey in preKeys) {
      await _store.storePreKey(preKey.id, preKey);
      batch.set(_preKeysOf(uid).doc(preKey.id.toString()), <String, Object?>{
        'id': preKey.id,
        'publicKey': base64Encode(preKey.getKeyPair().publicKey.serialize()),
      });
    }
    await batch.commit();
  }

  /// The bundle needed to open a session with [uid].
  ///
  /// Consumes one of their one-time pre-keys -- deleting it is the protocol,
  /// not cleanup: reusing a one-time pre-key weakens the forward secrecy of
  /// the session it starts. Returns a bundle without one if their pool is
  /// empty, which the protocol still allows (slightly weaker, and the normal
  /// fallback for a peer who has been offline a long time).
  Future<PreKeyBundle?> fetchPreKeyBundle(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await _identities.doc(uid).get();
    } on FirebaseException catch (e) {
      // Distinguished from "they have no keys" (null) on purpose. Not
      // being able to REACH the key directory is an infrastructure fault,
      // and treating it as "this contact has no keys" would quietly send
      // the message in plaintext while the user believes it is encrypted.
      //
      // By far the most common cause is firestore.rules not being deployed
      // after the signal* collections were added, so say so.
      throw SignalIdentityException(
        e.code == 'permission-denied'
            ? 'Could not read encryption keys (permission denied). Deploy '
                'firestore.rules: the signalIdentities / signalPreKeys '
                'rules may be missing.'
            : 'Could not reach the encryption key directory (${e.code}).',
      );
    }
    final data = doc.data();
    if (data == null) {
      // They have not set up encryption yet.
      return null;
    }

    final identityKey = IdentityKey.fromBytes(
      _decode(data['identityKey']),
      0,
    );
    final signedPreKey = Curve.decodePoint(_decode(data['signedPreKey']), 0);

    int? preKeyId;
    ECPublicKey? preKeyPublic;
    final available = await _preKeysOf(uid).limit(1).get();
    if (available.docs.isNotEmpty) {
      final preKeyDoc = available.docs.first;
      preKeyId = (preKeyDoc.data()['id'] as num?)?.toInt();
      preKeyPublic = Curve.decodePoint(
        _decode(preKeyDoc.data()['publicKey']),
        0,
      );
      try {
        await preKeyDoc.reference.delete();
      } on FirebaseException catch (e) {
        // Losing the race to another device is fine -- the bundle is still
        // valid. Failing to delete for any other reason is worth knowing
        // about, because a pre-key that is never consumed will be reused.
        debugPrint('Could not consume a one-time pre-key: ${e.code}');
      }
    }

    return PreKeyBundle(
      (data['registrationId'] as num?)?.toInt() ?? 0,
      (data['deviceId'] as num?)?.toInt() ?? deviceId,
      preKeyId ?? 0,
      preKeyPublic,
      (data['signedPreKeyId'] as num?)?.toInt() ?? 0,
      signedPreKey,
      _decode(data['signedPreKeySignature']),
      identityKey,
    );
  }

  /// Removes this account's published key material. Part of sign-out.
  Future<void> unpublish(String uid) async {
    try {
      final keys = await _preKeysOf(uid).get();
      final batch = _firestore.batch();
      for (final doc in keys.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_identities.doc(uid));
      await batch.commit();
    } on FirebaseException catch (e) {
      debugPrint('Could not unpublish Signal keys: ${e.code}');
    }
  }

  Uint8List _decode(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const SignalIdentityException('Malformed published key material.');
    }
    return Uint8List.fromList(base64Decode(value));
  }
}

class SignalIdentityException implements Exception {
  const SignalIdentityException(this.message);

  final String message;

  @override
  String toString() => 'SignalIdentityException: $message';
}
