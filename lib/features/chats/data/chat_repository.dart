import 'package:flutter/material.dart';

import '../domain/chat_attachment.dart';
import '../domain/chat_thread.dart';

abstract class ChatRepository {
  Future<List<ChatThread>> fetchThreads();

  /// Starts (or finds an existing) 1:1 thread with [participantUid]. Safe to
  /// call repeatedly for the same participant -- returns the same thread
  /// rather than creating duplicates.
  Future<ChatThread> startThread({
    required String participantUid,
    required String participantName,
    required String avatarLabel,
    required Color accentColor,
  });

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
