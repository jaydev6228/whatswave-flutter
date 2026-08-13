import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/core/permissions/device_location_service.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/chat_repository.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';
import 'package:whatswave/features/chats/domain/chat_thread.dart';
import 'package:whatswave/features/chats/domain/message_reply_preview.dart';
import 'package:whatswave/features/chats/domain/story_reply_context.dart';

void main() {
  group('ChatsController', () {
    late ChatsController controller;

    setUp(() {
      controller = ChatsController(
        repository: FakeChatRepository(
          initialThreads: DemoData.buildChatThreads(),
          latency: Duration.zero,
        ),
      );
    });

    test('loads chats and tracks active versus archived threads', () async {
      await controller.loadThreads();

      expect(controller.hasLoaded, isTrue);
      expect(controller.activeCount, 4);
      expect(controller.archivedCount, 1);
      expect(controller.visibleThreads.every((thread) => !thread.isArchived),
          isTrue);
      expect(controller.visibleThreads.first.name, 'Design Sprint');
    });

    test(
        'excludes community group threads from every Chats list view, '
        'but still resolves them by id', () async {
      await controller.loadThreads();
      final activeCountBefore = controller.activeCount;
      final unreadCountBefore = controller.unreadThreadCount;

      final threadId = await controller.createGroup(
        name: 'Trailhead Announcements',
        memberUids: const ['someone-uid'],
        isCommunityGroup: true,
      );

      expect(threadId, isNotNull);
      // A community thread starts with no messages, so it wouldn't show up
      // in list views anyway until someone sends the first message -- send
      // one so this test actually exercises the isCommunityGroup filter,
      // not just the "no messages yet" filter every fresh thread hits.
      await controller.sendTextMessage(threadId: threadId!, text: 'Welcome!');

      expect(controller.activeCount, activeCountBefore);
      expect(
        controller.inboxThreads().any((thread) => thread.id == threadId),
        isFalse,
      );
      expect(
        controller.visibleThreads.any((thread) => thread.id == threadId),
        isFalse,
      );
      expect(controller.unreadThreadCount, unreadCountBefore);

      // threadById is what ConversationScreen relies on when opened from
      // the Communities flow -- it must still resolve the thread even
      // though every list view hides it.
      final thread = controller.threadById(threadId);
      expect(thread, isNotNull);
      expect(thread!.isCommunityGroup, isTrue);
      expect(thread.name, 'Trailhead Announcements');
    });

    test('a regular new group is not marked as a community group', () async {
      await controller.loadThreads();

      final threadId = await controller.createGroup(
        name: 'Weekend Trip',
        memberUids: const ['friend-uid'],
      );

      expect(threadId, isNotNull);
      expect(controller.threadById(threadId!)?.isCommunityGroup, isFalse);
    });

    test(
        'a regular new group appears in the chat list immediately, before '
        'any message is sent', () async {
      await controller.loadThreads();

      final threadId = await controller.createGroup(
        name: 'Weekend Trip',
        memberUids: const ['friend-uid'],
      );

      expect(threadId, isNotNull);
      expect(controller.threadById(threadId!)?.messages, isEmpty);
      expect(
        controller.visibleThreads.any((thread) => thread.id == threadId),
        isTrue,
      );
      expect(
        controller.inboxThreads().any((thread) => thread.id == threadId),
        isTrue,
      );
    });

    test('filters by unread state and search query', () async {
      await controller.loadThreads();

      controller.updateFilter(ChatListFilter.unread);
      expect(
        controller.visibleThreads.map((thread) => thread.name),
        containsAll(<String>['Ava Patel', 'Design Sprint', 'Family']),
      );
      expect(
        controller.visibleThreads.any((thread) => thread.name == 'Product Ops'),
        isFalse,
      );

      controller.updateSearchQuery('voice note');
      expect(controller.visibleThreads.single.name, 'Family');
    });

    test('archives and unarchives threads across inbox views', () async {
      await controller.loadThreads();

      await controller.setThreadArchived(
          threadId: 'ava-patel', isArchived: true);
      expect(controller.threadById('ava-patel')?.isArchived, isTrue);
      expect(
        controller.visibleThreads.any((thread) => thread.id == 'ava-patel'),
        isFalse,
      );

      controller.toggleArchivedOnly();
      expect(
        controller.visibleThreads.any((thread) => thread.id == 'ava-patel'),
        isTrue,
      );

      await controller.setThreadArchived(
          threadId: 'ava-patel', isArchived: false);
      expect(controller.showArchivedOnly, isFalse);
      expect(controller.threadById('ava-patel')?.isArchived, isFalse);
    });

    test('blocks and unblocks a contact', () async {
      await controller.loadThreads();

      await controller.setThreadBlocked(threadId: 'ava-patel', isBlocked: true);
      expect(controller.threadById('ava-patel')?.isBlocked, isTrue);

      await controller.setThreadBlocked(
          threadId: 'ava-patel', isBlocked: false);
      expect(controller.threadById('ava-patel')?.isBlocked, isFalse);
    });

    test('clears a thread\'s messages without deleting the thread', () async {
      await controller.loadThreads();
      expect(controller.threadById('ava-patel')!.messages, isNotEmpty);

      await controller.clearThreadMessages('ava-patel');

      expect(controller.threadById('ava-patel'), isNotNull);
      expect(controller.threadById('ava-patel')!.messages, isEmpty);
    });

    test('common groups are empty for demo threads with no real uid', () async {
      await controller.loadThreads();

      final groups = await controller.groupThreadsSharedWith('ava-patel');

      expect(groups, isEmpty);
    });

    test('marks unread chats as read when opened', () async {
      await controller.loadThreads();

      expect(controller.threadById('family')?.unreadCount, 12);

      controller.openThread('family');

      expect(controller.threadById('family')?.unreadCount, 0);
      await Future<void>.delayed(Duration.zero);
    });

    test('sends text and attachment messages into a thread', () async {
      await controller.loadThreads();

      await controller.sendTextMessage(
        threadId: 'ava-patel',
        text: 'I will send the polished handoff in five.',
      );
      await controller.sendAttachmentMessage(
        threadId: 'ava-patel',
        attachments: const [
          ChatAttachment(
            id: 'test-photo',
            type: ChatAttachmentType.photo,
            title: 'Polished handoff',
            details: 'Ready for review',
            tintColor: Color(0xFF25D366),
            aspectRatio: 1.1,
          ),
        ],
      );

      final thread = controller.threadById('ava-patel');
      expect(thread, isNotNull);
      expect(
          thread!.messages.last.attachments.single.title, 'Polished handoff');
      expect(thread.messages[thread.messages.length - 2].text,
          'I will send the polished handoff in five.');
    });

    test('toggles a message reaction on, then off again', () async {
      await controller.loadThreads();
      final messageId = controller.threadById('ava-patel')!.messages.first.id;

      await controller.toggleMessageReaction(
        threadId: 'ava-patel',
        messageId: messageId,
        emoji: '❤️',
      );

      var message = controller
          .threadById('ava-patel')!
          .messages
          .firstWhere((entry) => entry.id == messageId);
      expect(message.hasReactions, isTrue);
      expect(message.reactions.values, contains('❤️'));

      await controller.toggleMessageReaction(
        threadId: 'ava-patel',
        messageId: messageId,
        emoji: '❤️',
      );

      message = controller
          .threadById('ava-patel')!
          .messages
          .firstWhere((entry) => entry.id == messageId);
      expect(message.hasReactions, isFalse);
    });

    test('replaces an existing reaction with a different emoji', () async {
      await controller.loadThreads();
      final messageId = controller.threadById('ava-patel')!.messages.first.id;

      await controller.toggleMessageReaction(
        threadId: 'ava-patel',
        messageId: messageId,
        emoji: '👍',
      );
      await controller.toggleMessageReaction(
        threadId: 'ava-patel',
        messageId: messageId,
        emoji: '😮',
      );

      final message = controller
          .threadById('ava-patel')!
          .messages
          .firstWhere((entry) => entry.id == messageId);
      expect(message.reactions.values, ['😮']);
    });

    test('surfaces send failures and keeps the existing thread history intact',
        () async {
      final failingController = ChatsController(
        repository: _SendFailingChatRepository(),
      );

      await failingController.loadThreads();
      final originalCount =
          failingController.threadById('ava-patel')!.messages.length;

      final didSend = await failingController.sendTextMessage(
        threadId: 'ava-patel',
        text: 'This should fail.',
      );

      expect(didSend, isFalse);
      expect(
        failingController.errorMessage,
        'Message service offline',
      );
      expect(
        failingController.threadById('ava-patel')!.messages.length,
        originalCount,
      );
    });

    test('surfaces repository failures on initial load', () async {
      final failingController = ChatsController(
        repository: _FailingChatRepository(),
      );

      await failingController.loadThreads();

      expect(failingController.hasLoaded, isFalse);
      expect(failingController.visibleThreads, isEmpty);
      expect(failingController.errorMessage, 'Network went away');
    });

    test('shares the current location once permission is granted', () async {
      final locationController = ChatsController(
        repository: FakeChatRepository(
          initialThreads: DemoData.buildChatThreads(),
          latency: Duration.zero,
        ),
        permissionService: MemoryAppPermissionService(),
        locationService: const _FakeDeviceLocationService(
          fix: DeviceLocationFix(latitude: 35.6595, longitude: 139.7005),
        ),
      );
      await locationController.loadThreads();

      final outcome = await locationController.sendCurrentLocation(
        threadId: 'ava-patel',
      );

      expect(outcome, LocationShareOutcome.sent);
      final attachment = locationController
          .threadById('ava-patel')!
          .messages
          .last
          .attachments
          .single;
      expect(attachment.type, ChatAttachmentType.location);
      expect(attachment.latitude, 35.6595);
      expect(attachment.longitude, 139.7005);
      expect(attachment.hasCoordinates, isTrue);
    });

    test(
        'reports permission-denied without touching errorMessage or sending anything',
        () async {
      final deniedController = ChatsController(
        repository: FakeChatRepository(
          initialThreads: DemoData.buildChatThreads(),
          latency: Duration.zero,
        ),
        permissionService: MemoryAppPermissionService(
          grantLocationOnRequest: false,
        ),
        locationService: const _FakeDeviceLocationService(
          fix: DeviceLocationFix(latitude: 35.6595, longitude: 139.7005),
        ),
      );
      await deniedController.loadThreads();
      final originalCount =
          deniedController.threadById('ava-patel')!.messages.length;

      final outcome =
          await deniedController.sendCurrentLocation(threadId: 'ava-patel');

      expect(outcome, LocationShareOutcome.permissionDenied);
      expect(deniedController.errorMessage, isNull);
      expect(
        deniedController.threadById('ava-patel')!.messages.length,
        originalCount,
      );
    });

    test('surfaces device location failures', () async {
      final failingLocationController = ChatsController(
        repository: FakeChatRepository(
          initialThreads: DemoData.buildChatThreads(),
          latency: Duration.zero,
        ),
        permissionService: MemoryAppPermissionService(),
        locationService: const _FakeDeviceLocationService(
          error: DeviceLocationException('GPS is unavailable right now.'),
        ),
      );
      await failingLocationController.loadThreads();

      final outcome = await failingLocationController.sendCurrentLocation(
        threadId: 'ava-patel',
      );

      expect(outcome, LocationShareOutcome.failed);
      expect(failingLocationController.errorMessage, isNull);
      expect(
        failingLocationController.locationFailureMessage,
        'GPS is unavailable right now.',
      );
    });

    test(
        'sendCurrentLocation keeps prior messages when repository returns summaries',
        () async {
      final fullThreads = DemoData.buildChatThreads();
      final controller = ChatsController(
        repository: _SummaryOnlyAfterSendRepository(
          delegate: FakeChatRepository(
            initialThreads: fullThreads,
            latency: Duration.zero,
          ),
        ),
        permissionService: MemoryAppPermissionService(),
        locationService: const _FakeDeviceLocationService(
          fix: DeviceLocationFix(latitude: 35.6595, longitude: 139.7005),
        ),
      );

      await controller.loadThreads();
      await controller.ensureThreadMessagesLoaded('ava-patel');

      final messagesBefore =
          controller.threadById('ava-patel')!.messages.length;
      expect(messagesBefore, greaterThan(1));

      final outcome = await controller.sendCurrentLocation(
        threadId: 'ava-patel',
      );

      expect(outcome, LocationShareOutcome.sent);
      expect(
        controller.threadById('ava-patel')!.messages.length,
        greaterThan(messagesBefore),
      );
    });

    test(
        'sendAttachmentMessage keeps prior messages when repository returns summaries',
        () async {
      final fullThreads = DemoData.buildChatThreads();
      final controller = ChatsController(
        repository: _SummaryOnlyAfterSendRepository(
          delegate: FakeChatRepository(
            initialThreads: fullThreads,
            latency: Duration.zero,
          ),
        ),
      );

      await controller.loadThreads();
      await controller.ensureThreadMessagesLoaded('ava-patel');

      final messagesBefore =
          controller.threadById('ava-patel')!.messages.length;
      expect(messagesBefore, greaterThan(1));

      final didSend = await controller.sendAttachmentMessage(
        threadId: 'ava-patel',
        attachments: const [
          ChatAttachment(
            id: 'test-file',
            type: ChatAttachmentType.file,
            title: 'Notes.docx',
            details: '12 KB • shared from Files',
            tintColor: AppPalette.amber,
          ),
        ],
      );

      expect(didSend, isTrue);
      expect(
        controller.threadById('ava-patel')!.messages.length,
        greaterThan(messagesBefore),
      );
    });

    test(
        'sendTextMessage keeps prior messages when repository returns summaries',
        () async {
      final fullThreads = DemoData.buildChatThreads();
      final controller = ChatsController(
        repository: _SummaryOnlyAfterSendRepository(
          delegate: FakeChatRepository(
            initialThreads: fullThreads,
            latency: Duration.zero,
          ),
        ),
      );

      await controller.loadThreads();
      await controller.ensureThreadMessagesLoaded('ava-patel');

      final messagesBefore =
          controller.threadById('ava-patel')!.messages.length;
      expect(messagesBefore, greaterThan(1));

      final didSend = await controller.sendTextMessage(
        threadId: 'ava-patel',
        text: 'Hi',
      );

      expect(didSend, isTrue);
      expect(
        controller.threadById('ava-patel')!.messages.length,
        greaterThan(messagesBefore),
      );
    });

    test(
        'second summary send keeps file and text when repository returns summaries',
        () async {
      final fullThreads = DemoData.buildChatThreads();
      final controller = ChatsController(
        repository: _SummaryOnlyAfterSendRepository(
          delegate: FakeChatRepository(
            initialThreads: fullThreads,
            latency: Duration.zero,
          ),
        ),
      );

      await controller.loadThreads();
      await controller.ensureThreadMessagesLoaded('ava-patel');

      final messagesBefore =
          controller.threadById('ava-patel')!.messages.length;

      final didSendFile = await controller.sendAttachmentMessage(
        threadId: 'ava-patel',
        attachments: const [
          ChatAttachment(
            id: 'test-file',
            type: ChatAttachmentType.file,
            title: 'Notes.docx',
            details: '12 KB • shared from Files',
            tintColor: AppPalette.amber,
          ),
        ],
      );
      expect(didSendFile, isTrue);

      final afterFile =
          controller.threadById('ava-patel')!.messages.length;
      expect(afterFile, greaterThan(messagesBefore));

      final didSendText = await controller.sendTextMessage(
        threadId: 'ava-patel',
        text: 'Hi',
      );
      expect(didSendText, isTrue);
      expect(
        controller.threadById('ava-patel')!.messages.length,
        greaterThan(afterFile),
      );
    });

    test('watchThreads summary update does not shrink visible history', () async {
      final repo = _WatchSummaryRepository(
        delegate: FakeChatRepository(
          initialThreads: DemoData.buildChatThreads(),
          latency: Duration.zero,
        ),
      );
      final controller = ChatsController(repository: repo);

      await controller.loadThreads();
      final countBefore =
          controller.threadById('ava-patel')!.messages.length;
      expect(countBefore, greaterThan(1));
      expect(controller.hasFullyLoadedMessages('ava-patel'), isFalse);

      repo.emitSummaryInbox();
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.threadById('ava-patel')!.messages.length,
        countBefore,
      );
    });

    test(
        'deleteMessage removes message optimistically on fully loaded thread',
        () async {
      await controller.loadThreads();
      await controller.ensureThreadMessagesLoaded('ava-patel');

      final thread = controller.threadById('ava-patel')!;
      final messageId = thread.messages.first.id;
      final countBefore = thread.messages.length;

      final didDelete = await controller.deleteMessage(
        threadId: 'ava-patel',
        messageId: messageId,
        forEveryone: false,
      );

      expect(didDelete, isTrue);
      expect(
        controller.threadById('ava-patel')!.messages.length,
        countBefore - 1,
      );
      expect(
        controller.threadById('ava-patel')!.messages.any(
              (message) => message.id == messageId,
            ),
        isFalse,
      );
    });

    test(
        'stale summary response after send still restores full history via sync',
        () async {
      final fullThreads = DemoData.buildChatThreads();
      final controller = ChatsController(
        repository: _StaleSummaryAfterSendRepository(
          delegate: FakeChatRepository(
            initialThreads: fullThreads,
            latency: Duration.zero,
          ),
        ),
      );

      await controller.loadThreads();
      await controller.ensureThreadMessagesLoaded('ava-patel');

      final messagesBefore =
          controller.threadById('ava-patel')!.messages.length;
      expect(messagesBefore, greaterThan(1));

      final didSend = await controller.sendTextMessage(
        threadId: 'ava-patel',
        text: 'Another line',
      );

      expect(didSend, isTrue);
      expect(
        controller.threadById('ava-patel')!.messages.length,
        greaterThan(messagesBefore),
      );
    });

    test(
        'background sync does not rebuild when server history already matches',
        () async {
      final fullThreads = DemoData.buildChatThreads();
      final controller = ChatsController(
        repository: _SummaryOnlyAfterSendRepository(
          delegate: FakeChatRepository(
            initialThreads: fullThreads,
            latency: Duration.zero,
          ),
        ),
      );

      await controller.loadThreads();
      await controller.ensureThreadMessagesLoaded('ava-patel');
      var rebuildCount = 0;
      controller.addListener(() => rebuildCount++);

      final didSend = await controller.sendTextMessage(
        threadId: 'ava-patel',
        text: 'Smooth send',
      );
      expect(didSend, isTrue);

      final rebuildsAfterSend = rebuildCount;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(rebuildCount, rebuildsAfterSend);
    });

    test('deleting a 1:1 chat hides that contact story until chat restarts',
        () async {
      await controller.loadThreads();
      final ava = controller.threadById('ava-patel')!;
      expect(controller.shouldShowStoryForThread(ava), isTrue);

      final didDelete = await controller.deleteThread('ava-patel');
      expect(didDelete, isTrue);
      expect(controller.isStoryHidden(
        avatarLabel: ava.avatarLabel,
        name: ava.name,
      ), isTrue);

      final threadId = await controller.startThreadWith(
        participantUid: 'uid-ava-patel',
        participantName: ava.name,
        avatarLabel: ava.avatarLabel,
        accentColor: ava.accentColor,
      );
      expect(threadId, 'ava-patel');
      expect(controller.threadById('ava-patel'), isNotNull);
      expect(controller.isStoryHidden(
        avatarLabel: ava.avatarLabel,
        name: 'Ava',
      ), isFalse);
    });
  });
}

