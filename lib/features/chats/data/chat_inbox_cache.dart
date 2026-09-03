import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/chat_attachment.dart';
import '../domain/chat_message.dart';
import '../domain/chat_thread.dart';

/// Persists inbox thread summaries on disk so cold starts can paint the chat
/// list immediately while Firestore syncs in the background.
class ChatInboxCache {
  ChatInboxCache({SharedPreferences? preferences}) : _preferences = preferences;

  static const String _storageKeyPrefix = 'chat_inbox_cache_v1';

  final SharedPreferences? _preferences;
  Future<SharedPreferences>? _preferencesFuture;

  Future<SharedPreferences> _resolvePreferences() {
    final cached = _preferences;
    if (cached != null) {
      return Future<SharedPreferences>.value(cached);
    }
    return _preferencesFuture ??= SharedPreferences.getInstance();
  }

  Future<List<ChatThread>?> load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return null;
    }

    final preferences = await _resolvePreferences();
    final raw = preferences.getString('$_storageKeyPrefix:$uid');
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final threadsRaw = decoded['threads'];
      if (threadsRaw is! List<dynamic>) {
        return null;
      }
      return threadsRaw
          .whereType<Map<String, dynamic>>()
          .map(_threadFromCacheJson)
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(List<ChatThread> threads) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || threads.isEmpty) {
      return;
    }

    final preferences = await _resolvePreferences();
    final payload = jsonEncode(<String, Object?>{
      'cachedAt': DateTime.now().toIso8601String(),
      'threads': threads.map(_threadToCacheJson).toList(growable: false),
    });
    await preferences.setString('$_storageKeyPrefix:$uid', payload);
  }

  Map<String, Object?> _threadToCacheJson(ChatThread thread) {
    return <String, Object?>{
      'id': thread.id,
      'name': thread.name,
      'avatarLabel': thread.avatarLabel,
      'accentColorArgb': thread.accentColor.toARGB32(),
      'unreadCount': thread.unreadCount,
      'isMuted': thread.isMuted,
      'isPinned': thread.isPinned,
      'isGroup': thread.isGroup,
      'hasStory': thread.hasStory,
      'isArchived': thread.isArchived,
      'isBlocked': thread.isBlocked,
      'typingPreview': thread.typingPreview,
      'participantUid': thread.participantUid,
      'isCommunityGroup': thread.isCommunityGroup,
      'isAnnouncementOnly': thread.isAnnouncementOnly,
      'avatarUrl': thread.avatarUrl,
      'groupDescription': thread.groupDescription,
      'participantUids': thread.participantUids,
      'messages': thread.messages.map(_messageToCacheJson).toList(),
    };
  }

  ChatThread _threadFromCacheJson(Map<String, dynamic> map) {
    final messagesRaw = (map['messages'] as List<dynamic>?) ?? const [];
    return ChatThread(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      avatarLabel: map['avatarLabel'] as String? ?? '',
      accentColor:
          Color((map['accentColorArgb'] as num?)?.toInt() ?? 0xFF6750A4),
      messages: messagesRaw
          .whereType<Map<String, dynamic>>()
          .map(_messageFromCacheJson)
          .toList(growable: false),
      unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
      isMuted: (map['isMuted'] as bool?) ?? false,
      isPinned: (map['isPinned'] as bool?) ?? false,
      isGroup: (map['isGroup'] as bool?) ?? false,
      hasStory: (map['hasStory'] as bool?) ?? false,
      isArchived: (map['isArchived'] as bool?) ?? false,
      isBlocked: (map['isBlocked'] as bool?) ?? false,
      typingPreview: map['typingPreview'] as String?,
      participantUid: map['participantUid'] as String?,
      isCommunityGroup: (map['isCommunityGroup'] as bool?) ?? false,
      isAnnouncementOnly: (map['isAnnouncementOnly'] as bool?) ?? false,
      avatarUrl: map['avatarUrl'] as String?,
      groupDescription: map['groupDescription'] as String?,
      participantUids: (map['participantUids'] as List<dynamic>?)
          ?.map((entry) => entry.toString())
          .toList(growable: false),
    );
  }

  Map<String, Object?> _messageToCacheJson(ChatMessage message) {
    return <String, Object?>{
      'id': message.id,
      'senderName': message.senderName,
      'sentAtMs': message.sentAt.millisecondsSinceEpoch,
      'isFromCurrentUser': message.isFromCurrentUser,
      'text': message.text,
      'deliveryState': message.deliveryState.name,
      'isDeleted': message.isDeleted,
      'isEdited': message.isEdited,
      'isStarred': message.isStarred,
      'attachments': message.attachments.map(_attachmentToCacheJson).toList(),
    };
  }

  ChatMessage _messageFromCacheJson(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String? ?? '',
      senderName: map['senderName'] as String? ?? '',
      sentAt: DateTime.fromMillisecondsSinceEpoch(
        (map['sentAtMs'] as num?)?.toInt() ?? 0,
      ),
      isFromCurrentUser: (map['isFromCurrentUser'] as bool?) ?? false,
      text: map['text'] as String? ?? '',
      deliveryState: MessageDeliveryState.values.firstWhere(
        (state) => state.name == map['deliveryState'],
        orElse: () => MessageDeliveryState.delivered,
      ),
      isDeleted: (map['isDeleted'] as bool?) ?? false,
      isEdited: (map['isEdited'] as bool?) ?? false,
      isStarred: (map['isStarred'] as bool?) ?? false,
      attachments: ((map['attachments'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_attachmentFromCacheJson)
          .toList(growable: false),
    );
  }

  Map<String, Object?> _attachmentToCacheJson(ChatAttachment attachment) {
    return <String, Object?>{
      'id': attachment.id,
      'type': attachment.type.name,
      'title': attachment.title,
      'details': attachment.details,
      'tintColorArgb': attachment.tintColor.toARGB32(),
      'aspectRatio': attachment.aspectRatio,
      'latitude': attachment.latitude,
      'longitude': attachment.longitude,
      'localMediaPath': attachment.localMediaPath,
    };
  }

  ChatAttachment _attachmentFromCacheJson(Map<String, dynamic> map) {
    return ChatAttachment(
      id: map['id'] as String? ?? '',
      type: ChatAttachmentType.values.firstWhere(
        (type) => type.name == map['type'],
        orElse: () => ChatAttachmentType.file,
      ),
      title: map['title'] as String? ?? '',
      details: map['details'] as String? ?? '',
      tintColor: Color((map['tintColorArgb'] as num?)?.toInt() ?? 0xFF6750A4),
      aspectRatio: (map['aspectRatio'] as num?)?.toDouble() ?? 1.25,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      localMediaPath: map['localMediaPath'] as String?,
    );
  }
}
