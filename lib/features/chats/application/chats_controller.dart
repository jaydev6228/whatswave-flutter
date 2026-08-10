import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/permissions/app_permission_service.dart';
import '../../../core/permissions/device_location_service.dart';
import '../../calls/domain/call_permissions.dart';
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
  })  : _repository = repository,
        _permissionService = permissionService ?? MemoryAppPermissionService(),
        _locationService = locationService ?? GeolocatorDeviceLocationService();

  final ChatRepository _repository;
  final AppPermissionService _permissionService;
  final DeviceLocationService _locationService;
  StreamSubscription<List<ChatThread>>? _liveThreadsSubscription;

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
      _listenForLiveThreads();
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
      _threads = threads;
      notifyListeners();
    });
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
    return _runThreadMutation(
      threadId,
      () => _repository.deleteThread(threadId),
      fallbackError: 'We could not delete that chat right now.',
    );
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
    return _runThreadMutation(
      threadId,
      () => _repository.clearThreadMessages(threadId),
      fallbackError: 'We could not clear that chat right now.',
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
      _threads = await _repository.fetchThreads();
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
    return _runThreadMutation(
      threadId,
      () => _repository.deleteMessage(
        threadId: threadId,
        messageId: messageId,
        forEveryone: forEveryone,
      ),
      fallbackError: 'We could not delete that message right now.',
      clearSearch: false,
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
    );
  }

  Future<bool> toggleMessageReaction({
    required String threadId,
    required String messageId,
    required String emoji,
  }) {
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
    );
  }

  /// Every starred message across every thread (most recent first), paired
  /// with the thread it lives in -- backs the "Starred messages" screen.
  List<({ChatThread thread, ChatMessage message})> get starredMessages {
    final entries = <({ChatThread thread, ChatMessage message})>[];
    for (final thread in _threads) {
      for (final message in thread.messages) {
        if (message.isStarred) {
          entries.add((thread: thread, message: message));
        }
      }
    }
    entries.sort((a, b) => b.message.sentAt.compareTo(a.message.sentAt));
    return entries;
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
        _threads = await _repository.sendAttachmentMessage(
          threadId: threadId,
          attachments: [attachment],
          caption: caption,
        );
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
