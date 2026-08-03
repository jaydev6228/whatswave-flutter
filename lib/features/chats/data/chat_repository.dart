import 'package:flutter/material.dart';

import '../domain/chat_attachment.dart';
import '../domain/chat_thread.dart';

abstract class ChatRepository {
  Future<List<ChatThread>> fetchThreads();

  /// Live thread updates, so a message someone else sends shows up (new
  /// preview, unread count, list position) without needing to relaunch or
  /// manually refresh. Null for implementations with no real-time backing
  /// (e.g. the local/fake repository) -- callers should fall back to
  /// [fetchThreads] alone in that case.
  Stream<List<ChatThread>>? watchThreads();

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

  /// Removes a thread from the caller's own chat list only -- the other
  /// participant keeps theirs, and it reappears for the caller if that
  /// person messages them again (matching how "delete chat" behaves in a
  /// real messaging app).
  Future<List<ChatThread>> deleteThread(String threadId);

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
