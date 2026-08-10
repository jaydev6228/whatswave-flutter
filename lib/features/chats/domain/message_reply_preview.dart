/// A frozen snapshot of the message being replied to -- shown as a small
/// quoted card inside the reply's own bubble (see ChatMessage.replyPreview),
/// matching WhatsApp's quote-reply. Deliberately NOT a live reference to the
/// original message (it could be edited or deleted afterward): the snapshot
/// stays exactly as it was at the moment of replying, same as WhatsApp's own
/// behavior.
class MessageReplyPreview {
  const MessageReplyPreview({
    required this.messageId,
    required this.senderName,
    required this.previewText,
  });

  /// The original message's id -- lets tapping the quoted card jump back
  /// to it in the conversation (see ConversationScreen._jumpToMessage).
  /// The original may no longer exist (deleted since); the jump is simply
  /// a no-op in that case since its GlobalKey never got a live context.
  final String messageId;

  /// The original message's sender name exactly as it read at reply time
  /// (including the literal "You" for your own messages, same convention
  /// [ChatMessage.senderName] already uses) -- a frozen snapshot, not
  /// resolved per-reader, so a self-reply still reads "You" to every
  /// viewer rather than the replier's real name.
  final String senderName;
  final String previewText;

  Map<String, Object?> toJson() => {
        'messageId': messageId,
        'senderName': senderName,
        'previewText': previewText,
      };

  static MessageReplyPreview? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final messageId = raw['messageId'] as String?;
    final senderName = raw['senderName'] as String?;
    final previewText = raw['previewText'] as String?;
    if (messageId == null || senderName == null || previewText == null) {
      return null;
    }
    return MessageReplyPreview(
      messageId: messageId,
      senderName: senderName,
      previewText: previewText,
    );
  }
}
