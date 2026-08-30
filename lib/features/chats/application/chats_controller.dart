import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/models/status_story.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/permissions/app_permission_service.dart';
import '../../../core/permissions/device_location_service.dart';
import '../../calls/domain/call_permissions.dart';
import '../data/chat_inbox_cache.dart';
import '../data/chat_repository.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_message.dart';
import '../domain/chat_thread.dart';
import '../domain/message_reply_preview.dart';
import '../domain/story_reply_context.dart';

enum ChatListFilter { all, unread, groups }

/// Location sharing has its own recoverable "ask for permission" outcome
/// distinct from every other kind of send failure, so the UI can show a
/// dedicated dialog for it instead of routing it through [errorMessage] --
/// a shared banner would otherwise leak onto unrelated screens that also
/// read [errorMessage] (see [ChatsController.errorMessage]).
enum LocationShareOutcome { sent, permissionDenied, failed }

class ChatsController extends ChangeNotifier {
  ChatsController({
    required ChatRepository repository,
    AppPermissionService? permissionService,
    DeviceLocationService? locationService,
    ChatInboxCache? inboxCache,
  })  : _repository = repository,
        _permissionService = permissionService ?? MemoryAppPermissionService(),
        _locationService = locationService ?? GeolocatorDeviceLocationService(),
        _inboxCache = inboxCache ?? ChatInboxCache();

  final ChatRepository _repository;
  final AppPermissionService _permissionService;
  final DeviceLocationService _locationService;
  final ChatInboxCache _inboxCache;
  DeviceLocationService get locationService => _locationService;
  StreamSubscription<List<ChatThread>>? _liveThreadsSubscription;

  bool _hasLoaded = false;
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';
  ChatListFilter _selectedFilter = ChatListFilter.all;
  bool _showArchivedOnly = false;
  List<ChatThread> _threads = const <ChatThread>[];
  final Set<String> _busyThreadIds = <String>{};
  final Set<String> _fullyLoadedThreadIds = <String>{};
  final Set<String> _loadingMessageThreadIds = <String>{};
  final Set<String> _hiddenStoryKeys = <String>{};

  /// Windowed pagination state. A thread's loaded `messages` is the currently
  /// paged-in window (latest [_initialPageSize] on open, extended older as the
  /// user scrolls up), NOT necessarily its full history. These track, per
  /// thread, whether older messages remain on the backend and whether an
  /// older page is currently being fetched.
  static const int _initialPageSize = 50;
  final Map<String, bool> _hasMoreOlderMessages = <String, bool>{};
  final Set<String> _loadingOlderThreadIds = <String>{};

  bool get hasLoaded => _hasLoaded;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  ChatListFilter get selectedFilter => _selectedFilter;
  bool get showArchivedOnly => _showArchivedOnly;
  List<ChatThread> get threads => List<ChatThread>.unmodifiable(_threads);

  /// Threads eligible for the Chats tab's own list views/counts --
  /// everything except community-backed group threads, which are a
  /// separate feature (see [ChatThread.isCommunityGroup]) and stay
  /// reachable only through the Communities flow that created them.
  /// [threadById] deliberately does NOT use this filter, since
  /// ConversationScreen still needs to resolve a community thread by id
  /// when opened from there.
  Iterable<ChatThread> get _chatsTabThreads =>
      _threads.where((thread) => !thread.isCommunityGroup);

  int get archivedCount =>
      _chatsTabThreads.where((thread) => thread.isArchived).length;
  int get activeCount =>
      _chatsTabThreads.where((thread) => !thread.isArchived).length;

  /// Count of non-archived chats with at least one unread message -- drives
  /// the Chats tab's bottom-nav badge.
  int get unreadThreadCount => _chatsTabThreads
      .where((thread) => !thread.isArchived && thread.unreadCount > 0)
      .length;

  List<ChatThread> get visibleThreads => threadsForView(
        archivedOnly: _showArchivedOnly,
      );

  List<ChatThread> archivedThreads({
    String query = '',
    ChatListFilter filter = ChatListFilter.all,
  }) {
    return threadsForView(
      archivedOnly: true,
      query: query,
      filter: filter,
    );
  }

  List<ChatThread> inboxThreads({
    String query = '',
    ChatListFilter filter = ChatListFilter.all,
  }) {
    return threadsForView(
      archivedOnly: false,
      query: query,
      filter: filter,
    );
  }

