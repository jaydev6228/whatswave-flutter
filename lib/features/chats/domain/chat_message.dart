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
  });

  final String id;
  final String senderName;
  final DateTime sentAt;
  final bool isFromCurrentUser;
  final String text;
  final List<ChatAttachment> attachments;
  final MessageDeliveryState deliveryState;

  bool get hasText => text.trim().isNotEmpty;
  bool get hasAttachments => attachments.isNotEmpty;

  ChatMessage copyWith({
    String? id,
    String? senderName,
    DateTime? sentAt,
    bool? isFromCurrentUser,
    String? text,
    List<ChatAttachment>? attachments,
    MessageDeliveryState? deliveryState,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderName: senderName ?? this.senderName,
      sentAt: sentAt ?? this.sentAt,
      isFromCurrentUser: isFromCurrentUser ?? this.isFromCurrentUser,
      text: text ?? this.text,
      attachments: attachments ?? this.attachments,
      deliveryState: deliveryState ?? this.deliveryState,
    );
  }
}
