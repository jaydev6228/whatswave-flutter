import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/media/media_uploader.dart';
import '../../../core/utils/user_profile_lookup.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_message.dart';
import '../domain/chat_thread.dart';
import '../domain/group_participant.dart';
import '../domain/story_reply_context.dart';
import 'chat_repository.dart';

/// Firestore-backed [ChatRepository].
///
/// A thread's displayed name/avatar/color always prefers the *other*
/// participant's own `userProfiles/{uid}` document (see
/// FirebaseAuthRepository, which publishes it on profile save). Falling
/// back to a single shared name/avatarLabel/accentColorArgb field on the
/// thread doc itself (an earlier version of this class did that) is wrong:
/// that field only ever holds a guess about *one specific uid* (whoever
/// startThread's caller was messaging), so using it as a blind fallback
/// for BOTH sides showed each of them the callee's name -- including the
/// callee looking at their own chat and seeing their own name. Fixed by
/// keying the fallback per-uid instead: seedProfiles is a
/// `{uid: {name, avatarLabel, accentColorArgb}}` map, so each viewer's
/// fallback lookup (seedProfiles[otherUid]) can only ever resolve to data
/// that's actually about the other person. If neither the live profile nor
/// a seed entry exists yet (e.g. viewing from the side nobody has
/// messaged), falls back to a generic placeholder rather than guessing
/// wrong.
///
/// unreadCounts and hiddenFor are per-participant maps/arrays (learned from
/// the same mistake as name resolution above -- a single shared
/// `unreadCount` field meant sending a message reset it to 0 for everyone,
/// including the person who was supposed to now have an unread message).
/// isMuted/isPinned/isArchived are still single shared fields -- a real
/// multi-user product would need those to be per-participant too, but
/// nothing has actually surfaced that as wrong yet.
class FirestoreChatRepository implements ChatRepository {
  FirestoreChatRepository({
    FirebaseFirestore? firestore,
    fb_auth.FirebaseAuth? firebaseAuth,
    MediaUploader? mediaUploader,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance,
        _mediaUploader = mediaUploader ?? FirebaseMediaUploader();

  final FirebaseFirestore _firestore;
  final fb_auth.FirebaseAuth _firebaseAuth;
  final MediaUploader _mediaUploader;

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
        _visibleDocs(snapshot.docs, uid)
            .map((doc) => _threadFromDoc(doc, currentUid: uid)),
      );
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(e.message ?? 'Could not load your chats.');
    }
  }

  @override
  Stream<List<ChatThread>> watchThreads() {
    final uid = _requireCurrentUid;
    return _threadsRef
        .where('participantUids', arrayContains: uid)
        .snapshots()
        .asyncMap(
          (snapshot) => Future.wait(
            _visibleDocs(snapshot.docs, uid)
                .map((doc) => _threadFromDoc(doc, currentUid: uid)),
          ),
        );
  }

  /// Excludes threads the caller deleted from their own list (see
  /// [deleteThread]) -- Firestore can't express "arrayContains is false" in
  /// a query, so this filters client-side after the fact instead.
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> _visibleDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String uid,
  ) {
    return docs.where((doc) {
      final hiddenFor =
          (doc.data()['hiddenFor'] as List<dynamic>?)?.cast<String>() ??
              const <String>[];
      return !hiddenFor.contains(uid);
    });
  }

  @override
  Future<ChatThread> startThread({
    required String participantUid,
    required String participantName,
    required String avatarLabel,
    required Color accentColor,
  }) async {
    final uid = _requireCurrentUid;
    if (participantUid == uid) {
      throw const ChatRepositoryException('You cannot start a chat with yourself.');
    }

    // Deterministic id from the sorted pair of uids -- repeated calls for
    // the same two people always resolve to the same thread instead of
    // creating duplicates, with no query/race needed to check first.
    final threadId = ([uid, participantUid]..sort()).join('_');
    final docRef = _threadsRef.doc(threadId);

    try {
      final existing = await docRef.get();
      if (!existing.exists) {
        await docRef.set(<String, Object?>{
          // Keyed by uid, not a flat field -- see the class doc comment
          // for why a single shared name/avatar/color is wrong here.
          'seedProfiles': {
            participantUid: {
              'name': participantName,
              'avatarLabel': avatarLabel,
              'accentColorArgb': accentColor.toARGB32(),
            },
          },
          'participantUids': [uid, participantUid],
          'unreadCounts': {uid: 0, participantUid: 0},
          'hiddenFor': <String>[],
          'isMuted': false,
          'isPinned': false,
          'isGroup': false,
          'hasStory': false,
          'isArchived': false,
        });
      }
      final doc = await docRef.get();
      return _threadFromDoc(doc, currentUid: uid);
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
        e.message ?? 'Could not start that chat right now.',
      );
    }
  }

  @override
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
    bool isCommunityGroup = false,
  }) async {
    final uid = _requireCurrentUid;
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const ChatRepositoryException('Give the group a name.');
    }
    if (memberUids.isEmpty) {
      throw const ChatRepositoryException('Add at least one member.');
    }

    final participantUids = <String>{uid, ...memberUids}.toList();
    final docRef = _threadsRef.doc();

    try {
      await docRef.set(<String, Object?>{
        'isGroup': true,
        'isCommunityGroup': isCommunityGroup,
        'groupName': trimmedName,
        'groupAvatarLabel': _avatarLabelForName(trimmedName),
        'groupAccentColorArgb': _accentColorForName(trimmedName).toARGB32(),
        'groupAdminUids': [uid],
        'participantUids': participantUids,
        'unreadCounts': {for (final id in participantUids) id: 0},
        'hiddenFor': <String>[],
        'isMuted': false,
        'isPinned': false,
        'hasStory': false,
        'isArchived': false,
      });
      final doc = await docRef.get();
      return _threadFromDoc(doc, currentUid: uid);
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
        e.message ?? 'Could not create that group right now.',
      );
    }
  }

  String _avatarLabelForName(String name) {
    final parts =
        name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return 'GR';
    }
    if (parts.length == 1) {
      final clean = parts.first.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      return clean.isEmpty
          ? 'GR'
          : clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Color _accentColorForName(String name) {
    const palette = <Color>[
      AppPalette.emerald,
      AppPalette.green,
      AppPalette.sky,
      AppPalette.purple,
      AppPalette.amber,
      AppPalette.rose,
    ];
    return palette[name.hashCode.abs() % palette.length];
  }

  @override
  Future<List<ChatThread>> addGroupMembers({
    required String threadId,
    required List<String> memberUids,
  }) async {
    try {
      await _threadsRef.doc(threadId).update({
        'participantUids': FieldValue.arrayUnion(memberUids),
        for (final memberUid in memberUids) 'unreadCounts.$memberUid': 0,
      });
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
        e.message ?? 'Could not add members right now.',
      );
    }
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> removeGroupMember({
    required String threadId,
    required String memberUid,
  }) async {
    final uid = _requireCurrentUid;
    if (memberUid == uid) {
      throw const ChatRepositoryException(
        'Use "Exit group" to remove yourself.',
      );
    }
    try {
      await _threadsRef.doc(threadId).update({
        'participantUids': FieldValue.arrayRemove([memberUid]),
        'groupAdminUids': FieldValue.arrayRemove([memberUid]),
      });
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
        e.message ?? 'Could not remove that member right now.',
      );
    }
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> leaveGroup(String threadId) async {
    final uid = _requireCurrentUid;
    try {
      await _threadsRef.doc(threadId).update({
        'participantUids': FieldValue.arrayRemove([uid]),
        'groupAdminUids': FieldValue.arrayRemove([uid]),
      });
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
        e.message ?? 'Could not leave that group right now.',
      );
    }
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> setGroupAdmin({
    required String threadId,
    required String memberUid,
    required bool isAdmin,
  }) async {
    try {
      await _threadsRef.doc(threadId).update({
        'groupAdminUids': isAdmin
            ? FieldValue.arrayUnion([memberUid])
            : FieldValue.arrayRemove([memberUid]),
      });
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
        e.message ?? 'Could not update that admin right now.',
      );
    }
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> renameGroup({
    required String threadId,
    required String name,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const ChatRepositoryException('Give the group a name.');
    }
    try {
      await _threadsRef.doc(threadId).update({'groupName': trimmedName});
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
        e.message ?? 'Could not rename that group right now.',
      );
    }
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> updateGroupDescription({
    required String threadId,
    required String description,
  }) async {
    try {
      await _threadsRef
          .doc(threadId)
          .update({'groupDescription': description.trim()});
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
        e.message ?? 'Could not update that group right now.',
      );
    }
    return fetchThreads();
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
  Future<List<ChatThread>> setThreadBlocked({
    required String threadId,
    required bool isBlocked,
  }) async {
    try {
      await _threadsRef.doc(threadId).update({'isBlocked': isBlocked});
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(e.message ?? 'Could not update that chat.');
    }
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> clearThreadMessages(String threadId) async {
    try {
      final messagesSnapshot =
          await _threadsRef.doc(threadId).collection('messages').get();
      final batch = _firestore.batch();
      for (final doc in messagesSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
        e.message ?? 'Could not clear that chat right now.',
      );
    }
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> groupThreadsSharedWith(
    String participantUid,
  ) async {
    final uid = _requireCurrentUid;
    try {
      final snapshot = await _threadsRef
          .where('participantUids', arrayContains: uid)
          .where('isGroup', isEqualTo: true)
          .get();
      final matchingDocs = snapshot.docs.where((doc) {
        final memberUids =
            (doc.data()['participantUids'] as List<dynamic>?)
                    ?.cast<String>() ??
                const <String>[];
        return memberUids.contains(participantUid);
      }).toList();
      return Future.wait(
        _visibleDocs(matchingDocs, uid)
            .map((doc) => _threadFromDoc(doc, currentUid: uid)),
      );
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
        e.message ?? 'Could not load common groups right now.',
      );
    }
  }

  @override
  Future<List<ChatThread>> markThreadRead(String threadId) async {
    final uid = _requireCurrentUid;
    try {
      await _threadsRef.doc(threadId).update({'unreadCounts.$uid': 0});
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(e.message ?? 'Could not update that chat.');
    }
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> deleteThread(String threadId) async {
    final uid = _requireCurrentUid;
    try {
      await _threadsRef.doc(threadId).update({
        'hiddenFor': FieldValue.arrayUnion([uid]),
      });
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(e.message ?? 'Could not delete that chat.');
    }
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
    StoryReplyContext? storyReplyContext,
  }) async {
    await _sendMessage(
      threadId: threadId,
      text: text,
      attachments: const [],
      storyReplyContext: storyReplyContext,
    );
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> editMessage({
    required String threadId,
    required String messageId,
    required String text,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      throw const ChatRepositoryException('A message can\'t be empty.');
    }
    try {
      await _threadsRef
          .doc(threadId)
          .collection('messages')
          .doc(messageId)
          .update({'text': normalizedText, 'isEdited': true});
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
        e.message ?? 'We could not edit that message right now.',
      );
    }
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> deleteMessage({
    required String threadId,
    required String messageId,
    required bool forEveryone,
  }) async {
    final uid = _requireCurrentUid;
    final messageRef =
        _threadsRef.doc(threadId).collection('messages').doc(messageId);
    try {
      if (forEveryone) {
        await messageRef.update({
          'text': '',
          'attachments': const <Object?>[],
          'isDeleted': true,
        });
      } else {
        await messageRef.update({
          'hiddenFor': FieldValue.arrayUnion([uid]),
        });
      }
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
        e.message ?? 'We could not delete that message right now.',
      );
    }
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
  }) async {
    await _sendMessage(
      threadId: threadId,
      text: caption ?? '',
      attachments: attachments,
    );
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> toggleMessageReaction({
    required String threadId,
    required String messageId,
    required String emoji,
  }) async {
    final uid = _requireCurrentUid;
    final messageRef =
        _threadsRef.doc(threadId).collection('messages').doc(messageId);

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(messageRef);
        final currentReactions =
            (snapshot.data()?['reactions'] as Map<String, dynamic>?) ??
                const <String, dynamic>{};
        final isRemoving = currentReactions[uid] == emoji;
        transaction.update(messageRef, {
          'reactions.$uid': isRemoving ? FieldValue.delete() : emoji,
        });
      });
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
        e.message ?? 'We could not update that reaction right now.',
      );
    }
    return fetchThreads();
  }

  @override
  Future<List<ChatThread>> toggleMessageStar({
    required String threadId,
    required String messageId,
  }) async {
    final uid = _requireCurrentUid;
    final messageRef =
        _threadsRef.doc(threadId).collection('messages').doc(messageId);

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(messageRef);
        final starredBy =
            (snapshot.data()?['starredBy'] as List<dynamic>?)?.cast<String>() ??
                const <String>[];
        transaction.update(messageRef, {
          'starredBy': starredBy.contains(uid)
              ? FieldValue.arrayRemove([uid])
              : FieldValue.arrayUnion([uid]),
        });
      });
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
        e.message ?? 'We could not update that message right now.',
      );
    }
    return fetchThreads();
  }

  Future<void> _sendMessage({
    required String threadId,
    required String text,
    required List<ChatAttachment> attachments,
    StoryReplyContext? storyReplyContext,
  }) async {
    final uid = _requireCurrentUid;
    final senderName = _firebaseAuth.currentUser?.displayName ?? 'You';

    try {
      final threadDoc = await _threadsRef.doc(threadId).get();
      final participantUids =
          (threadDoc.data()?['participantUids'] as List<dynamic>?)
                  ?.cast<String>() ??
              const <String>[];

      final messageRef = _threadsRef.doc(threadId).collection('messages').doc();
      final uploadedAttachments = await Future.wait(
        attachments.map(
          (attachment) => _uploadAttachmentMedia(
            attachment,
            threadId: threadId,
            messageId: messageRef.id,
          ),
        ),
      );

      final batch = _firestore.batch();
      batch.set(messageRef, {
        'senderUid': uid,
        'senderName': senderName,
        'sentAt': FieldValue.serverTimestamp(),
        'text': text,
        'attachments': uploadedAttachments.map(_attachmentToMap).toList(),
        'deliveryState': MessageDeliveryState.delivered.name,
        if (storyReplyContext != null)
          'storyReplyContext': storyReplyContext.toJson(),
      });

      final threadUpdate = <String, Object?>{
        'isArchived': false,
        // A new message un-hides the thread for everyone, matching how a
        // "deleted" chat reappears if the other person messages you again.
        'hiddenFor': <String>[],
        'unreadCounts.$uid': 0,
      };
      for (final participantUid in participantUids) {
        if (participantUid != uid) {
          threadUpdate['unreadCounts.$participantUid'] =
              FieldValue.increment(1);
        }
      }
      batch.update(_threadsRef.doc(threadId), threadUpdate);

      await batch.commit();
    } on FirebaseException catch (e) {
      throw ChatRepositoryException(
          e.message ?? 'Could not send that message.');
    }
  }

  Future<ChatThread> _threadFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String currentUid,
  }) async {
    final data = doc.data() ?? const <String, dynamic>{};

    var name = 'WhatsWave user';
    var avatarLabel = '?';
    var accentColor = AppPalette.slate;
    String? avatarUrl;
    final isGroup = (data['isGroup'] as bool?) ?? false;

    final participantUids =
        (data['participantUids'] as List<dynamic>?)?.cast<String>() ??
            const <String>[];
    // A group has no single "other participant" -- it keeps its own
    // name/avatar/color set at creation time (see createGroup) instead of
    // borrowing another user's profile.
    final otherUid = isGroup
        ? null
        : participantUids.cast<String?>().firstWhere(
            (entry) => entry != null && entry != currentUid,
            orElse: () => null,
          );

    List<GroupParticipant>? participants;
    String? groupDescription;

    if (isGroup) {
      name = (data['groupName'] as String?) ?? 'Group';
      avatarLabel = (data['groupAvatarLabel'] as String?) ?? 'GR';
      accentColor =
          Color((data['groupAccentColorArgb'] as int?) ?? accentColor.toARGB32());
      groupDescription = data['groupDescription'] as String?;

      final adminUids =
          (data['groupAdminUids'] as List<dynamic>?)?.cast<String>() ??
              const <String>[];
      final lookup = UserProfileLookup(firestore: _firestore);
      participants = await Future.wait(
        participantUids.map((memberUid) async {
          final profile = await lookup.fetch(memberUid);
          final isSelf = memberUid == currentUid;
          return GroupParticipant(
            uid: memberUid,
            name: profile?.name ?? (isSelf ? 'You' : 'WhatsWave user'),
            avatarLabel: profile?.avatarLabel ?? '?',
            accentColor:
                Color(profile?.accentColorArgb ?? AppPalette.slate.toARGB32()),
            avatarUrl: profile?.avatarUrl,
            isAdmin: adminUids.contains(memberUid),
            isSelf: isSelf,
          );
        }),
      );
    } else if (otherUid != null) {
      // A per-uid seed guess from whoever created the thread -- only ever
      // valid as a fallback for looking up THIS specific otherUid (see the
      // class doc comment for why a single shared field was wrong).
      final seedProfiles = data['seedProfiles'] as Map<String, dynamic>?;
      final seed = seedProfiles?[otherUid] as Map<String, dynamic>?;
      if (seed != null) {
        final seedName = seed['name'] as String?;
        if (seedName != null && seedName.isNotEmpty) {
          name = seedName;
          avatarLabel = (seed['avatarLabel'] as String?) ?? avatarLabel;
          accentColor =
              Color((seed['accentColorArgb'] as int?) ?? accentColor.toARGB32());
        }
      }

      final profile =
          await UserProfileLookup(firestore: _firestore).fetch(otherUid);
      if (profile != null) {
        name = profile.name;
        avatarLabel = profile.avatarLabel ?? avatarLabel;
        accentColor = Color(profile.accentColorArgb ?? accentColor.toARGB32());
        avatarUrl = profile.avatarUrl;
      }
    }

    final messagesSnapshot =
        await doc.reference.collection('messages').orderBy('sentAt').get();

    final messages = messagesSnapshot.docs
        // "Deleted for me" -- hidden from this reader's own view only;
        // every other participant's read of the same doc is unaffected.
        .where((messageDoc) {
          final hiddenFor =
              (messageDoc.data()['hiddenFor'] as List<dynamic>?) ??
                  const <dynamic>[];
          return !hiddenFor.contains(currentUid);
        })
        .map(
            (messageDoc) => _messageFromDoc(messageDoc, currentUid: currentUid))
        .toList(growable: false);

    return ChatThread(
      id: doc.id,
      name: name,
      avatarLabel: avatarLabel,
      accentColor: accentColor,
      avatarUrl: avatarUrl,
      messages: messages,
      unreadCount:
          (data['unreadCounts'] as Map<String, dynamic>?)?[currentUid]
                  as int? ??
              0,
      isMuted: (data['isMuted'] as bool?) ?? false,
      isPinned: (data['isPinned'] as bool?) ?? false,
      isGroup: (data['isGroup'] as bool?) ?? false,
      hasStory: (data['hasStory'] as bool?) ?? false,
      isArchived: (data['isArchived'] as bool?) ?? false,
      isBlocked: (data['isBlocked'] as bool?) ?? false,
      typingPreview: data['typingPreview'] as String?,
      participantUid: otherUid,
      isCommunityGroup: (data['isCommunityGroup'] as bool?) ?? false,
      participants: participants,
      groupDescription: groupDescription,
    );
  }

  ChatMessage _messageFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required String currentUid,
  }) {
    final data = doc.data();
    final sentAt = data['sentAt'];
    final attachmentsRaw = (data['attachments'] as List<dynamic>?) ?? const [];
    final reactionsRaw =
        (data['reactions'] as Map<String, dynamic>?) ?? const {};

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
      reactions: reactionsRaw.map(
        (uid, emoji) => MapEntry(uid, emoji as String),
      ),
      storyReplyContext:
          StoryReplyContext.fromJson(data['storyReplyContext']),
      isDeleted: (data['isDeleted'] as bool?) ?? false,
      isEdited: (data['isEdited'] as bool?) ?? false,
      isStarred: ((data['starredBy'] as List<dynamic>?) ?? const [])
          .contains(currentUid),
    );
  }

  /// Uploads a photo/video attachment's local file to Firebase Storage and
  /// returns a copy pointing at the resulting download URL instead -- the
  /// only way the OTHER participant's device can ever see this media, since
  /// [ChatAttachment.localMediaPath] otherwise holds a path that only
  /// exists on the sender's own device. Best-effort: on failure (offline,
  /// quota, etc), the message still sends with the original local path so
  /// the sender at least keeps seeing their own bubble, matching this
  /// class's other best-effort writes (e.g. _registerUserProfile).
  Future<ChatAttachment> _uploadAttachmentMedia(
    ChatAttachment attachment, {
    required String threadId,
    required String messageId,
  }) async {
    final localPath = attachment.localMediaPath;
    final isUploadable = localPath != null &&
        localPath.isNotEmpty &&
        !localPath.startsWith('asset://') &&
        !localPath.startsWith('http://') &&
        !localPath.startsWith('https://') &&
        (attachment.type == ChatAttachmentType.photo ||
            attachment.type == ChatAttachmentType.video ||
            attachment.type == ChatAttachmentType.file ||
            attachment.type == ChatAttachmentType.voiceNote);
    if (!isUploadable) {
      return attachment;
    }

    final file = File(localPath);
    if (!await file.exists()) {
      return attachment;
    }

    try {
      final extension = localPath.contains('.')
          ? localPath.substring(localPath.lastIndexOf('.'))
          : switch (attachment.type) {
              ChatAttachmentType.photo => '.jpg',
              ChatAttachmentType.video => '.mp4',
              ChatAttachmentType.voiceNote => '.m4a',
              _ => '',
            };
      final downloadUrl = await _mediaUploader.uploadFile(
        file,
        storagePath: 'chatMedia/$threadId/$messageId-${attachment.id}$extension',
      );
      return attachment.copyWith(localMediaPath: downloadUrl);
    } catch (e) {
      // Best-effort -- see doc comment above. Deliberately catches
      // everything, not just MediaUploadException: a raw platform/plugin
      // error here must never fail the whole send (it previously did,
      // surfacing as "Not sent" on every photo/video message regardless of
      // whether the text-only send would have worked fine).
      debugPrint('Attachment upload failed, sending with local path only: $e');
      return attachment;
    }
  }

  Map<String, Object?> _attachmentToMap(ChatAttachment attachment) {
    return {
      'id': attachment.id,
      'type': attachment.type.name,
      'title': attachment.title,
      'details': attachment.details,
      'tintColorArgb': attachment.tintColor.toARGB32(),
      'aspectRatio': attachment.aspectRatio,
      if (attachment.latitude != null) 'latitude': attachment.latitude,
      if (attachment.longitude != null) 'longitude': attachment.longitude,
      // A Firebase Storage download URL once _uploadAttachmentMedia has run
      // (readable by any device), or -- if that upload failed -- the
      // original device-local path as a same-device-only fallback so at
      // least the sender can still re-read their own sent media back.
      if (attachment.localMediaPath != null)
        'localMediaPath': attachment.localMediaPath,
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
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      localMediaPath: map['localMediaPath'] as String?,
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