  List<ChatThread> threadsForView({
    required bool archivedOnly,
    String? query,
    ChatListFilter? filter,
  }) {
    final normalizedQuery = (query ?? _searchQuery).trim().toLowerCase();
    final activeFilter = filter ?? _selectedFilter;
    final filteredThreads = _chatsTabThreads.where((thread) {
      // A 1:1 thread startThreadWith() just created (or one someone opened
      // and never messaged) has no messages yet -- keep it out of every
      // list view until there's an actual conversation, same idea as an
      // empty status not showing up as a real update. threadById() still
      // finds it directly, so the conversation screen it was just opened
      // from keeps working. A group is different: creating one is already
      // a deliberate, named action with chosen participants (matching
      // WhatsApp, which shows a just-created group in the list right
      // away), so this only hides empty 1:1 threads.
      if (thread.messages.isEmpty && !thread.isGroup) {
        return false;
      }
      if (thread.isArchived != archivedOnly) {
        return false;
      }

      final matchesFilter = switch (activeFilter) {
        ChatListFilter.all => true,
        ChatListFilter.unread => thread.unreadCount > 0,
        ChatListFilter.groups => thread.isGroup,
      };
      if (!matchesFilter) {
        return false;
      }

      if (normalizedQuery.isEmpty) {
        return true;
      }

      final preview = thread.listPreview.toLowerCase();
      return thread.name.toLowerCase().contains(normalizedQuery) ||
          preview.contains(normalizedQuery);
    }).toList(growable: false);

    filteredThreads.sort((left, right) {
      if (left.isPinned != right.isPinned) {
        return left.isPinned ? -1 : 1;
      }

      final leftActivity = left.latestActivityAt;
      final rightActivity = right.latestActivityAt;
      if (leftActivity != null && rightActivity != null) {
        final byDate = rightActivity.compareTo(leftActivity);
        if (byDate != 0) {
          return byDate;
        }
      } else if (leftActivity != null || rightActivity != null) {
        return leftActivity == null ? 1 : -1;
      }

      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return filteredThreads;
  }

  ChatThread? threadById(String threadId) {
    for (final thread in _threads) {
      if (thread.id == threadId) {
        return thread;
      }
    }
    return null;
  }

  /// Whether a contact's status should still be visible after their 1:1 chat
  /// was deleted -- deleting a chat hides their story until a new chat starts.
  bool shouldShowStoryForThread(ChatThread thread) {
    if (!thread.hasStory || thread.isGroup) {
      return thread.hasStory;
    }
    return !isStoryHidden(
      avatarLabel: thread.avatarLabel,
      name: thread.name,
      participantUid: thread.participantUid,
      threadId: thread.id,
    );
  }

  bool isStoryHidden({
    required String avatarLabel,
    required String name,
    String? participantUid,
    String? threadId,
  }) {
    for (final key in _hiddenStoryKeys) {
      if (_matchesHiddenStoryKey(
        key: key,
        avatarLabel: avatarLabel,
        name: name,
        participantUid: participantUid,
        threadId: threadId,
      )) {
        return true;
      }
    }
    return false;
  }

  bool isStatusStoryHidden(StatusStory story) {
    if (story.isMine) {
      return false;
    }
    return isStoryHidden(
      avatarLabel: story.avatarLabel,
      name: story.name,
      participantUid: story.id,
    );
  }

  bool isThreadBusy(String threadId) => _busyThreadIds.contains(threadId);

  bool isThreadMessagesLoading(String threadId) =>
      _loadingMessageThreadIds.contains(threadId);

  bool hasFullyLoadedMessages(String threadId) =>
      _fullyLoadedThreadIds.contains(threadId);

  /// Whether older messages remain to be paged in for [threadId] (drives the
  /// top-of-list "loading older" affordance). True only once the initial page
  /// has loaded and the backend reported more history behind it.
  bool hasMoreOlderMessages(String threadId) =>
      _hasMoreOlderMessages[threadId] ?? false;

  bool isLoadingOlderMessages(String threadId) =>
      _loadingOlderThreadIds.contains(threadId);

  Future<void> ensureLoaded() async {
    if (_hasLoaded || _isLoading) {
      return;
    }
    await loadThreads();
  }

  Future<void> loadThreads() async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    if (!_hasLoaded) {
      try {
        final cachedThreads = await _inboxCache.load();
        if (cachedThreads != null && cachedThreads.isNotEmpty) {
          _threads = cachedThreads;
          notifyListeners();
        }
      } catch (_) {
        // Best-effort -- network fetch below remains the source of truth.
      }
    }

    try {
      _threads = _mergeIncomingThreads(await _repository.fetchThreads());
      _hasLoaded = true;
      _listenForLiveThreads();
      unawaited(_persistInboxCache());
      unawaited(refreshStarredMessages());
    } on ChatRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not load your chats right now.';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Keeps [_threads] in sync with messages/reads/deletes happening
  /// elsewhere (e.g. the other participant sending a message), so previews,
  /// unread counts, and list position update on their own instead of
  /// needing a manual refresh or relaunch. No-op for repositories with no
  /// real-time backing (see [ChatRepository.watchThreads]).
  void _listenForLiveThreads() {
    if (_liveThreadsSubscription != null) {
      return;
    }
    final stream = _repository.watchThreads();
    if (stream == null) {
      return;
    }
    _liveThreadsSubscription = stream.listen((threads) {
      _threads = _mergeIncomingThreads(threads);
      unawaited(_persistInboxCache());
      notifyListeners();
    });
  }

  Future<void> _persistInboxCache() async {
    try {
      await _inboxCache.save(_chatsTabThreads.toList(growable: false));
    } catch (_) {
      // Best-effort persistence for cold-start previews.
    }
  }

  Future<void> ensureThreadMessagesLoaded(String threadId) async {
    if (_fullyLoadedThreadIds.contains(threadId) ||
        _loadingMessageThreadIds.contains(threadId)) {
      return;
    }

    _loadingMessageThreadIds.add(threadId);
    notifyListeners();

    try {
      // Load only the most recent window so opening a long thread stays cheap;
      // older messages are paged in on demand via [loadOlderMessages].
      final page = await _repository.fetchThreadMessagesPage(
        threadId: threadId,
        limit: _initialPageSize,
      );
      _fullyLoadedThreadIds.add(threadId);
      _hasMoreOlderMessages[threadId] = page.hasMoreOlder;
      final existing = threadById(threadId);
      if (existing == null) {
        _errorMessage = 'We could not load that chat right now.';
      } else {
        _threads = _threads.map(
          (thread) {
            if (thread.id != threadId) {
              return thread;
            }
            return thread.copyWith(
              messages: _mergeMessages(thread.messages, page.messages),
            );
          },
        ).toList(growable: false);
      }
    } on ChatRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not load that chat right now.';
    }

    _loadingMessageThreadIds.remove(threadId);
    notifyListeners();
  }

  /// Pages in the next-older window for [threadId], prepending it to the loaded
  /// window. Safe to call repeatedly (e.g. as the user nears the top of the
  /// list) -- it no-ops while a fetch is in flight or once history is
  /// exhausted. Contiguous by construction: each page continues from the
  /// oldest message currently loaded, so [_mergeMessages]'s sort never opens a
  /// gap.
  Future<void> loadOlderMessages(String threadId) async {
    if (!_fullyLoadedThreadIds.contains(threadId) ||
        _loadingOlderThreadIds.contains(threadId) ||
        !(_hasMoreOlderMessages[threadId] ?? false)) {
      return;
    }

    final current = threadById(threadId);
    if (current == null || current.messages.isEmpty) {
      return;
    }
    final oldestLoaded = current.messages.first;

    _loadingOlderThreadIds.add(threadId);
    notifyListeners();

    try {
      final page = await _repository.fetchThreadMessagesPage(
        threadId: threadId,
        limit: _initialPageSize,
        before: oldestLoaded,
      );
      // No new messages behind the cursor means we've reached the top.
      _hasMoreOlderMessages[threadId] =
          page.messages.isEmpty ? false : page.hasMoreOlder;
      final cached = threadById(threadId);
      if (cached != null && page.messages.isNotEmpty) {
        final merged = _mergeMessages(cached.messages, page.messages);
        _threads = _threads
            .map(
              (thread) => thread.id == threadId
                  ? thread.copyWith(messages: merged)
                  : thread,
            )
            .toList(growable: false);
      }
    } on ChatRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      // Best-effort; the existing window stays usable and the caller can retry.
    }

    _loadingOlderThreadIds.remove(threadId);
    notifyListeners();
  }

