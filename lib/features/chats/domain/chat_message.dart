import 'chat_attachment.dart';

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

  bool get hasText => text.trim().isNotEmpty;
  bool get hasAttachments => attachments.isNotEmpty;
  bool get hasReactions => reactions.isNotEmpty;

  ChatMessage copyWith({
    String? id,
    String? senderName,
    DateTime? sentAt,
    bool? isFromCurrentUser,
    String? text,
    List<ChatAttachment>? attachments,
    MessageDeliveryState? deliveryState,
    Map<String, String>? reactions,
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
    );
  }
}
