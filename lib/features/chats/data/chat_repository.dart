import '../domain/chat_attachment.dart';
import '../domain/chat_thread.dart';

abstract class ChatRepository {
  Future<List<ChatThread>> fetchThreads();

  Future<List<ChatThread>> setThreadArchived({
    required String threadId,
    required bool isArchived,
  });

  Future<List<ChatThread>> markThreadRead(String threadId);

  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
  });

  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required ChatAttachment attachment,
    String? caption,
  });
}

class ChatRepositoryException implements Exception {
  const ChatRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