  /// Ensures [messageId] is inside [threadId]'s loaded window, paging older in
  /// batches until it appears (or history is exhausted). Backs tap-to-jump on a
  /// quoted reply whose target scrolled out of the loaded window. Bounded so a
  /// jump to a very old message can't page unboundedly. Returns whether the
  /// message is now loaded.
  Future<bool> ensureMessageLoaded(String threadId, String messageId) async {
    if (!_fullyLoadedThreadIds.contains(threadId)) {
      await ensureThreadMessagesLoaded(threadId);
    }

    bool isLoaded() =>
        threadById(threadId)?.messages.any((m) => m.id == messageId) ?? false;

    // Cap the walk-back so a jump to an ancient message stays bounded.
    const maxPages = 20;
    var pages = 0;
    while (!isLoaded() &&
        (_hasMoreOlderMessages[threadId] ?? false) &&
        pages < maxPages) {
      await loadOlderMessages(threadId);
      pages++;
    }
    return isLoaded();
  }

  List<ChatThread> _mergeIncomingThreads(List<ChatThread> incoming) {
    return incoming.map((thread) {
      final cached = threadById(thread.id);
      if (cached == null) {
        return thread;
      }

      if (!_fullyLoadedThreadIds.contains(thread.id)) {
        if (thread.messages.isNotEmpty &&
            cached.messages.length > thread.messages.length) {
          return thread.copyWith(
            messages: _mergeMessages(cached.messages, thread.messages),
          );
        }
        return thread;
      }

      return thread.copyWith(
        messages: _mergeMessages(cached.messages, thread.messages),
      );
    }).toList(growable: false);
  }

  ChatThread _mergeIncomingThread(ChatThread incoming) {
    return _mergeIncomingThreads([incoming]).first;
  }

  bool _isSummaryMessageSnapshot(
    List<ChatMessage> incomingMessages,
    List<ChatMessage> cachedMessages,
  ) {
    return incomingMessages.length == 1 && cachedMessages.length > 1;
  }

  void _applyOptimisticMessageRemoval({
    required String threadId,
    required String messageId,
    required bool forEveryone,
  }) {
    _threads = _threads.map(
      (thread) {
        if (thread.id != threadId) {
          return thread;
        }
        if (forEveryone) {
          return thread.copyWith(
            messages: thread.messages
                .map(
                  (message) => message.id == messageId
                      ? message.copyWith(
                          text: '',
                          attachments: const <ChatAttachment>[],
                          isDeleted: true,
                        )
                      : message,
                )
                .toList(growable: false),
          );
        }
        return thread.copyWith(
          messages: thread.messages
              .where((message) => message.id != messageId)
              .toList(growable: false),
        );
      },
    ).toList(growable: false);
    notifyListeners();
  }

  void _applyOptimisticClear(String threadId) {
    _threads = _threads
        .map(
          (thread) => thread.id == threadId
              ? thread.copyWith(messages: const <ChatMessage>[])
              : thread,
        )
        .toList(growable: false);
    notifyListeners();
  }

  List<ChatMessage> _mergeMessages(
    List<ChatMessage> cachedMessages,
    List<ChatMessage> incomingMessages,
  ) {
    if (incomingMessages.isEmpty) {
      return cachedMessages;
    }

    final mergedById = <String, ChatMessage>{
      for (final message in cachedMessages) message.id: message,
    };
    for (final message in incomingMessages) {
      // Incoming wins for the same id so edits, reactions, and deletes apply.
      mergedById[message.id] = message;
    }

    final merged = mergedById.values.toList(growable: false)
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return List<ChatMessage>.unmodifiable(merged);
  }

