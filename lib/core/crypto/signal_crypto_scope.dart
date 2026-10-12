import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/chats/data/local_message_store.dart';
import '../../features/chats/data/pending_send_store.dart';
import 'crypto_box.dart';
import 'message_crypto.dart';
import 'safety_number_service.dart';
import 'sender_key_distributor.dart';
import 'signal_identity_service.dart';
import 'signal_key_backup_service.dart';
import 'signal_store.dart';

/// Everything end-to-end encryption needs, assembled once at startup.
///
/// Built in `main()` rather than lazily inside the repository bundle
/// because two SQLite files have to be opened, and that is async while the
/// bundle factory is not. Doing it up front also means a failure here is
/// visible at launch instead of surfacing as a message that silently fails
/// to encrypt.
///
/// Only exists in a Firebase-backed build. The seeded local backend has no
/// peers, no keys and nothing to protect, so it runs without one and every
/// widget test keeps working unchanged.
class SignalCryptoScope {
  SignalCryptoScope._({
    required this.cryptoBox,
    required this.store,
    required this.localMessages,
    required this.pendingSends,
    required this.identityService,
    required this.backupService,
    required this.safetyNumbers,
    required this.messageCrypto,
    required this.senderKeys,
    required this.currentUid,
    required Database signalDatabase,
    required Database messagesDatabase,
    required Database pendingDatabase,
  })  : _signalDatabase = signalDatabase,
        _messagesDatabase = messagesDatabase,
        _pendingDatabase = pendingDatabase;

  final CryptoBox cryptoBox;
  final WhatsWaveSignalStore store;
  final LocalMessageStore localMessages;

  /// Outgoing messages that have not reached the server, so a failed send
  /// survives leaving the conversation.
  final PendingSendStore pendingSends;
  final SignalIdentityService identityService;
  final SignalKeyBackupService backupService;
  final SafetyNumberService safetyNumbers;
  final MessageCrypto messageCrypto;
  final SenderKeyDistributor senderKeys;

  /// The signed-in uid, read at call time. Half of every safety number.
  final String? Function() currentUid;

  final Database _signalDatabase;
  final Database _messagesDatabase;
  final Database _pendingDatabase;

  /// [currentUid] is read at call time rather than captured, because the
  /// scope outlives any one signed-in session.
  static Future<SignalCryptoScope> create({
    required String? Function() currentUid,
    String? directory,
  }) async {
    final root = directory ??
        p.join((await getApplicationSupportDirectory()).path, 'signal');
    await Directory(root).create(recursive: true);

    final cryptoBox = CryptoBox();
    final signalDatabase = await WhatsWaveSignalStore.openDatabase_(
      path: p.join(root, 'signal.db'),
    );
    final messagesDatabase = await LocalMessageStore.open(
      path: p.join(root, 'messages.db'),
    );
    final pendingDatabase = await PendingSendStore.open(
      path: p.join(root, 'pending.db'),
    );

    final store = WhatsWaveSignalStore(
      database: signalDatabase,
      cryptoBox: cryptoBox,
    );
    final localMessages = LocalMessageStore(
      database: messagesDatabase,
      cryptoBox: cryptoBox,
    );
    final identityService = SignalIdentityService(
      store: store,
      currentUid: currentUid,
    );
    final senderKeys = SenderKeyDistributor(
      store: store,
      identityService: identityService,
      currentUid: () => currentUid() ?? '',
    );

    return SignalCryptoScope._(
      cryptoBox: cryptoBox,
      store: store,
      localMessages: localMessages,
      pendingSends: PendingSendStore(
        database: pendingDatabase,
        cryptoBox: cryptoBox,
      ),
      identityService: identityService,
      backupService: SignalKeyBackupService(
        store: store,
        cryptoBox: cryptoBox,
        identityService: identityService,
      ),
      safetyNumbers: SafetyNumberService(store: store),
      senderKeys: senderKeys,
      messageCrypto: SignalMessageCrypto(
        store: store,
        identityService: identityService,
        localMessages: localMessages,
        // Encryption is meaningless without a signed-in identity, and the
        // repository never reaches here unauthenticated.
        currentUid: () => currentUid() ?? '',
        // Without this, group threads silently fall back to plaintext.
        senderKeys: senderKeys,
      ),
      currentUid: currentUid,
      signalDatabase: signalDatabase,
      messagesDatabase: messagesDatabase,
      pendingDatabase: pendingDatabase,
    );
  }

  /// Makes sure this device has an identity and has published its keys.
  ///
  /// Idempotent, best-effort and never throws: a launch must not fail
  /// because key publication did. An unpublished identity degrades to
  /// plaintext sends, which is visible and recoverable; a crash at startup
  /// is not.
  Future<void> ensureIdentity() async {
    try {
      await identityService.ensureIdentity();
      // Sender keys other members sent while this device was away. Must
      // happen before any group message is read, or those messages have no
      // chain to decrypt against and render as unreadable.
      await senderKeys.drainInbox();
    } catch (error, stackTrace) {
      debugPrint('Could not establish a Signal identity: $error\n$stackTrace');
    }
  }

  /// Destroys every key and all decrypted content. Part of sign-out.
  Future<void> wipe() async {
    await store.wipe();
    await localMessages.wipe();
    await pendingSends.wipe();
    await cryptoBox.destroyLocalDataKey();
  }

  Future<void> dispose() async {
    await _signalDatabase.close();
    await _messagesDatabase.close();
    await _pendingDatabase.close();
  }
}
