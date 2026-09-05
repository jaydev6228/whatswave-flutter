import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/media/media_transfer.dart';
import '../../../core/sample/demo_data.dart';
import '../../../core/utils/user_profile_lookup.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_message.dart';
import '../domain/chat_thread.dart';
import '../domain/group_participant.dart';
import '../domain/message_reply_preview.dart';
import '../domain/story_reply_context.dart';
import '../domain/typing_state.dart';
import 'chat_repository.dart';

class FakeChatRepository implements ChatRepository {
  FakeChatRepository({
    List<ChatThread>? initialThreads,
    this.latency = const Duration(milliseconds: 180),
    this.onAttachmentTransfer,
  }) : _threads =
            _deepCopyThreads(initialThreads ?? DemoData.buildChatThreads());

  final Duration latency;

  /// Handed the [MediaTransfer] of an in-flight [sendAttachmentMessage]
  /// before this repository waits on anything, so a test can drive the
  /// bubble's progress ring by hand.
  ///
  /// This repository uploads nothing, so it has no byte counts of its own
  /// to report -- and inventing a timed sequence of them here would put a
  /// fake upload on the code path the local/demo backend actually runs.
  final void Function(MediaTransfer transfer)? onAttachmentTransfer;
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
  Future<ChatThread> fetchThreadWithMessages(String threadId) async {
    await _wait();
    return _deepCopyThread(_threadForId(threadId));
  }

  @override
  Future<ChatMessagePage> fetchThreadMessagesPage({
    required String threadId,
    int limit = 50,
    ChatMessage? before,
  }) async {
    await _wait();
    // Thread messages are chronological (oldest first).
    final all = _threadForId(threadId).messages;
    final int end;
    if (before == null) {
      end = all.length;
    } else {
      final idx = all.indexWhere((m) => m.id == before.id);
      end = idx < 0 ? all.length : idx;
    }
    final start = (end - limit).clamp(0, end);
    return ChatMessagePage(
      messages: all.sublist(start, end).toList(growable: false),
      hasMoreOlder: start > 0,
    );
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
    final threadId = _directThreadIdForParticipant(participantUid);
    final existing = _threads
        .cast<ChatThread?>()
        .firstWhere((entry) => entry?.id == threadId, orElse: () => null);
    if (existing != null) {
      return existing;
    }

    final thread = ChatThread(
      id: threadId,
      name: participantName,
      avatarLabel: avatarLabel,
      accentColor: accentColor,
      participantUid: participantUid,
      messages: const [],
    );
    _threads = [thread, ..._threads];
    return thread;
  }

  String _directThreadIdForParticipant(String participantUid) {
    if (participantUid.startsWith('uid-')) {
      return participantUid.substring(4);
    }
    return participantUid;
  }