  @override
  void dispose() {
    _liveThreadsSubscription?.cancel();
    super.dispose();
  }

  void updateSearchQuery(String value) {
    if (_searchQuery == value) {
      return;
    }

    _searchQuery = value;
    _errorMessage = null;
    notifyListeners();
  }

  void updateFilter(ChatListFilter filter) {
    if (_selectedFilter == filter) {
      return;
    }

    _selectedFilter = filter;
    _errorMessage = null;
    notifyListeners();
  }

  void toggleArchivedOnly() {
    _showArchivedOnly = !_showArchivedOnly;
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }

    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> setThreadArchived({
    required String threadId,
    required bool isArchived,
  }) async {
    return _runThreadMutation(
      threadId,
      () => _repository.setThreadArchived(
        threadId: threadId,
        isArchived: isArchived,
      ),
      fallbackError: 'We could not update that chat right now.',
      afterSuccess: () {
        if (_showArchivedOnly && visibleThreads.isEmpty && archivedCount == 0) {
          _showArchivedOnly = false;
        }
      },
    );
  }

  Future<bool> deleteThread(String threadId) async {
    final thread = threadById(threadId);
    final didDelete = await _runThreadMutation(
      threadId,
      () => _repository.deleteThread(threadId),
      fallbackError: 'We could not delete that chat right now.',
    );
    if (didDelete && thread != null && !thread.isGroup) {
      _hideStoryForDeletedThread(thread);
      notifyListeners();
    }
    return didDelete;
  }

  Future<bool> setThreadBlocked({
    required String threadId,
    required bool isBlocked,
  }) async {
    return _runThreadMutation(
      threadId,
      () => _repository.setThreadBlocked(
        threadId: threadId,
        isBlocked: isBlocked,
      ),
      fallbackError: 'We could not update that contact right now.',
    );
  }

  Future<bool> clearThreadMessages(String threadId) async {
    _applyOptimisticClear(threadId);
    return _runThreadMutation(
      threadId,
      () => _repository.clearThreadMessages(threadId),
      fallbackError: 'We could not clear that chat right now.',
      notifyWhileBusy: false,
    );
  }

  Future<List<ChatThread>> groupThreadsSharedWith(
    String participantUid,
  ) async {
    try {
      return await _repository.groupThreadsSharedWith(participantUid);
    } on ChatRepositoryException {
      return const <ChatThread>[];
    } catch (_) {
      return const <ChatThread>[];
    }
  }

