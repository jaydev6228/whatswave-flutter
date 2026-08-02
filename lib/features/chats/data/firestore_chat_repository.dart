import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';

import '../domain/chat_attachment.dart';
import '../domain/chat_message.dart';
import '../domain/chat_thread.dart';
import 'chat_repository.dart';

/// Firestore-backed [ChatRepository].
///
/// Known simplification: unreadCount/isMuted/isPinned/isArchived live
/// directly on the thread document rather than per-participant. This
/// matches how [ChatRepository] already behaves -- there is no per-user
/// parameter anywhere in this interface, it implicitly means "for whoever
/// is signed in" (same assumption FakeChatRepository makes). A real
/// multi-user product would need per-participant state instead.
class FirestoreChatRepository implements ChatRepository {
  FirestoreChatRepository({
    FirebaseFirestore? firestore,
    fb_auth.FirebaseAuth? firebaseAuth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final fb_auth.FirebaseAuth _firebaseAuth;

  CollectionReference<Map<String, dynamic>> get _threadsRef =>
      _firestore.collection('chatThreads');

  String get _requireCurrentUid {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null) {
      throw const ChatRepositoryException('Sign in again to load your chats.');
    }
    return uid;
  }

  @override
  Future<List<ChatThread>> fetchThreads() async {
    final uid = _requireCurrentUid;
    try {
      final snapshot =
          await _threadsRef.where('participantUids', arrayContains: uid).get();
      return Future.wait(
        snapshot.docs.map((doc) => _threadFromDoc(doc, currentUid: uid)),
      );
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(e.message ?? 'Could not load your chats.');
    }
  }

  @override
  Future<List<ChatThread>> setThreadArchived({
    required String threadId,
    required bool isArchived,
  }) async {
    try {
      final update = <String, Object?>{'isArchived': isArchived};
      if (isArchived) {
        update['typingPreview'] = null;
      }
      await _threadsRef.doc(threadId).update(update);
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(e.message ?? 'Could not update that chat.');
    }
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> markThreadRead(String threadId) async {
    try {
      await _threadsRef.doc(threadId).update({'unreadCount': 0});
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(e.message ?? 'Could not update that chat.');
    }
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
  }) async {
    await _sendMessage(threadId: threadId, text: text, attachments: const []);
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required ChatAttachment attachment,
    String? caption,
  }) async {
    await _sendMessage(
      threadId: threadId,
      text: caption ?? '',
      attachments: [attachment],
    );
    return fetchThreads();
  }

  Future<void> _sendMessage({
    required String threadId,
    required String text,
    required List<ChatAttachment> attachments,
  }) async {
    final uid = _requireCurrentUid;
    final senderName = _firebaseAuth.currentUser?.displayName ?? 'You';

    try {
      final batch = _firestore.batch();
      final messageRef = _threadsRef.doc(threadId).collection('messages').doc();

      batch.set(messageRef, {
        'senderUid': uid,
        'senderName': senderName,
        'sentAt': FieldValue.serverTimestamp(),
        'text': text,
        'attachments': attachments.map(_attachmentToMap).toList(),
        'deliveryState': MessageDeliveryState.delivered.name,
      });

      batch.update(_threadsRef.doc(threadId), {
        'unreadCount': 0,
        'isArchived': false,
      });

      await batch.commit();
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
          e.message ?? 'Could not send that message.');
    }
  }

  Future<ChatThread> _threadFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required String currentUid,
  }) async {
    final data = doc.data();

    final messagesSnapshot =
        await doc.reference.collection('messages').orderBy('sentAt').get();

    final messages = messagesSnapshot.docs
        .map(
            (messageDoc) => _messageFromDoc(messageDoc, currentUid: currentUid))
        .toList(growable: false);

    return ChatThread(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      avatarLabel: (data['avatarLabel'] as String?) ?? '',
      accentColor: Color((data['accentColorArgb'] as int?) ?? 0xFF000000),
      messages: messages,
      unreadCount: (data['unreadCount'] as int?) ?? 0,
      isMuted: (data['isMuted'] as bool?) ?? false,
      isPinned: (data['isPinned'] as bool?) ?? false,
      isGroup: (data['isGroup'] as bool?) ?? false,
      hasStory: (data['hasStory'] as bool?) ?? false,
      isArchived: (data['isArchived'] as bool?) ?? false,
      typingPreview: data['typingPreview'] as String?,
    );
  }

  ChatMessage _messageFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required String currentUid,
  }) {
    final data = doc.data();
    final sentAt = data['sentAt'];
    final attachmentsRaw = (data['attachments'] as List<dynamic>?) ?? const [];

    return ChatMessage(
      id: doc.id,
      senderName: (data['senderName'] as String?) ?? '',
      sentAt: sentAt is Timestamp ? sentAt.toDate() : DateTime.now(),
      isFromCurrentUser: data['senderUid'] == currentUid,
      text: (data['text'] as String?) ?? '',
      attachments: attachmentsRaw
          .whereType<Map<String, dynamic>>()
          .map(_attachmentFromMap)
          .toList(growable: false),
      deliveryState: _deliveryStateFromName(data['deliveryState'] as String?),
    );
  }

  Map<String, Object?> _attachmentToMap(ChatAttachment attachment) {
    return {
      'id': attachment.id,
      'type': attachment.type.name,
      'title': attachment.title,
      'details': attachment.details,
      'tintColorArgb': attachment.tintColor.toARGB32(),
      'aspectRatio': attachment.aspectRatio,
    };
  }

  ChatAttachment _attachmentFromMap(Map<String, dynamic> map) {
    return ChatAttachment(
      id: (map['id'] as String?) ?? '',
      type: _attachmentTypeFromName(map['type'] as String?),
      title: (map['title'] as String?) ?? '',
      details: (map['details'] as String?) ?? '',
      tintColor: Color((map['tintColorArgb'] as int?) ?? 0xFF000000),
      aspectRatio: (map['aspectRatio'] as num?)?.toDouble() ?? 1.25,
    );
  }

  ChatAttachmentType _attachmentTypeFromName(String? name) {
    return ChatAttachmentType.values.firstWhere(
      (value) => value.name == name,
      orElse: () => ChatAttachmentType.file,
    );
  }

  MessageDeliveryState _deliveryStateFromName(String? name) {
    return MessageDeliveryState.values.firstWhere(
      (value) => value.name == name,
      orElse: () => MessageDeliveryState.sent,
    );
  }
}
