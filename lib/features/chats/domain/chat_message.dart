import 'chat_attachment.dart';
import 'story_reply_context.dart';

enum MessageDeliveryState { sending, sent, delivered, read, failed }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderName,
    required this.sentAt,
    required this.isFromCurrentUser,
    this.text = '',
    this.attachments = const <ChatAttachment>[],
    this.deliveryState = MessageDeliveryState.delivered,
    this.reactions = const <String, String>{},
    this.storyReplyContext,
    this.isDeleted = false,
    this.isEdited = false,
  });

  final String id;
  final String senderName;
  final DateTime sentAt;
  final bool isFromCurrentUser;
  final String text;
  final List<ChatAttachment> attachments;
  final MessageDeliveryState deliveryState;

  /// Uid -> emoji, one reaction per user (matches the per-user-map
  /// convention this codebase already uses for things like unread counts).
  final Map<String, String> reactions;

  /// Set only for a message sent from the story viewer's reply bar -- see
  /// [StoryReplyContext].
  final StoryReplyContext? storyReplyContext;

  /// "Deleted for everyone" -- the message stays in place (so the
  /// conversation's shape/order doesn't shift) but [text]/[attachments] are
  /// cleared server-side and the bubble renders a "This message was
  /// deleted" placeholder instead. Distinct from "deleted for me", which
  /// never reaches the domain layer at all -- it's applied as a read-time
  /// filter in the repository (see FirestoreChatRepository's class doc).
  final bool isDeleted;

  /// True once the sender has edited this message's text after sending --
  /// shown as a small "Edited" label, matching WhatsApp.
  final bool isEdited;

  bool get hasText => text.trim().isNotEmpty;
  bool get hasAttachments => attachments.isNotEmpty;
  bool get hasReactions => reactions.isNotEmpty;
  bool get hasStoryReplyContext => storyReplyContext != null;

  ChatMessage copyWith({
    String? id,
    String? senderName,
    DateTime? sentAt,
    bool? isFromCurrentUser,
    String? text,
    List<ChatAttachment>? attachments,
    MessageDeliveryState? deliveryState,
    Map<String, String>? reactions,
    StoryReplyContext? storyReplyContext,
    bool? isDeleted,
    bool? isEdited,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderName: senderName ?? this.senderName,
      sentAt: sentAt ?? this.sentAt,
      isFromCurrentUser: isFromCurrentUser ?? this.isFromCurrentUser,
      text: text ?? this.text,
      attachments: attachments ?? this.attachments,
      deliveryState: deliveryState ?? this.deliveryState,
      reactions: reactions ?? this.reactions,
      storyReplyContext: storyReplyContext ?? this.storyReplyContext,
      isDeleted: isDeleted ?? this.isDeleted,
      isEdited: isEdited ?? this.isEdited,
    );
  }
}