  @override
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
    bool isCommunityGroup = false,
    bool isAnnouncementOnly = false,
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
      isCommunityGroup: isCommunityGroup,
      isAnnouncementOnly: isAnnouncementOnly,
      participants: [
        const GroupParticipant(
          uid: 'me',
          name: 'You',
          avatarLabel: 'ME',
          accentColor: AppPalette.slate,
          isAdmin: true,
          isSelf: true,
        ),
        for (final uid in memberUids) _syntheticParticipant(uid),
      ],
    );
    _threads = [thread, ..._threads];
    return thread;
  }

  // The fake repository is only ever given a bare uid for a new member
  // (see createGroup/addGroupMembers) -- unlike FirestoreChatRepository,
  // it has no userProfiles collection to resolve a real name/avatar from,
  // so this is a readable placeholder rather than an attempt at a real
  // lookup.
  GroupParticipant _syntheticParticipant(String uid) {
    final label = uid.length >= 4 ? uid.substring(uid.length - 4) : uid;
    return GroupParticipant(
      uid: uid,
      name: 'Member $label',
      avatarLabel: _avatarLabelForName(label),
      accentColor: _accentColorForName(uid),
    );
  }

  @override
  Future<List<ChatThread>> addGroupMembers({
    required String threadId,
    required List<String> memberUids,
  }) async {
    await _wait();
    final thread = _threadForId(threadId);
    final existingUids =
        thread.participants?.map((p) => p.uid).toSet() ?? <String>{};
    final updated = [
      ...?thread.participants,
      for (final uid in memberUids)
        if (!existingUids.contains(uid)) _syntheticParticipant(uid),
    ];
    _threads = _threads
        .map(
          (entry) => entry.id == thread.id
              ? entry.copyWith(participants: updated)
              : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<List<ChatThread>> removeGroupMember({
    required String threadId,
    required String memberUid,
  }) async {
    await _wait();
    final thread = _threadForId(threadId);
    final updated = (thread.participants ?? const <GroupParticipant>[])
        .where((p) => p.uid != memberUid)
        .toList(growable: false);
    _threads = _threads
        .map(
          (entry) => entry.id == thread.id
              ? entry.copyWith(participants: updated)
              : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<List<ChatThread>> leaveGroup(String threadId) async {
    await _wait();
    _threads =
        _threads.where((entry) => entry.id != threadId).toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<List<ChatThread>> setGroupAdmin({
    required String threadId,
    required String memberUid,
    required bool isAdmin,
  }) async {
    await _wait();
    final thread = _threadForId(threadId);
    final updated = (thread.participants ?? const <GroupParticipant>[])
        .map(
          (p) => p.uid == memberUid ? p.copyWith(isAdmin: isAdmin) : p,
        )
        .toList(growable: false);
    _threads = _threads
        .map(
          (entry) => entry.id == thread.id
              ? entry.copyWith(participants: updated)
              : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<List<ChatThread>> renameGroup({
    required String threadId,
    required String name,
  }) async {
    await _wait();
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const ChatRepositoryException('Give the group a name.');
    }
    final thread = _threadForId(threadId);
    _threads = _threads
        .map(
          (entry) =>
              entry.id == thread.id ? entry.copyWith(name: trimmedName) : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<List<ChatThread>> updateGroupDescription({
    required String threadId,
    required String description,
  }) async {
    await _wait();
    final thread = _threadForId(threadId);
    _threads = _threads
        .map(
          (entry) => entry.id == thread.id
              ? entry.copyWith(groupDescription: description.trim())
              : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<List<ChatThread>> updateGroupAvatar({
    required String threadId,
    required File photo,
  }) async {
    await _wait();
    final thread = _threadForId(threadId);
    // No real upload (or filesystem check) for the fake/demo backend --
    // just stand in the picked file's own path, the same as
    // FakeAuthRepository.updateAvatar's equivalent for profile photos.
    // AvatarBadge already resolves a non-http avatarUrl as a local file
    // path.
    _threads = _threads
        .map(
          (entry) => entry.id == thread.id
              ? entry.copyWith(avatarUrl: photo.path)
              : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<List<ChatThread>> deleteGroupAvatar(String threadId) async {
    await _wait();
    final thread = _threadForId(threadId);
    _threads = _threads
        .map(
          (entry) => entry.id == thread.id
              ? entry.copyWith(clearAvatarUrl: true)
              : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
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
  Future<List<ChatThread>> setThreadBlocked({
    required String threadId,
    required bool isBlocked,
  }) async {
    await _wait();
    final thread = _threadForId(threadId);
    _threads = _threads
        .map(
          (entry) => entry.id == thread.id
              ? entry.copyWith(isBlocked: isBlocked)
              : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<List<ChatThread>> clearThreadMessages(String threadId) async {
    await _wait();
    final thread = _threadForId(threadId);
    _threads = _threads
        .map(
          (entry) => entry.id == thread.id
              ? entry.copyWith(messages: const <ChatMessage>[])
              : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<UserProfileSnapshot?> fetchContactProfile(String uid) async {
    await _wait();
    // Demo threads carry no participantUid (see groupThreadsSharedWith
    // below), so Contact info falls back to the thread id -- which is the
    // same slug the demo contact list is keyed by. Matching both that and
    // matchedUid keeps this working either way.
    for (final contact in DemoData.buildCommunityContacts()) {
      if (contact.id == uid || contact.matchedUid == uid) {
        return UserProfileSnapshot(
          name: contact.name,
          avatarLabel: contact.avatarLabel,
          accentColorArgb: contact.accentColor.toARGB32(),
          username: contact.username,
          about: contact.about,
          phoneNumber: contact.phoneNumber,
        );
      }
    }
    return null;
  }

  @override
  Future<List<ChatThread>> groupThreadsSharedWith(
    String participantUid,
  ) async {
    await _wait();
    // The fake repository never sets a real participantUid on its demo
    // threads (see ChatThread.participantUid's own doc comment), so there
    // is no membership data to check here -- always empty, same as the
    // interface's documented "not a real account" case.
    return const <ChatThread>[];
  }

  @override
  Future<void> markThreadRead(String threadId) async {
    await _wait();
    final thread = _threadForId(threadId);
    _threads = _threads
        .map(
          (entry) =>
              entry.id == thread.id ? entry.copyWith(unreadCount: 0) : entry,
        )
        .toList(growable: false);
  }

  @override
  Future<void> setTypingState({
    required String threadId,
    required bool isTyping,
  }) async {
    await _wait();
    final uid = currentUserReactionKey;
    final thread = _threadForId(threadId);
    final existing = Map<String, TypingParticipantState>.from(
      thread.typingByUid ?? const <String, TypingParticipantState>{},
    );
    if (isTyping) {
      existing[uid] = TypingParticipantState(
        displayName: 'You',
        startedAt: DateTime.now(),
      );
    } else {
      existing.remove(uid);
    }

    _threads = _threads
        .map(
          (entry) => entry.id == thread.id
              ? entry.copyWith(
                  typingByUid: existing.isEmpty ? null : existing,
                  clearTypingByUid: existing.isEmpty,
                  clearTypingPreview: !isTyping,
                )
              : entry,
        )
        .toList(growable: false);
  }

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
    StoryReplyContext? storyReplyContext,
    MessageReplyPreview? replyPreview,
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
      storyReplyContext: storyReplyContext,
      replyPreview: replyPreview,
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
                  clearTypingByUid: true,
                )
              : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<List<ChatThread>> editMessage({
    required String threadId,
    required String messageId,
    required String text,
  }) async {
    await _wait();
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      throw const ChatRepositoryException('A message can\'t be empty.');
    }
    final thread = _threadForId(threadId);

    _threads = _threads
        .map(
          (entry) => entry.id == thread.id
              ? entry.copyWith(
                  messages: entry.messages
                      .map(
                        (message) => message.id == messageId
                            ? message.copyWith(
                                text: normalizedText,
                                isEdited: true,
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

  @override
  Future<List<ChatThread>> deleteMessage({
    required String threadId,
    required String messageId,
    required bool forEveryone,
  }) async {
    await _wait();
    final thread = _threadForId(threadId);

    _threads = _threads
        .map(
          (entry) => entry.id != thread.id
              ? entry
              : entry.copyWith(
                  messages: forEveryone
                      ? entry.messages
                          .map(
                            (message) => message.id == messageId
                                ? message.copyWith(
                                    text: '',
                                    attachments: const <ChatAttachment>[],
                                    isDeleted: true,
                                  )
                                : message,
                          )
                          .toList(growable: false)
                      // No per-uid perspective in fake/demo data (see
                      // _currentUserId below) -- "for me" just removes it
                      // from the single view this repository has.
                      : entry.messages
                          .where((message) => message.id != messageId)
                          .toList(growable: false),
                ),
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
    MessageReplyPreview? replyPreview,
    MediaTransfer? transfer,
  }) async {
    if (transfer != null) {
      onAttachmentTransfer?.call(transfer);
    }
    await _wait();
    if (transfer?.isCancelled ?? false) {
      return _deepCopyThreads(_threads);
    }
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
      replyPreview: replyPreview,
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
                  clearTypingByUid: true,
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
  String get currentUserReactionKey => _currentUserId;

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

  @override
  Future<List<ChatThread>> toggleMessageStar({
    required String threadId,
    required String messageId,
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
                            ? message.copyWith(isStarred: !message.isStarred)
                            : message,
                      )
                      .toList(growable: false),
                )
              : entry,
        )
        .toList(growable: false);
    return _deepCopyThreads(_threads);
  }

  @override
  Future<List<StarredMessageEntry>> fetchStarredMessages() async {
    await _wait();
    final entries = <StarredMessageEntry>[];
    for (final thread in _threads) {
      for (final message in thread.messages) {
        if (message.isStarred) {
          entries.add(
            StarredMessageEntry(threadId: thread.id, message: message),
          );
        }
      }
    }
    return entries;
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

  static ChatThread _deepCopyThread(ChatThread thread) => _cloneThread(thread);

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
