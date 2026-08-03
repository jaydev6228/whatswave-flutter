import 'package:flutter/material.dart';

import '../data/chat_repository.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_thread.dart';

enum ChatListFilter { all, unread, groups }

class ChatsController extends ChangeNotifier {
  ChatsController({required ChatRepository repository})
      : _repository = repository;

  final ChatRepository _repository;

  bool _hasLoaded = false;
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';
  ChatListFilter _selectedFilter = ChatListFilter.all;
  bool _showArchivedOnly = false;
  List<ChatThread> _threads = const <ChatThread>[];
  final Set<String> _busyThreadIds = <String>{};

  bool get hasLoaded => _hasLoaded;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  ChatListFilter get selectedFilter => _selectedFilter;
  bool get showArchivedOnly => _showArchivedOnly;
  List<ChatThread> get threads => List<ChatThread>.unmodifiable(_threads);
  int get archivedCount => _threads.where((thread) => thread.isArchived).length;
  int get activeCount => _threads.where((thread) => !thread.isArchived).length;

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
    final filteredThreads = _threads.where((thread) {
      // A thread startThreadWith() just created (or one someone opened
      // and never messaged) has no messages yet -- keep it out of every
      // list view until there's an actual conversation, same idea as an
      // empty status not showing up as a real update. threadById() still
      // finds it directly, so the conversation screen it was just opened
      // from keeps working.
      if (thread.messages.isEmpty) {
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

  bool isThreadBusy(String threadId) => _busyThreadIds.contains(threadId);

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

    try {
      _threads = await _repository.fetchThreads();
      _hasLoaded = true;
    } on ChatRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not load your chats right now.';
    }

    _isLoading = false;
    notifyListeners();
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
      _threads = await _repository.fetchThreads();
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

  Future<void> openThread(String threadId) async {
    final thread = threadById(threadId);
    if (thread == null || thread.unreadCount == 0) {
      return;
    }

    await _runThreadMutation(
      threadId,
      () => _repository.markThreadRead(threadId),
      fallbackError: 'We could not open that chat right now.',
    );
  }

  Future<bool> sendTextMessage({
    required String threadId,
    required String text,
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
      ),
      fallbackError: 'We could not send that message right now.',
      clearSearch: false,
    );
  }

  Future<bool> sendAttachmentMessage({
    required String threadId,
    required ChatAttachment attachment,
    String? caption,
  }) {
    return _runThreadMutation(
      threadId,
      () => _repository.sendAttachmentMessage(
        threadId: threadId,
        attachment: attachment,
        caption: caption,
      ),
      fallbackError: 'We could not send that attachment right now.',
      clearSearch: false,
    );
  }

  Future<bool> _runThreadMutation(
    String threadId,
    Future<List<ChatThread>> Function() action, {
    required String fallbackError,
    VoidCallback? afterSuccess,
    bool clearSearch = true,
  }) async {
    _busyThreadIds.add(threadId);
    _errorMessage = null;
    notifyListeners();

    var didSucceed = false;

    try {
      _threads = await action();
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
    } catch (_) {
      _errorMessage = fallbackError;
    }

    _busyThreadIds.remove(threadId);
    notifyListeners();
    return didSucceed;
  }
}
