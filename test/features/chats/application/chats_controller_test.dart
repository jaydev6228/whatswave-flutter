import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/chat_repository.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';
import 'package:whatswave/features/chats/domain/chat_thread.dart';

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

    test('marks unread chats as read when opened', () async {
      await controller.loadThreads();

      expect(controller.threadById('family')?.unreadCount, 12);

      await controller.openThread('family');

      expect(controller.threadById('family')?.unreadCount, 0);
    });

    test('sends text and attachment messages into a thread', () async {
      await controller.loadThreads();

      await controller.sendTextMessage(
        threadId: 'ava-patel',
        text: 'I will send the polished handoff in five.',
      );
      await controller.sendAttachmentMessage(
        threadId: 'ava-patel',
        attachment: const ChatAttachment(
          id: 'test-photo',
          type: ChatAttachmentType.photo,
          title: 'Polished handoff',
          details: 'Ready for review',
          tintColor: Color(0xFF25D366),
          aspectRatio: 1.1,
        ),
      );

      final thread = controller.threadById('ava-patel');
      expect(thread, isNotNull);
      expect(
          thread!.messages.last.attachments.single.title, 'Polished handoff');
      expect(thread.messages[thread.messages.length - 2].text,
          'I will send the polished handoff in five.');
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
  });
}

class _FailingChatRepository implements ChatRepository {
  @override
  Future<List<ChatThread>> fetchThreads() {
    throw const ChatRepositoryException('Network went away');
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
  Future<List<ChatThread>> markThreadRead(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required ChatAttachment attachment,
    String? caption,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
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
  Future<List<ChatThread>> markThreadRead(String threadId) =>
      _delegate.markThreadRead(threadId);

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required ChatAttachment attachment,
    String? caption,
  }) {
    throw const ChatRepositoryException('Message service offline');
  }

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
  }) {
    throw const ChatRepositoryException('Message service offline');
  }

  @override
  Future<List<ChatThread>> setThreadArchived({
    required String threadId,
    required bool isArchived,
  }) =>
      _delegate.setThreadArchived(
        threadId: threadId,
        isArchived: isArchived,
      );
}
