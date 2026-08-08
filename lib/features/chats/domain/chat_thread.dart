import 'package:flutter/material.dart';

import 'chat_message.dart';

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
    );
  }
}
