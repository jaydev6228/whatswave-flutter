import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/sample/demo_data.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_message.dart';
import '../domain/chat_thread.dart';
import 'chat_repository.dart';

class FakeChatRepository implements ChatRepository {
  FakeChatRepository({
    List<ChatThread>? initialThreads,
    this.latency = const Duration(milliseconds: 180),
  }) : _threads =
            _deepCopyThreads(initialThreads ?? DemoData.buildChatThreads());

  final Duration latency;
  List<ChatThread> _threads;
  int _messageSequence = 0;

  Future<void> _wait() {
    if (latency == Duration.zero) {
      return Future<void>.value();
    }
    return Future<void>.delayed(latency);
  }

  @override
  Future<List<ChatThread>> fetchThreads() async {
    await _wait();
    return _deepCopyThreads(_threads);
  }

  @override
  Stream<List<ChatThread>>? watchThreads() => null;

  @override
  Future<List<ChatThread>> deleteThread(String threadId) async {
    await _wait();
    _threads =
        _threads.where((entry) => entry.id != threadId).toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<ChatThread> startThread({
    required String participantUid,
    required String participantName,
    required String avatarLabel,
    required Color accentColor,
  }) async {
    await _wait();
    final existing = _threads
        .cast<ChatThread?>()
        .firstWhere((entry) => entry?.id == participantUid, orElse: () => null);
    if (existing != null) {
      return existing;
    }

    final thread = ChatThread(
      id: participantUid,
      name: participantName,
      avatarLabel: avatarLabel,
      accentColor: accentColor,
      messages: const [],
    );
    _threads = [thread, ..._threads];
    return thread;
  }

  @override
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
  }) async {
    await _wait();
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const ChatRepositoryException('Give the group a name.');
    }
    if (memberUids.isEmpty) {
      throw const ChatRepositoryException('Add at least one member.');
    }

    final thread = ChatThread(
      id: 'group-${DateTime.now().microsecondsSinceEpoch}',
      name: trimmedName,
      avatarLabel: _avatarLabelForName(trimmedName),
      accentColor: _accentColorForName(trimmedName),
      messages: const [],
      isGroup: true,
    );
    _threads = [thread, ..._threads];
    return thread;
  }

  @override
  Future<List<ChatThread>> setThreadArchived({
    required String threadId,
    required bool isArchived,
  }) async {
    await _wait();
    final thread = _threadForId(threadId);
    _threads = _threads
        .map(
          (entry) => entry.id == thread.id
              ? entry.copyWith(
                  isArchived: isArchived,
                  clearTypingPreview: isArchived,
                )
              : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<List<ChatThread>> markThreadRead(String threadId) async {
    await _wait();
    final thread = _threadForId(threadId);
    _threads = _threads
        .map(
          (entry) =>
              entry.id == thread.id ? entry.copyWith(unreadCount: 0) : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
  }) async {
    await _wait();
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      throw const ChatRepositoryException(
        'Type a message before sending it.',
      );
    }

    final thread = _threadForId(threadId);
    final newMessage = ChatMessage(
      id: '${thread.id}-message-${_messageSequence++}',
      senderName: 'You',
      sentAt: DateTime.now(),
      isFromCurrentUser: true,
      text: normalizedText,
      deliveryState: MessageDeliveryState.delivered,
    );

    _threads = _threads
        .map(
          (entry) => entry.id == thread.id
              ? entry.copyWith(
                  messages: List<ChatMessage>.unmodifiable(
                    [...entry.messages, newMessage],
                  ),
                  unreadCount: 0,
                  isArchived: false,
                  clearTypingPreview: true,
                )
              : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
  }) async {
    await _wait();
    final thread = _threadForId(threadId);
    final trimmedCaption = caption?.trim() ?? '';
    final newMessage = ChatMessage(
      id: '${thread.id}-message-${_messageSequence++}',
      senderName: 'You',
      sentAt: DateTime.now(),
      isFromCurrentUser: true,
      text: trimmedCaption,
      attachments: List<ChatAttachment>.unmodifiable(attachments),
      deliveryState: MessageDeliveryState.delivered,
    );

    _threads = _threads
        .map(
          (entry) => entry.id == thread.id
              ? entry.copyWith(
                  messages: List<ChatMessage>.unmodifiable(
                    [...entry.messages, newMessage],
                  ),
                  unreadCount: 0,
                  isArchived: false,
                  clearTypingPreview: true,
                )
              : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  /// The fake repository has no real multi-user identity system (messages
  /// only carry an `isFromCurrentUser` flag, not a uid), so it uses a
  /// single fixed key for "this device's own reaction" -- fine for demo
  /// data, which is always a single-perspective view.
  static const String _currentUserId = 'me';

  @override
  Future<List<ChatThread>> toggleMessageReaction({
    required String threadId,
    required String messageId,
    required String emoji,
  }) async {
    await _wait();
    final thread = _threadForId(threadId);

    _threads = _threads
        .map(
          (entry) => entry.id == thread.id
              ? entry.copyWith(
                  messages: entry.messages
                      .map(
                        (message) => message.id == messageId
                            ? message.copyWith(
                                reactions: _toggledReactions(
                                  message.reactions,
                                  emoji,
                                ),
                              )
                            : message,
                      )
                      .toList(growable: false),
                )
              : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  Map<String, String> _toggledReactions(
    Map<String, String> current,
    String emoji,
  ) {
    final next = Map<String, String>.of(current);
    if (next[_currentUserId] == emoji) {
      next.remove(_currentUserId);
    } else {
      next[_currentUserId] = emoji;
    }
    return Map<String, String>.unmodifiable(next);
  }

  String _avatarLabelForName(String name) {
    final parts =
        name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return 'GR';
    }
    if (parts.length == 1) {
      final clean = parts.first.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      return clean.isEmpty
          ? 'GR'
          : clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Color _accentColorForName(String name) {
    const palette = <Color>[
      AppPalette.emerald,
      AppPalette.green,
      AppPalette.sky,
      AppPalette.purple,
      AppPalette.amber,
      AppPalette.rose,
    ];
    return palette[name.hashCode.abs() % palette.length];
  }

  ChatThread _threadForId(String threadId) {
    for (final thread in _threads) {
      if (thread.id == threadId) {
        return thread;
      }
    }

    throw ChatRepositoryException(
      'We could not find that chat anymore. Pull to refresh and try again.',
    );
  }

  static List<ChatThread> _deepCopyThreads(List<ChatThread> threads) {
    return List<ChatThread>.unmodifiable(
      threads.map(_cloneThread),
    );
  }

  static ChatThread _cloneThread(ChatThread thread) {
    return thread.copyWith(
      messages: List<ChatMessage>.unmodifiable(
        thread.messages.map(_cloneMessage),
      ),
    );
  }

  static ChatMessage _cloneMessage(ChatMessage message) {
    return message.copyWith(
      attachments: List<ChatAttachment>.unmodifiable(
        message.attachments.map((attachment) => attachment.copyWith()),
      ),
      reactions: Map<String, String>.unmodifiable(message.reactions),
    );
  }
}
