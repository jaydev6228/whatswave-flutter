import 'package:flutter/material.dart';

import 'chat_message.dart';
import 'group_participant.dart';

class ChatThread {
  const ChatThread({
    required this.id,
    required this.name,
    required this.avatarLabel,
    required this.accentColor,
    required this.messages,
    this.unreadCount = 0,
    this.isMuted = false,
    this.isPinned = false,
    this.isGroup = false,
    this.hasStory = false,
    this.isArchived = false,
    this.isBlocked = false,
    this.typingPreview,
    this.participantUid,
    this.isCommunityGroup = false,
    this.avatarUrl,
    this.participants,
    this.participantUids,
    this.groupDescription,
  });

  final String id;
  final String name;
  final String avatarLabel;
  final Color accentColor;
  final List<ChatMessage> messages;
  final int unreadCount;
  final bool isMuted;
  final bool isPinned;
  final bool isGroup;
  final bool hasStory;
  final bool isArchived;
  final bool isBlocked;
  final String? typingPreview;

  /// The other participant's real Firebase uid, if known -- lets calling
  /// (see CallsController.startOutgoingCall) place a real call instead of
  /// silently falling back to the local simulated flow. Null for Fake/demo
  /// threads, which have no real other-account uid to call.
  final String? participantUid;

  /// True for a group thread created to back a community's messaging (see
  /// CommunitiesController._ensureGroupThreadIfPossible). Communities are a
  /// separate feature from Chats -- real WhatsApp merged community
  /// sub-groups into the main chat list only after removing its dedicated
  /// Communities tab, but this app keeps that tab, so a community-backed
  /// thread is filtered out of every Chats list view (see
  /// ChatsController.threadsForView) and only reachable through the
  /// Communities flow that created it.
  final bool isCommunityGroup;

  /// The other 1:1 participant's uploaded profile photo (see
  /// FirebaseAuthRepository.updateAvatar), resolved the same way as their
  /// live name -- see FirestoreChatRepository's class doc comment. Null
  /// for groups (which have no single other participant) and for anyone
  /// who hasn't set one, falling back to [avatarLabel]/[accentColor].
  final String? avatarUrl;

  /// This group's membership, in creation order -- null for 1:1 threads,
  /// and for a group whose membership hasn't been resolved yet (e.g. a
  /// backend that doesn't support group management).
  final List<GroupParticipant>? participants;

  /// Raw Firebase uids for every group member, including the viewer.
  /// Always set for Firestore-backed groups and used as a fallback when
  /// placing a call if [participants] hasn't been resolved yet.
  final List<String>? participantUids;

  /// A short "what's this group for" blurb, editable by admins -- null if
  /// never set. Not applicable to 1:1 threads.
  final String? groupDescription;

  /// Whether the viewer resolving this thread is a group admin -- always
  /// false for 1:1 threads or a group with no [participants] data.
  bool get currentUserIsGroupAdmin =>
      participants?.any((p) => p.isSelf && p.isAdmin) ?? false;

  /// Every other member uid in this group, excluding [currentUid].
  List<String> otherMemberUids(String currentUid) {
    final uids = participantUids ??
        participants?.map((participant) => participant.uid).toList() ??
        const <String>[];
    return uids.where((uid) => uid != currentUid).toList(growable: false);
  }

  ChatMessage? get latestMessage => messages.isEmpty ? null : messages.last;

  DateTime? get latestActivityAt => latestMessage?.sentAt;

  bool get isTyping => typingPreview?.trim().isNotEmpty ?? false;

  String get typingParticipantLabel {
    final preview = typingPreview?.trim() ?? '';
    if (preview.isEmpty) {
      return '';
    }

    const suffixes = <String>[
      ' is typing…',
      ' is typing...',
      ' is typing',
    ];
    for (final suffix in suffixes) {
      if (preview.toLowerCase().endsWith(suffix.toLowerCase())) {
        return preview.substring(0, preview.length - suffix.length).trim();
      }
    }

    return preview;
  }

  String get listPreview {
    if (isTyping) {
      return typingPreview!.trim();
    }

    final latest = latestMessage;
    if (latest == null) {
      return 'No messages yet';
    }

    final attachmentLabel =
        latest.attachments.isEmpty ? '' : latest.attachments.first.compactLabel;
    final text = latest.text.trim();

    String preview;
    if (attachmentLabel.isNotEmpty && text.isNotEmpty) {
      preview = '$attachmentLabel · $text';
    } else if (text.isNotEmpty) {
      preview = text;
    } else if (attachmentLabel.isNotEmpty) {
      preview = attachmentLabel;
    } else {
      preview = 'Tap to start chatting';
    }

    if (isGroup && !latest.isFromCurrentUser) {
      return '${latest.senderName}: $preview';
    }
    return preview;
  }

  MessageDeliveryState? get listDeliveryState {
    if (isTyping) {
      return null;
    }
    final latest = latestMessage;
    if (latest == null || !latest.isFromCurrentUser) {
      return null;
    }
    return latest.deliveryState;
  }

  ChatThread copyWith({
    String? id,
    String? name,
    String? avatarLabel,
    Color? accentColor,
    List<ChatMessage>? messages,
    int? unreadCount,
    bool? isMuted,
    bool? isPinned,
    bool? isGroup,
    bool? hasStory,
    bool? isArchived,
    bool? isBlocked,
    String? typingPreview,
    bool clearTypingPreview = false,
    String? participantUid,
    bool? isCommunityGroup,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    List<GroupParticipant>? participants,
    List<String>? participantUids,
    String? groupDescription,
  }) {
    return ChatThread(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarLabel: avatarLabel ?? this.avatarLabel,
      accentColor: accentColor ?? this.accentColor,
      messages: messages ?? this.messages,
      unreadCount: unreadCount ?? this.unreadCount,
      isMuted: isMuted ?? this.isMuted,
      isPinned: isPinned ?? this.isPinned,
      isGroup: isGroup ?? this.isGroup,
      hasStory: hasStory ?? this.hasStory,
      isArchived: isArchived ?? this.isArchived,
      isBlocked: isBlocked ?? this.isBlocked,
      typingPreview:
          clearTypingPreview ? null : typingPreview ?? this.typingPreview,
      participantUid: participantUid ?? this.participantUid,
      isCommunityGroup: isCommunityGroup ?? this.isCommunityGroup,
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      participants: participants ?? this.participants,
      participantUids: participantUids ?? this.participantUids,
      groupDescription: groupDescription ?? this.groupDescription,
    );
  }
}
