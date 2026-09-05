import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/core/permissions/device_location_service.dart';
import 'package:whatswave/core/utils/user_profile_lookup.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/core/media/media_transfer.dart';
import 'package:whatswave/features/chats/data/chat_repository.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';
import 'package:whatswave/features/chats/domain/chat_message.dart';
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

      final afterFile = controller.threadById('ava-patel')!.messages.length;
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

    test('watchThreads summary update does not shrink visible history',
        () async {
      final repo = _WatchSummaryRepository(
        delegate: FakeChatRepository(
          initialThreads: DemoData.buildChatThreads(),
          latency: Duration.zero,
        ),
      );
      final controller = ChatsController(repository: repo);

      await controller.loadThreads();
      final countBefore = controller.threadById('ava-patel')!.messages.length;
      expect(countBefore, greaterThan(1));
      expect(controller.hasFullyLoadedMessages('ava-patel'), isFalse);

      repo.emitSummaryInbox();
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.threadById('ava-patel')!.messages.length,
        countBefore,
      );
    });

    test('deleteMessage removes message optimistically on fully loaded thread',
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

    test('background sync does not rebuild when server history already matches',
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
      expect(
          controller.isStoryHidden(
            avatarLabel: ava.avatarLabel,
            name: ava.name,
          ),
          isTrue);

      final threadId = await controller.startThreadWith(
        participantUid: 'uid-ava-patel',
        participantName: ava.name,
        avatarLabel: ava.avatarLabel,
        accentColor: ava.accentColor,
      );
      expect(threadId, 'ava-patel');
      expect(controller.threadById('ava-patel'), isNotNull);
      expect(
          controller.isStoryHidden(
            avatarLabel: ava.avatarLabel,
            name: 'Ava',
          ),
          isFalse);
    });

    test(
        'pages older message history in as the window grows, then stops '
        'once the thread is exhausted', () async {
      final pagedController = ChatsController(
        repository:
            _SummaryInboxRepository([_threadWithMessages('paged', 120)]),
      );
      addTearDown(pagedController.dispose);

      await pagedController.loadThreads();
      await pagedController.ensureThreadMessagesLoaded('paged');

      // Opening loads only the newest window, not the whole 120-message thread.
      var messages = pagedController.threadById('paged')!.messages;
      expect(messages.length, 50);
      expect(messages.first.id, 'm70');
      expect(messages.last.id, 'm119');
      expect(pagedController.hasMoreOlderMessages('paged'), isTrue);

      // Scrolling up pages the next-older window in, contiguously.
      await pagedController.loadOlderMessages('paged');
      messages = pagedController.threadById('paged')!.messages;
      expect(messages.length, 100);
      expect(messages.first.id, 'm20');
      expect(pagedController.hasMoreOlderMessages('paged'), isTrue);

      // The final partial window exhausts the history.
      await pagedController.loadOlderMessages('paged');
      messages = pagedController.threadById('paged')!.messages;
      expect(messages.length, 120);
      expect(messages.first.id, 'm0');
      expect(pagedController.hasMoreOlderMessages('paged'), isFalse);

      // Nothing left to load -- further requests are no-ops.
      await pagedController.loadOlderMessages('paged');
      expect(pagedController.threadById('paged')!.messages.length, 120);
    });

    test(
        'starredMessages includes a starred message from a thread whose '
        'loaded window does not carry it -- regression: it used to be '
        'derived from thread.messages, so a starred message outside the '
        'currently-loaded window (e.g. any thread the caller has not '
        'opened this session, as fetchThreads only returns a summary '
        'preview) silently never appeared', () async {
      final base = DateTime(2026, 1, 1, 8);
      final threadA = ChatThread(
        id: 'thread-a',
        name: 'Alice',
        avatarLabel: 'AL',
        accentColor: const Color(0xFF00A884),
        messages: [
          ChatMessage(
            id: 'a-old',
            senderName: 'Alice',
            sentAt: base,
            isFromCurrentUser: false,
            text: 'Older starred message',
            isStarred: true,
          ),
          ChatMessage(
            id: 'a-new',
            senderName: 'You',
            sentAt: base.add(const Duration(minutes: 5)),
            isFromCurrentUser: true,
            text: 'Latest message',
          ),
        ],
      );
      final threadB = ChatThread(
        id: 'thread-b',
        name: 'Bob',
        avatarLabel: 'BO',
        accentColor: const Color(0xFF00A884),
        messages: [
          ChatMessage(
            id: 'b-latest',
            senderName: 'Bob',
            sentAt: base.add(const Duration(minutes: 10)),
            isFromCurrentUser: false,
            text: 'Latest message, also starred',
            isStarred: true,
          ),
        ],
      );

      final summaryController = ChatsController(
        repository: _SummaryInboxRepository([threadA, threadB]),
      );
      addTearDown(summaryController.dispose);

      await summaryController.loadThreads();
      // refreshStarredMessages runs fire-and-forget right after the thread
      // list loads -- flush pending microtasks so it lands before asserting.
      await Future<void>.delayed(Duration.zero);

      // Confirms this test actually exercises the summary-window scenario:
      // thread-a's loaded window holds only its latest message, not the
      // starred one.
      final loadedThreadA = summaryController.threadById('thread-a')!;
      expect(loadedThreadA.messages, hasLength(1));
      expect(loadedThreadA.messages.single.id, 'a-new');

      final starredIds = summaryController.starredMessages
          .map((entry) => entry.message.id)
          .toSet();
      expect(starredIds, {'a-old', 'b-latest'});
    });

    test(
        'starring a message that is not the thread\'s latest still shows up '
        'on the message itself once the background sync lands -- '
        'regression: the sync\'s "did anything change" check compared only '
        'message ids/order, so it wrongly concluded nothing changed and '
        'skipped applying the freshly-fetched isStarred flag', () async {
      final openThread = _threadWithMessages('open-thread', 3);
      final starController = ChatsController(
        repository: _SummaryStarRepository([openThread]),
      );
      addTearDown(starController.dispose);

      await starController.loadThreads();
      await starController.ensureThreadMessagesLoaded('open-thread');

      // m1 is the middle message -- not the thread's latest (m2), so
      // toggleMessageStar's summary-only response never carries it.
      final didStar = await starController.toggleMessageStar(
        threadId: 'open-thread',
        messageId: 'm1',
      );
      expect(didStar, isTrue);

      // The authoritative background resync that reconciles the real
      // isStarred state is fire-and-forget -- flush pending microtasks so
      // it lands before asserting.
      await Future<void>.delayed(Duration.zero);

      final message = starController
          .threadById('open-thread')!
          .messages
          .firstWhere((candidate) => candidate.id == 'm1');
      expect(message.isStarred, isTrue);
    });
  });
}

