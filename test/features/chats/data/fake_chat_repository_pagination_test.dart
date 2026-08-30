import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/domain/chat_message.dart';
import 'package:whatswave/features/chats/domain/chat_thread.dart';

/// Builds a thread whose messages are chronological (oldest first) with ids
/// `m0`..`m{count-1}` and strictly increasing timestamps, so paging boundaries
/// are easy to assert.
ChatThread _threadWith(String id, int count) {
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

void main() {
  group('fetchThreadMessagesPage', () {
    test('returns the newest window first, then pages strictly older',
        () async {
      final repo = FakeChatRepository(
        initialThreads: [_threadWith('t', 120)],
        latency: Duration.zero,
      );

      // Newest 50 (m70..m119), chronological, more history behind them.
      final page1 =
          await repo.fetchThreadMessagesPage(threadId: 't', limit: 50);
      expect(page1.messages.length, 50);
      expect(page1.messages.first.id, 'm70');
      expect(page1.messages.last.id, 'm119');
      expect(page1.hasMoreOlder, isTrue);

      // Next-older 50 (m20..m69), continuing from the previous window's oldest.
      final page2 = await repo.fetchThreadMessagesPage(
        threadId: 't',
        limit: 50,
        before: page1.messages.first,
      );
      expect(page2.messages.length, 50);
      expect(page2.messages.first.id, 'm20');
      expect(page2.messages.last.id, 'm69');
      expect(page2.hasMoreOlder, isTrue);

      // Final partial window (m0..m19) exhausts the history.
      final page3 = await repo.fetchThreadMessagesPage(
        threadId: 't',
        limit: 50,
        before: page2.messages.first,
      );
      expect(page3.messages.length, 20);
      expect(page3.messages.first.id, 'm0');
      expect(page3.messages.last.id, 'm19');
      expect(page3.hasMoreOlder, isFalse);
    });

    test('a thread shorter than one page has no older history', () async {
      final repo = FakeChatRepository(
        initialThreads: [_threadWith('t', 10)],
        latency: Duration.zero,
      );

      final page = await repo.fetchThreadMessagesPage(threadId: 't', limit: 50);
      expect(page.messages.length, 10);
      expect(page.messages.first.id, 'm0');
      expect(page.messages.last.id, 'm9');
      expect(page.hasMoreOlder, isFalse);
    });

    test('paging past the oldest message yields an empty final window',
        () async {
      final repo = FakeChatRepository(
        initialThreads: [_threadWith('t', 30)],
        latency: Duration.zero,
      );

      final page = await repo.fetchThreadMessagesPage(threadId: 't', limit: 50);
      expect(page.messages.first.id, 'm0');
      expect(page.hasMoreOlder, isFalse);

      final beyond = await repo.fetchThreadMessagesPage(
        threadId: 't',
        limit: 50,
        before: page.messages.first,
      );
      expect(beyond.messages, isEmpty);
      expect(beyond.hasMoreOlder, isFalse);
    });
  });
}