  /// Starts (or finds an existing) 1:1 thread with [participantUid] and
  /// returns its id, or null on failure (see [errorMessage]).
  Future<String?> startThreadWith({
    required String participantUid,
    required String participantName,
    required String avatarLabel,
    required Color accentColor,
  }) async {
    _errorMessage = null;
    notifyListeners();

    try {
      final thread = await _repository.startThread(
        participantUid: participantUid,
        participantName: participantName,
        avatarLabel: avatarLabel,
        accentColor: accentColor,
      );
      _unhideStoryForParticipant(
        participantUid: participantUid,
        avatarLabel: avatarLabel,
        name: participantName,
      );
      var incoming = await _repository.fetchThreads();
      if (!incoming.any((entry) => entry.id == thread.id)) {
        incoming = [thread, ...incoming];
      }
      _threads = _mergeIncomingThreads(incoming);
      if (threadById(thread.id) == null) {
        _threads = [thread, ..._threads];
      }
      notifyListeners();
      return thread.id;
    } on ChatRepositoryException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return null;
    } catch (_) {
      _errorMessage = 'We could not start that chat right now.';
      notifyListeners();
      return null;
    }
  }

  /// Creates a new group thread with [memberUids] and returns its id, or
  /// null on failure (see [errorMessage]).
  ///
  /// [isCommunityGroup] should only be true when called on a community's
  /// behalf (see [ChatThread.isCommunityGroup]) -- it keeps the resulting
  /// thread out of every Chats list view.
  Future<String?> createGroup({
    required String name,
    required List<String> memberUids,
    bool isCommunityGroup = false,
  }) async {
    _errorMessage = null;
    notifyListeners();

    try {
      final thread = await _repository.createGroup(
        name: name,
        memberUids: memberUids,
        isCommunityGroup: isCommunityGroup,
      );
      _threads = _mergeIncomingThreads(await _repository.fetchThreads());
      notifyListeners();
      return thread.id;
    } on ChatRepositoryException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return null;
    } catch (_) {
      _errorMessage = 'We could not create that group right now.';
      notifyListeners();
      return null;
    }
  }

  Future<bool> addGroupMembers({
    required String threadId,
    required List<String> memberUids,
  }) async {
    return _runThreadMutation(
      threadId,
      () => _repository.addGroupMembers(
        threadId: threadId,
        memberUids: memberUids,
      ),
      fallbackError: 'We could not add those members right now.',
    );
  }

  Future<bool> removeGroupMember({
    required String threadId,
    required String memberUid,
  }) async {
    return _runThreadMutation(
      threadId,
      () => _repository.removeGroupMember(
        threadId: threadId,
        memberUid: memberUid,
      ),
      fallbackError: 'We could not remove that member right now.',
    );
  }

  Future<bool> leaveGroup(String threadId) async {
    return _runThreadMutation(
      threadId,
      () => _repository.leaveGroup(threadId),
      fallbackError: 'We could not leave that group right now.',
    );
  }

  Future<bool> setGroupAdmin({
    required String threadId,
    required String memberUid,
    required bool isAdmin,
  }) async {
    return _runThreadMutation(
      threadId,
      () => _repository.setGroupAdmin(
        threadId: threadId,
        memberUid: memberUid,
        isAdmin: isAdmin,
      ),
      fallbackError: 'We could not update that admin right now.',
    );
  }

  Future<bool> renameGroup({
    required String threadId,
    required String name,
  }) async {
    return _runThreadMutation(
      threadId,
      () => _repository.renameGroup(threadId: threadId, name: name),
      fallbackError: 'We could not rename that group right now.',
    );
  }

  Future<bool> updateGroupDescription({
    required String threadId,
    required String description,
  }) async {
    return _runThreadMutation(
      threadId,
      () => _repository.updateGroupDescription(
        threadId: threadId,
        description: description,
      ),
      fallbackError: 'We could not update that group right now.',
    );
  }

  /// Uploads [photo] as a group's icon -- called both right after
  /// [createGroup] (New group's name step, if a photo was picked) and to
  /// change it later from group info, the same single path either way.
  Future<bool> updateGroupAvatar({
    required String threadId,
    required File photo,
  }) async {
    return _runThreadMutation(
      threadId,
      () => _repository.updateGroupAvatar(threadId: threadId, photo: photo),
      fallbackError: 'We could not update that group photo right now.',
    );
  }

  Future<bool> deleteGroupAvatar(String threadId) async {
    return _runThreadMutation(
      threadId,
      () => _repository.deleteGroupAvatar(threadId),
      fallbackError: 'We could not remove that group photo right now.',
    );
  }

  void openThread(String threadId) {
    _markThreadReadOptimistic(threadId);
    unawaited(_markThreadReadRemote(threadId));
  }

  void _markThreadReadOptimistic(String threadId) {
    final thread = threadById(threadId);
    if (thread == null || thread.unreadCount == 0) {
      return;
    }

    _threads = _threads
        .map(
          (entry) =>
              entry.id == threadId ? entry.copyWith(unreadCount: 0) : entry,
        )
        .toList(growable: false);
    notifyListeners();
  }

  Future<void> _markThreadReadRemote(String threadId) async {
    try {
      await _repository.markThreadRead(threadId);
    } on ChatRepositoryException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
    } catch (_) {
      _errorMessage = 'We could not open that chat right now.';
      notifyListeners();
    }
  }

  Future<bool> sendTextMessage({
    required String threadId,
    required String text,
    StoryReplyContext? storyReplyContext,
    MessageReplyPreview? replyPreview,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      _errorMessage = 'Type a message before sending it.';
      notifyListeners();
      return false;
    }

    return _runThreadMutation(
      threadId,
      () => _repository.sendTextMessage(
        threadId: threadId,
        text: normalizedText,
        storyReplyContext: storyReplyContext,
        replyPreview: replyPreview,
      ),
      fallbackError: 'We could not send that message right now.',
      clearSearch: false,
      notifyWhileBusy: false,
    );
  }

  Future<bool> editMessage({
    required String threadId,
    required String messageId,
    required String text,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      _errorMessage = 'A message can\'t be empty.';
      notifyListeners();
      return false;
    }

    return _runThreadMutation(
      threadId,
      () => _repository.editMessage(
        threadId: threadId,
        messageId: messageId,
        text: normalizedText,
      ),
      fallbackError: 'We could not edit that message right now.',
      clearSearch: false,
    );
  }

  Future<bool> deleteMessage({
    required String threadId,
    required String messageId,
    required bool forEveryone,
  }) {
    _applyOptimisticMessageRemoval(
      threadId: threadId,
      messageId: messageId,
      forEveryone: forEveryone,
    );
    return _runThreadMutation(
      threadId,
      () => _repository.deleteMessage(
        threadId: threadId,
        messageId: messageId,
        forEveryone: forEveryone,
      ),
      fallbackError: 'We could not delete that message right now.',
      clearSearch: false,
      notifyWhileBusy: false,
    );
  }

  Future<bool> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
    MessageReplyPreview? replyPreview,
  }) {
    return _runThreadMutation(
      threadId,
      () => _repository.sendAttachmentMessage(
        threadId: threadId,
        attachments: attachments,
        caption: caption,
        replyPreview: replyPreview,
      ),
      fallbackError: 'We could not send that attachment right now.',
      clearSearch: false,
      notifyWhileBusy: false,
    );
  }

  Future<bool> toggleMessageReaction({
    required String threadId,
    required String messageId,
    required String emoji,
  }) {
    // Reflect the reaction (or its removal) immediately -- WhatsApp shows it
    // the instant you tap. _runThreadMutation then replaces threads with the
    // real result on success, or re-syncs authoritatively (reverting this)
    // if the backend rejects the write.
    _applyOptimisticReaction(
      threadId: threadId,
      messageId: messageId,
      emoji: emoji,
    );
    return _runThreadMutation(
      threadId,
      () => _repository.toggleMessageReaction(
        threadId: threadId,
        messageId: messageId,
        emoji: emoji,
      ),
      fallbackError: 'We could not update that reaction right now.',
      clearSearch: false,
    );
  }

  /// Toggles the current user's reaction on a message in local state: a fresh
  /// emoji is added, tapping the same emoji again removes it. Keyed by the
  /// backend's [ChatRepository.currentUserReactionKey] so it matches what the
  /// server will store.
  void _applyOptimisticReaction({
    required String threadId,
    required String messageId,
    required String emoji,
  }) {
    final key = _repository.currentUserReactionKey;
    if (key.isEmpty) {
      return;
    }
    _threads = _threads.map((thread) {
      if (thread.id != threadId) {
        return thread;
      }
      return thread.copyWith(
        messages: thread.messages.map((message) {
          if (message.id != messageId) {
            return message;
          }
          final reactions = Map<String, String>.from(message.reactions);
          if (reactions[key] == emoji) {
            reactions.remove(key);
          } else {
            reactions[key] = emoji;
          }
          return message.copyWith(reactions: reactions);
        }).toList(growable: false),
      );
    }).toList(growable: false);
    notifyListeners();
  }

  Future<bool> toggleMessageStar({
    required String threadId,
    required String messageId,
  }) {
    return _runThreadMutation(
      threadId,
      () => _repository.toggleMessageStar(
        threadId: threadId,
        messageId: messageId,
      ),
      fallbackError: 'We could not update that message right now.',
      clearSearch: false,
      afterSuccess: () => _syncStarredEntry(
        threadId: threadId,
        messageId: messageId,
      ),
    );
  }

  List<StarredMessageEntry> _starredEntries = const <StarredMessageEntry>[];
  bool _isLoadingStarredMessages = false;

  /// Every starred message across every thread (most recent first), paired
  /// with the thread it lives in -- backs the "Starred messages" screen.
  ///
  /// Sourced from [refreshStarredMessages]/[ChatRepository.fetchStarredMessages]
  /// rather than scanning [_threads], since a thread's [ChatThread.messages]
  /// only ever holds whichever window it currently has loaded (see
  /// windowed pagination in [ensureThreadMessagesLoaded]) -- deriving this
  /// list from that window would silently miss a starred message in any
  /// thread the caller hasn't opened this session.
  List<({ChatThread thread, ChatMessage message})> get starredMessages {
    final entries = <({ChatThread thread, ChatMessage message})>[];
    for (final entry in _starredEntries) {
      final thread = threadById(entry.threadId);
      if (thread != null) {
        entries.add((thread: thread, message: entry.message));
      }
    }
    return entries;
  }

  /// Re-fetches [_starredEntries] from the repository -- called once in the
  /// background after the initial thread list loads, and again whenever the
  /// Starred messages screen is opened, so it never depends on which
  /// threads happen to already have a loaded message window.
  Future<void> refreshStarredMessages() async {
    if (_isLoadingStarredMessages) {
      return;
    }
    _isLoadingStarredMessages = true;
    try {
      final entries = await _repository.fetchStarredMessages();
      entries.sort(
        (a, b) => b.message.sentAt.compareTo(a.message.sentAt),
      );
      _starredEntries = entries;
      notifyListeners();
    } catch (_) {
      // Best-effort -- the screen simply keeps showing whatever it already
      // had (possibly empty) rather than surfacing a separate error banner.
    } finally {
      _isLoadingStarredMessages = false;
    }
  }

  /// Optimistically keeps [_starredEntries] in sync right after a star
  /// toggle succeeds, using the just-mutated message already merged into
  /// [_threads] -- avoids waiting on a full [refreshStarredMessages] round
  /// trip for the thread the caller is actively looking at.
  void _syncStarredEntry({
    required String threadId,
    required String messageId,
  }) {
    final message = threadById(threadId)
        ?.messages
        .where((candidate) => candidate.id == messageId)
        .firstOrNull;
    if (message == null) {
      return;
    }
    final withoutMessage = _starredEntries
        .where((entry) => entry.message.id != messageId)
        .toList(growable: false);
    if (!message.isStarred) {
      _starredEntries = withoutMessage;
      return;
    }
    _starredEntries = [
      ...withoutMessage,
      StarredMessageEntry(threadId: threadId, message: message),
    ]..sort((a, b) => b.message.sentAt.compareTo(a.message.sentAt));
  }

  String? _locationFailureMessage;
  String? get locationFailureMessage => _locationFailureMessage;

  Future<void> openLocationSettings() => _permissionService.openSettings();

  /// Captures the device's current GPS fix and sends it as a location
  /// attachment, requesting location permission first if needed. Unlike
  /// [sendAttachmentMessage], the caller has no attachment to show
  /// optimistically up front -- permission + a GPS fix both take a moment,
  /// so [isThreadBusy] is the only feedback until this resolves.
  ///
  /// Deliberately does not touch [errorMessage]/[_errorMessage] -- that
  /// banner is read by other screens too (e.g. the Chats list), so a denied
  /// permission here would otherwise leak an unrelated banner onto them.
  /// The caller shows a dedicated dialog based on the returned outcome.
  Future<LocationShareOutcome> sendCurrentLocation({
    required String threadId,
    String? caption,
  }) async {
    _busyThreadIds.add(threadId);
    _locationFailureMessage = null;
    notifyListeners();

    var outcome = LocationShareOutcome.failed;
    try {
      var status = await _permissionService.locationAccessStatus();
      if (status != CallPermissionStatus.granted) {
        status = await _permissionService.requestLocationAccess();
      }

      if (status != CallPermissionStatus.granted) {
        outcome = LocationShareOutcome.permissionDenied;
      } else {
        final fix = await _locationService.getCurrentLocation();
        final attachment = ChatAttachment(
          id: '$threadId-location-${DateTime.now().microsecondsSinceEpoch}',
          type: ChatAttachmentType.location,
          title: 'Current location',
          details: 'Tap to open in Maps',
          tintColor: AppPalette.rose,
          latitude: fix.latitude,
          longitude: fix.longitude,
        );
        final incoming = await _repository.sendAttachmentMessage(
          threadId: threadId,
          attachments: [attachment],
          caption: caption,
        );
        _threads = _reconcileMutatedThread(
          incoming: incoming,
          mutatedThreadId: threadId,
        );
        if (_fullyLoadedThreadIds.contains(threadId)) {
          unawaited(_syncOpenThreadMessagesInBackground(threadId));
        } else {
          unawaited(ensureThreadMessagesLoaded(threadId));
        }
        outcome = LocationShareOutcome.sent;
      }
    } on DeviceLocationException catch (error) {
      _locationFailureMessage = error.message;
    } on ChatRepositoryException catch (error) {
      _locationFailureMessage = error.message;
    } catch (_) {
      _locationFailureMessage = 'We could not share your location right now.';
    }

    _busyThreadIds.remove(threadId);
    notifyListeners();
    return outcome;
  }

  /// Merges any missing server messages in the background without blocking
  /// send UX or rebuilding the list when nothing changed.
  /// Upper bound on how much of a (possibly deeply paged-back) window the
  /// background sync refetches, so reconciliation after a mutation stays cheap
  /// even when the user has scrolled far into history.
  static const int _maxSyncWindow = 200;

  Future<void> _syncOpenThreadMessagesInBackground(
    String threadId, {
    bool authoritative = false,
  }) async {
    if (!_fullyLoadedThreadIds.contains(threadId)) {
      return;
    }

    final before = threadById(threadId);
    if (before == null) {
      return;
    }
    // Refetch a window that covers what's loaded (capped) rather than the
    // thread's full history -- pagination means `messages` is a window, not
    // everything.
    final limit =
        before.messages.length.clamp(_initialPageSize, _maxSyncWindow);

    try {
      final page = await _repository.fetchThreadMessagesPage(
        threadId: threadId,
        limit: limit,
      );
      final cached = threadById(threadId);
      if (cached == null) {
        return;
      }
      // The newest window is at least as deep as what we asked for; older
      // history behind it either still exists or was already known to.
      _hasMoreOlderMessages[threadId] =
          page.hasMoreOlder || (_hasMoreOlderMessages[threadId] ?? false);

      final reconciled = authoritative
          ? _reconcileWindow(cached.messages, page.messages)
          : _mergeMessages(cached.messages, page.messages);

      if (_messageListsEquivalent(cached.messages, reconciled)) {
        return;
      }

      _threads = _threads
          .map(
            (thread) => thread.id == threadId
                ? thread.copyWith(messages: reconciled)
                : thread,
          )
          .toList(growable: false);
      notifyListeners();
    } catch (_) {
      // Best-effort; merged in-memory state remains usable.
    }
  }

  /// Authoritative reconciliation for the background sync: the refetched [page]
  /// is the source of truth for everything from its oldest message onward (so
  /// deletes/edits inside the window are reflected instead of lingering the way
  /// a union merge would), while cached history strictly older than the window
  /// is preserved so paged-in older messages don't vanish.
  List<ChatMessage> _reconcileWindow(
    List<ChatMessage> cached,
    List<ChatMessage> page,
  ) {
    if (page.isEmpty) {
      // The whole refetched window came back empty -- the thread was cleared.
      return const <ChatMessage>[];
    }
    final windowStart = page.first.sentAt;
    final older = cached
        .where((message) => message.sentAt.isBefore(windowStart))
        .toList(growable: false);
    return List<ChatMessage>.unmodifiable(<ChatMessage>[...older, ...page]);
  }

  /// Content equality, not just id/order -- this backs the background
  /// sync's "did anything actually change" check after a mutation like star/
  /// react/edit/delete. Comparing ids alone missed the very mutation this
  /// sync exists to reconcile: starring a message that isn't the thread's
  /// latest never appears in [toggleMessageStar]'s summary-only response
  /// (see [_reconcileMutatedThread]/[_isSummaryMessageSnapshot]), so the
  /// authoritative refetch here is the only place the toggled state lands
  /// locally -- an id-only check saw the same ids in the same order and
  /// bailed out before applying it, leaving the message looking un-starred
  /// until something else happened to refresh the thread.
  bool _messageListsEquivalent(
    List<ChatMessage> left,
    List<ChatMessage> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (!_messagesContentEqual(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  bool _messagesContentEqual(ChatMessage a, ChatMessage b) {
    return a.id == b.id &&
        a.text == b.text &&
        a.deliveryState == b.deliveryState &&
        a.isDeleted == b.isDeleted &&
        a.isEdited == b.isEdited &&
        a.isStarred == b.isStarred &&
        a.attachments.length == b.attachments.length &&
        mapEquals(a.reactions, b.reactions);
  }

  List<ChatThread> _reconcileMutatedThread({
    required List<ChatThread> incoming,
    required String mutatedThreadId,
  }) {
    if (!_fullyLoadedThreadIds.contains(mutatedThreadId)) {
      return incoming.map((thread) {
        if (thread.id != mutatedThreadId) {
          return _mergeIncomingThread(thread);
        }
        final cached = threadById(mutatedThreadId);
        if (cached == null || thread.messages.isEmpty) {
          return thread;
        }
        return thread.copyWith(
          messages: _mergeMessages(cached.messages, thread.messages),
        );
      }).toList(growable: false);
    }

    final incomingThread = incoming.cast<ChatThread?>().firstWhere(
        (thread) => thread?.id == mutatedThreadId,
        orElse: () => null);
    final cachedThread = threadById(mutatedThreadId);
    if (incomingThread == null || cachedThread == null) {
      return _mergeIncomingThreads(incoming);
    }

    if (incomingThread.messages.isEmpty) {
      return incoming
          .map(
            (thread) => thread.id == mutatedThreadId
                ? incomingThread
                : _mergeIncomingThread(thread),
          )
          .toList(growable: false);
    }

    if (_isSummaryMessageSnapshot(
      incomingThread.messages,
      cachedThread.messages,
    )) {
      unawaited(_syncOpenThreadMessagesInBackground(mutatedThreadId));
      return incoming
          .map(
            (thread) => thread.id == mutatedThreadId
                ? incomingThread.copyWith(
                    messages: _mergeMessages(
                      cachedThread.messages,
                      incomingThread.messages,
                    ),
                  )
                : _mergeIncomingThread(thread),
          )
          .toList(growable: false);
    }

    return incoming
        .map(
          (thread) => thread.id == mutatedThreadId
              ? incomingThread
              : _mergeIncomingThread(thread),
        )
        .toList(growable: false);
  }

  Future<bool> _runThreadMutation(
    String threadId,
    Future<List<ChatThread>> Function() action, {
    required String fallbackError,
    VoidCallback? afterSuccess,
    bool clearSearch = true,
    bool notifyWhileBusy = true,
  }) async {
    _busyThreadIds.add(threadId);
    _errorMessage = null;
    if (notifyWhileBusy) {
      notifyListeners();
    }

    var didSucceed = false;

    try {
      final latestBeforeMutation = threadById(threadId)?.latestMessage?.id;
      final incoming = await action();
      _threads = _reconcileMutatedThread(
        incoming: incoming,
        mutatedThreadId: threadId,
      );
      if (_fullyLoadedThreadIds.contains(threadId)) {
        final latestAfterMutation = threadById(threadId)?.latestMessage?.id;
        if (latestAfterMutation == latestBeforeMutation) {
          await _syncOpenThreadMessagesInBackground(threadId);
        } else {
          unawaited(_syncOpenThreadMessagesInBackground(threadId));
        }
      } else if (!_loadingMessageThreadIds.contains(threadId)) {
        unawaited(ensureThreadMessagesLoaded(threadId));
      }
      if (clearSearch && _showArchivedOnly) {
        final thread = threadById(threadId);
        if (thread != null && !thread.isArchived) {
          _showArchivedOnly = false;
        }
      }
      afterSuccess?.call();
      didSucceed = true;
    } on ChatRepositoryException catch (error) {
      _errorMessage = error.message;
      if (_fullyLoadedThreadIds.contains(threadId)) {
        await _syncOpenThreadMessagesInBackground(
          threadId,
          authoritative: true,
        );
      }
    } catch (_) {
      _errorMessage = fallbackError;
      if (_fullyLoadedThreadIds.contains(threadId)) {
        await _syncOpenThreadMessagesInBackground(
          threadId,
          authoritative: true,
        );
      }
    }

    _busyThreadIds.remove(threadId);
    notifyListeners();
    return didSucceed;
  }

  void _hideStoryForDeletedThread(ChatThread thread) {
    _hiddenStoryKeys.add(_storyParticipantKey(
      avatarLabel: thread.avatarLabel,
      name: thread.name,
    ));
    _hiddenStoryKeys.add('thread:${thread.id}');
    final participantUid = thread.participantUid;
    if (participantUid != null && participantUid.isNotEmpty) {
      _hiddenStoryKeys.add('uid:$participantUid');
      _hiddenStoryKeys
          .add('thread:${_canonicalDirectThreadId(participantUid)}');
    }
  }

  void _unhideStoryForParticipant({
    required String participantUid,
    required String avatarLabel,
    required String name,
  }) {
    _hiddenStoryKeys.remove(_storyParticipantKey(
      avatarLabel: avatarLabel,
      name: name,
    ));
    _hiddenStoryKeys.remove('uid:$participantUid');
    _hiddenStoryKeys
        .remove('thread:${_canonicalDirectThreadId(participantUid)}');
    _hiddenStoryKeys.remove('thread:$participantUid');
  }

  String _storyParticipantKey({
    required String avatarLabel,
    required String name,
  }) {
    return '${avatarLabel.trim().toLowerCase()}|${name.trim().toLowerCase()}';
  }

  String _canonicalDirectThreadId(String participantUid) {
    if (participantUid.startsWith('uid-')) {
      return participantUid.substring(4);
    }
    return participantUid;
  }

  bool _matchesHiddenStoryKey({
    required String key,
    required String avatarLabel,
    required String name,
    String? participantUid,
    String? threadId,
  }) {
    if (key.startsWith('uid:')) {
      final hiddenUid = key.substring(4);
      if (participantUid == hiddenUid) {
        return true;
      }
      if (threadId == _canonicalDirectThreadId(hiddenUid)) {
        return true;
      }
      return false;
    }
    if (key.startsWith('thread:')) {
      final hiddenThreadId = key.substring(7);
      if (threadId == hiddenThreadId) {
        return true;
      }
      if (participantUid != null &&
          _canonicalDirectThreadId(participantUid) == hiddenThreadId) {
        return true;
      }
      return false;
    }

    final parts = key.split('|');
    if (parts.length != 2) {
      return false;
    }
    final normalizedAvatar = avatarLabel.trim().toLowerCase();
    final normalizedName = name.trim().toLowerCase();
    if (normalizedAvatar != parts[0]) {
      return false;
    }
    final hiddenName = parts[1];
    return normalizedName == hiddenName ||
        normalizedName.startsWith('$hiddenName ') ||
        hiddenName.startsWith('$normalizedName ') ||
        normalizedName.startsWith(hiddenName) ||
        hiddenName.startsWith(normalizedName);
  }
}