/// A thread with chronological messages `m0`..`m{count-1}`, for exercising
/// pagination boundaries.
ChatThread _threadWithMessages(String id, int count) {
  final base = DateTime(2026, 1, 1, 8);
  return ChatThread(
    id: id,
    name: 'Paged Thread',
    avatarLabel: 'PT',
    accentColor: const Color(0xFF00A884),
    messages: List<ChatMessage>.generate(
      count,
      (i) => ChatMessage(
        id: 'm$i',
        senderName: 'Someone',
        sentAt: base.add(Duration(minutes: i)),
        isFromCurrentUser: false,
        text: 'message $i',
      ),
    ),
  );
}

/// Mimics a real backend where the inbox query (`fetchThreads`) carries only a
/// last-message preview -- full history is fetched per-thread and paged. The
/// stock [FakeChatRepository] returns full histories from `fetchThreads`, which
/// would mask the window growth this test checks.
class _SummaryInboxRepository extends FakeChatRepository {
  _SummaryInboxRepository(List<ChatThread> threads)
      : super(initialThreads: threads, latency: Duration.zero);

  @override
  Future<List<ChatThread>> fetchThreads() async {
    final full = await super.fetchThreads();
    return full
        .map(
          (thread) => thread.messages.isEmpty
              ? thread
              : thread.copyWith(messages: [thread.messages.last]),
        )
        .toList(growable: false);
  }
}

/// Mimics FirestoreChatRepository.toggleMessageStar, which (like every other
/// mutation there) returns `fetchThreads()` -- a summary-only snapshot
/// carrying just each thread's latest message, not the message that was
/// actually toggled unless it happens to be the latest one.
class _SummaryStarRepository extends FakeChatRepository {
  _SummaryStarRepository(List<ChatThread> threads)
      : super(initialThreads: threads, latency: Duration.zero);