class _FakeDeviceLocationService implements DeviceLocationService {
  const _FakeDeviceLocationService({this.fix, this.error});

  final DeviceLocationFix? fix;
  final DeviceLocationException? error;

  @override
  Future<DeviceLocationFix> getCurrentLocation() async {
    if (error != null) {
      throw error!;
    }
    return fix!;
  }
}

/// Mimics Firestore mutations that refetch the inbox with one preview message
/// per thread instead of full histories.
class _SummaryOnlyAfterSendRepository implements ChatRepository {
  _SummaryOnlyAfterSendRepository({required FakeChatRepository delegate})
      : _delegate = delegate;

  final FakeChatRepository _delegate;

  List<ChatThread> _summaryOnly(List<ChatThread> threads) {
    return threads
        .map(
          (thread) => thread.messages.isEmpty
              ? thread
              : thread.copyWith(
                  messages: [thread.messages.last],
                ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ChatThread>> fetchThreads() => _delegate.fetchThreads();

  @override
  Stream<List<ChatThread>>? watchThreads() => _delegate.watchThreads();

  @override
  Future<ChatThread> fetchThreadWithMessages(String threadId) =>
      _delegate.fetchThreadWithMessages(threadId);

  @override
  Future<void> markThreadRead(String threadId) =>
      _delegate.markThreadRead(threadId);

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
    MessageReplyPreview? replyPreview,
  }) async {
    return _summaryOnly(
      await _delegate.sendAttachmentMessage(
        threadId: threadId,
        attachments: attachments,
        caption: caption,
        replyPreview: replyPreview,
      ),
    );
  }

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
    StoryReplyContext? storyReplyContext,
    MessageReplyPreview? replyPreview,
  }) async {
    return _summaryOnly(
      await _delegate.sendTextMessage(
        threadId: threadId,
        text: text,
        storyReplyContext: storyReplyContext,
        replyPreview: replyPreview,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Emits summary-only inbox snapshots on [watchThreads], mimicking Firestore
/// live updates while keeping full histories available on first load.
class _WatchSummaryRepository implements ChatRepository {
  _WatchSummaryRepository({required FakeChatRepository delegate})
      : _delegate = delegate;

  final FakeChatRepository _delegate;
  final StreamController<List<ChatThread>> _updates =
      StreamController<List<ChatThread>>.broadcast();

  List<ChatThread> _summaryOnly(List<ChatThread> threads) {
    return threads
        .map(
          (thread) => thread.messages.isEmpty
              ? thread
              : thread.copyWith(
                  messages: [thread.messages.last],
                ),
        )
        .toList(growable: false);
  }

  void emitSummaryInbox() {
    _delegate.fetchThreads().then((threads) {
      _updates.add(_summaryOnly(threads));
    });
  }

  @override
  Future<List<ChatThread>> fetchThreads() => _delegate.fetchThreads();

  @override
  Stream<List<ChatThread>>? watchThreads() => _updates.stream;

  @override
  Future<ChatThread> fetchThreadWithMessages(String threadId) =>
      _delegate.fetchThreadWithMessages(threadId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Returns the previous latest message after send, reproducing a stale
/// Firestore limit(1) read racing the new write.
class _StaleSummaryAfterSendRepository implements ChatRepository {
  _StaleSummaryAfterSendRepository({required FakeChatRepository delegate})
      : _delegate = delegate;

  final FakeChatRepository _delegate;
  List<ChatThread>? _preSendSnapshot;

  List<ChatThread> _summaryOnly(List<ChatThread> threads) {
    return threads
        .map(
          (thread) => thread.messages.isEmpty
              ? thread
              : thread.copyWith(
                  messages: [thread.messages.last],
                ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ChatThread>> fetchThreads() => _delegate.fetchThreads();

  @override
  Stream<List<ChatThread>>? watchThreads() => _delegate.watchThreads();

  @override
  Future<ChatThread> fetchThreadWithMessages(String threadId) =>
      _delegate.fetchThreadWithMessages(threadId);

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
    StoryReplyContext? storyReplyContext,
    MessageReplyPreview? replyPreview,
  }) async {
    _preSendSnapshot = _summaryOnly(await _delegate.fetchThreads());
    await _delegate.sendTextMessage(
      threadId: threadId,
      text: text,
      storyReplyContext: storyReplyContext,
      replyPreview: replyPreview,
    );
    return _preSendSnapshot!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingChatRepository implements ChatRepository {
  @override
  Future<List<ChatThread>> fetchThreads() {
    throw const ChatRepositoryException('Network went away');
  }

  @override
  Stream<List<ChatThread>>? watchThreads() => null;

  @override
  Future<List<ChatThread>> deleteThread(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<ChatThread> startThread({
    required String participantUid,
    required String participantName,
    required String avatarLabel,
    required Color accentColor,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> setThreadBlocked({
    required String threadId,
    required bool isBlocked,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> clearThreadMessages(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> groupThreadsSharedWith(String participantUid) {
    throw UnimplementedError();
  }

  @override
  Future<ChatThread> fetchThreadWithMessages(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<void> markThreadRead(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
    bool isCommunityGroup = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
    MessageReplyPreview? replyPreview,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> toggleMessageReaction({
    required String threadId,
    required String messageId,
    required String emoji,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
    StoryReplyContext? storyReplyContext,
    MessageReplyPreview? replyPreview,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> editMessage({
    required String threadId,
    required String messageId,
    required String text,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> deleteMessage({
    required String threadId,
    required String messageId,
    required bool forEveryone,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> setThreadArchived({
    required String threadId,
    required bool isArchived,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> addGroupMembers({
    required String threadId,
    required List<String> memberUids,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> removeGroupMember({
    required String threadId,
    required String memberUid,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> leaveGroup(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> setGroupAdmin({
    required String threadId,
    required String memberUid,
    required bool isAdmin,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> renameGroup({
    required String threadId,
    required String name,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> updateGroupDescription({
    required String threadId,
    required String description,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> updateGroupAvatar({
    required String threadId,
    required File photo,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> deleteGroupAvatar(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> toggleMessageStar({
    required String threadId,
    required String messageId,
  }) {
    throw UnimplementedError();
  }
}

class _SendFailingChatRepository implements ChatRepository {
  _SendFailingChatRepository()
      : _delegate = FakeChatRepository(
          initialThreads: DemoData.buildChatThreads(),
          latency: Duration.zero,
        );

  final FakeChatRepository _delegate;

  @override
  Future<List<ChatThread>> fetchThreads() => _delegate.fetchThreads();

  @override
  Stream<List<ChatThread>>? watchThreads() => _delegate.watchThreads();

  @override
  Future<List<ChatThread>> deleteThread(String threadId) =>
      _delegate.deleteThread(threadId);

  @override
  Future<ChatThread> startThread({
    required String participantUid,
    required String participantName,
    required String avatarLabel,
    required Color accentColor,
  }) {
    return _delegate.startThread(
      participantUid: participantUid,
      participantName: participantName,
      avatarLabel: avatarLabel,
      accentColor: accentColor,
    );
  }

  @override
  Future<ChatThread> fetchThreadWithMessages(String threadId) =>
      _delegate.fetchThreadWithMessages(threadId);

  @override
  Future<void> markThreadRead(String threadId) =>
      _delegate.markThreadRead(threadId);

  @override
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
    bool isCommunityGroup = false,
  }) =>
      _delegate.createGroup(
        name: name,
        memberUids: memberUids,
        isCommunityGroup: isCommunityGroup,
      );

  @override
  Future<List<ChatThread>> setThreadBlocked({
    required String threadId,
    required bool isBlocked,
  }) =>
      _delegate.setThreadBlocked(threadId: threadId, isBlocked: isBlocked);

  @override
  Future<List<ChatThread>> clearThreadMessages(String threadId) =>
      _delegate.clearThreadMessages(threadId);

  @override
  Future<List<ChatThread>> groupThreadsSharedWith(String participantUid) =>
      _delegate.groupThreadsSharedWith(participantUid);

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
    MessageReplyPreview? replyPreview,
  }) {
    throw const ChatRepositoryException('Message service offline');
  }

  @override
  Future<List<ChatThread>> toggleMessageReaction({
    required String threadId,
    required String messageId,
    required String emoji,
  }) =>
      _delegate.toggleMessageReaction(
        threadId: threadId,
        messageId: messageId,
        emoji: emoji,
      );

  @override
  Future<List<ChatThread>> toggleMessageStar({
    required String threadId,
    required String messageId,
  }) =>
      _delegate.toggleMessageStar(threadId: threadId, messageId: messageId);

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
    StoryReplyContext? storyReplyContext,
    MessageReplyPreview? replyPreview,
  }) {
    throw const ChatRepositoryException('Message service offline');
  }

  @override
  Future<List<ChatThread>> editMessage({
    required String threadId,
    required String messageId,
    required String text,
  }) =>
      _delegate.editMessage(
          threadId: threadId, messageId: messageId, text: text);

  @override
  Future<List<ChatThread>> deleteMessage({
    required String threadId,
    required String messageId,
    required bool forEveryone,
  }) =>
      _delegate.deleteMessage(
        threadId: threadId,
        messageId: messageId,
        forEveryone: forEveryone,
      );

  @override
  Future<List<ChatThread>> setThreadArchived({
    required String threadId,
    required bool isArchived,
  }) =>
      _delegate.setThreadArchived(
        threadId: threadId,
        isArchived: isArchived,
      );

  @override
  Future<List<ChatThread>> addGroupMembers({
    required String threadId,
    required List<String> memberUids,
  }) =>
      _delegate.addGroupMembers(threadId: threadId, memberUids: memberUids);

  @override
  Future<List<ChatThread>> removeGroupMember({
    required String threadId,
    required String memberUid,
  }) =>
      _delegate.removeGroupMember(threadId: threadId, memberUid: memberUid);

  @override
  Future<List<ChatThread>> leaveGroup(String threadId) =>
      _delegate.leaveGroup(threadId);

  @override
  Future<List<ChatThread>> setGroupAdmin({
    required String threadId,
    required String memberUid,
    required bool isAdmin,
  }) =>
      _delegate.setGroupAdmin(
        threadId: threadId,
        memberUid: memberUid,
        isAdmin: isAdmin,
      );

  @override
  Future<List<ChatThread>> renameGroup({
    required String threadId,
    required String name,
  }) =>
      _delegate.renameGroup(threadId: threadId, name: name);

  @override
  Future<List<ChatThread>> updateGroupDescription({
    required String threadId,
    required String description,
  }) =>
      _delegate.updateGroupDescription(
        threadId: threadId,
        description: description,
      );

  @override
  Future<List<ChatThread>> updateGroupAvatar({
    required String threadId,
    required File photo,
  }) =>
      _delegate.updateGroupAvatar(threadId: threadId, photo: photo);

  @override
  Future<List<ChatThread>> deleteGroupAvatar(String threadId) =>
      _delegate.deleteGroupAvatar(threadId);
}
