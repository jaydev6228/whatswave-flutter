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

  /// Creates a new group thread with the caller plus [memberUids]. Always
  /// creates a fresh thread (no dedup against an existing group with the
  /// same members -- unlike [startThread], there's no natural deterministic
  /// id for an N-person group).
  ///
  /// [isCommunityGroup] marks the resulting thread as backing a community
  /// (see [ChatThread.isCommunityGroup]) so it's excluded from the main
  /// Chats list -- pass true only for threads created on a community's
  /// behalf, never for a user-initiated group from New group.
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
    bool isCommunityGroup = false,
  });

  Future<List<ChatThread>> setThreadArchived({
    required String threadId,
    required bool isArchived,
  });

  Future<List<ChatThread>> setThreadBlocked({
    required String threadId,
    required bool isBlocked,
  });

  /// Empties a thread's messages while keeping the thread/contact itself --
  /// deliberately distinct from [deleteThread], which removes the whole
  /// thread. Matches WhatsApp's "Clear chat" (contact stays, history goes)
  /// rather than "Delete chat" (contact goes too).
  Future<List<ChatThread>> clearThreadMessages(String threadId);

  /// Group threads that both the caller and [participantUid] belong to --
  /// the "Common groups" list on a 1:1 contact's info screen. Empty if
  /// there are none (or this participant isn't a real account, e.g. a
  /// Fake/demo thread with no uid to check membership against).
  Future<List<ChatThread>> groupThreadsSharedWith(String participantUid);

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

  /// Sends one or more attachments as a single message (e.g. several
  /// photos picked together) -- always non-empty.
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
  });

  /// Sets (or replaces) the caller's reaction on [messageId] to [emoji]. If
  /// the caller already reacted with the same [emoji], removes it instead
  /// (a toggle) -- matching how tapping an already-selected reaction in the
  /// picker tray, or tapping your own reaction badge, clears it.
  Future<List<ChatThread>> toggleMessageReaction({
    required String threadId,
    required String messageId,
    required String emoji,
  });
}

class ChatRepositoryException implements Exception {
  const ChatRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