  List<ChatThread> _summaryOnly(List<ChatThread> threads) {
    return threads
        .map(
          (thread) => thread.messages.isEmpty
              ? thread
              : thread.copyWith(messages: [thread.messages.last]),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ChatThread>> toggleMessageStar({
    required String threadId,
    required String messageId,
  }) async {
    await super.toggleMessageStar(threadId: threadId, messageId: messageId);
    return _summaryOnly(await super.fetchThreads());
  }
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
  Future<ChatMessagePage> fetchThreadMessagesPage({
    required String threadId,
    int limit = 50,
    ChatMessage? before,
  }) =>
      _delegate.fetchThreadMessagesPage(
        threadId: threadId,
        limit: limit,
        before: before,
      );

  @override
  Future<void> markThreadRead(String threadId) =>
      _delegate.markThreadRead(threadId);

  @override
  Future<void> setTypingState({
    required String threadId,
    required bool isTyping,
  }) =>
      _delegate.setTypingState(threadId: threadId, isTyping: isTyping);

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
    MessageReplyPreview? replyPreview,
    MediaTransfer? transfer,
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
  Future<ChatMessagePage> fetchThreadMessagesPage({
    required String threadId,
    int limit = 50,
    ChatMessage? before,
  }) =>
      _delegate.fetchThreadMessagesPage(
        threadId: threadId,
        limit: limit,
        before: before,
      );

  @override
  Future<void> setTypingState({
    required String threadId,
    required bool isTyping,
  }) =>
      _delegate.setTypingState(threadId: threadId, isTyping: isTyping);

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
  Future<ChatMessagePage> fetchThreadMessagesPage({
    required String threadId,
    int limit = 50,
    ChatMessage? before,
  }) =>
      _delegate.fetchThreadMessagesPage(
        threadId: threadId,
        limit: limit,
        before: before,
      );

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
  Future<void> setTypingState({
    required String threadId,
    required bool isTyping,
  }) =>
      _delegate.setTypingState(threadId: threadId, isTyping: isTyping);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingChatRepository implements ChatRepository {
  @override
  String get currentUserReactionKey => 'me';

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
  Future<UserProfileSnapshot?> fetchContactProfile(String uid) async => null;

  @override
  Future<ChatThread> fetchThreadWithMessages(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<ChatMessagePage> fetchThreadMessagesPage({
    required String threadId,
    int limit = 50,
    ChatMessage? before,
  }) {
    throw const ChatRepositoryException('Network went away');
  }

  @override
  Future<void> markThreadRead(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<void> setTypingState({
    required String threadId,
    required bool isTyping,
  }) async {}

  @override
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
    bool isCommunityGroup = false,
    bool isAnnouncementOnly = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
    MessageReplyPreview? replyPreview,
    MediaTransfer? transfer,
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

  @override
  Future<List<StarredMessageEntry>> fetchStarredMessages() {
    throw const ChatRepositoryException('Network went away');
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
  String get currentUserReactionKey => 'me';

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
  Future<ChatMessagePage> fetchThreadMessagesPage({
    required String threadId,
    int limit = 50,
    ChatMessage? before,
  }) =>
      _delegate.fetchThreadMessagesPage(
        threadId: threadId,
        limit: limit,
        before: before,
      );

  @override
  Future<void> markThreadRead(String threadId) =>
      _delegate.markThreadRead(threadId);

  @override
  Future<void> setTypingState({
    required String threadId,
    required bool isTyping,
  }) =>
      _delegate.setTypingState(threadId: threadId, isTyping: isTyping);

  @override
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
    bool isCommunityGroup = false,
    bool isAnnouncementOnly = false,
  }) =>
      _delegate.createGroup(
        name: name,
        memberUids: memberUids,
        isCommunityGroup: isCommunityGroup,
        isAnnouncementOnly: isAnnouncementOnly,
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
  Future<UserProfileSnapshot?> fetchContactProfile(String uid) =>
      _delegate.fetchContactProfile(uid);

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
    MessageReplyPreview? replyPreview,
    MediaTransfer? transfer,
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
  Future<List<StarredMessageEntry>> fetchStarredMessages() =>
      _delegate.fetchStarredMessages();

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
