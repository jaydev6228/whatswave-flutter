import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/domain/chat_message.dart';
import 'package:whatswave/features/chats/domain/chat_thread.dart';

/// Every Chats surface reads its rows through ChatsController.inboxThreads /
/// archivedThreads / visibleThreads (chats_screen.dart, its archived screen,
/// and new_chat_screen.dart), so a community-backed thread that leaks past
/// any one of those argument combinations lands back in the user's chat list.
/// The seeded threads below are deliberately built to pass every *other*
/// filter -- they have messages, they're groups, they're unread, and their
/// names match the search query -- so each expectation can only be satisfied
/// by the community-group exclusion itself.
void main() {
  ChatMessage message(String id, String text) => ChatMessage(
        id: id,
        senderName: 'Priya',
        sentAt: DateTime(2026, 8, 9, 10),
        isFromCurrentUser: false,
        text: text,
      );

  ChatThread communityThread({
    required String id,
    required String name,
    bool isArchived = false,
  }) =>
      ChatThread(
        id: id,
        name: name,
        avatarLabel: name.substring(0, 1),
        accentColor: AppPalette.emerald,
        messages: [message('$id-m1', 'Match day is on')],
        unreadCount: 3,
        isGroup: true,
        isCommunityGroup: true,
        isArchived: isArchived,
      );

  ChatThread plainGroupThread({required String id, required String name}) =>
      ChatThread(
        id: id,
        name: name,
        avatarLabel: name.substring(0, 1),
        accentColor: AppPalette.sky,
        messages: [message('$id-m1', 'Match day is on')],
        unreadCount: 2,
        isGroup: true,
      );

  late ChatsController controller;

  setUp(() async {
    controller = ChatsController(
      repository: FakeChatRepository(
        latency: Duration.zero,
        initialThreads: [
          communityThread(id: 'community-general', name: 'General'),
          communityThread(
            id: 'community-archived',
            name: 'General Archive',
            isArchived: true,
          ),
          plainGroupThread(id: 'plain-group', name: 'Generally Weekend Plans'),
        ],
      ),
    );
    await controller.loadThreads();
  });

  group('community group threads stay out of every Chats surface', () {
    test('the main list and its counts', () {
      expect(
        controller.inboxThreads().map((thread) => thread.id),
        const ['plain-group'],
      );
      expect(
        controller.visibleThreads.map((thread) => thread.id),
        const ['plain-group'],
      );
      expect(controller.activeCount, 1);
      expect(controller.archivedCount, 0);
      expect(controller.unreadThreadCount, 1);
    });

    test('the Unread filter chip', () {
      expect(
        controller
            .inboxThreads(filter: ChatListFilter.unread)
            .map((thread) => thread.id),
        const ['plain-group'],
      );
    });

    test('the Groups filter chip', () {
      expect(
        controller
            .inboxThreads(filter: ChatListFilter.groups)
            .map((thread) => thread.id),
        const ['plain-group'],
      );
    });

    test('search results', () {
      expect(
        controller.inboxThreads(query: 'general').map((thread) => thread.id),
        const ['plain-group'],
      );
      // Matching on the preview text rather than the name is a second way
      // into the same list.
      expect(
        controller.inboxThreads(query: 'match day').map((thread) => thread.id),
        const ['plain-group'],
      );
    });

    test('the archived list, including its own search and filters', () {
      expect(controller.archivedThreads(), isEmpty);
      expect(controller.archivedThreads(query: 'general'), isEmpty);
      expect(
        controller.archivedThreads(filter: ChatListFilter.groups),
        isEmpty,
      );
      expect(
        controller.archivedThreads(filter: ChatListFilter.unread),
        isEmpty,
      );
    });

    test('but the conversation screen can still resolve one by id', () {
      expect(controller.threadById('community-general')?.name, 'General');
    });
  });
}
