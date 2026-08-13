import '../../chats/application/chats_controller.dart';
import '../domain/community_group_preview.dart';
import '../domain/community_hub.dart';

/// Resolves community unread badges from live chat threads when available.
abstract final class CommunityUnread {
  static int forThread(ChatsController chats, String? threadId) {
    if (threadId == null) {
      return 0;
    }
    return chats.threadById(threadId)?.unreadCount ?? 0;
  }

  static int forGroup(
    ChatsController chats,
    CommunityGroupPreview group,
  ) {
    if (group.threadId != null) {
      return forThread(chats, group.threadId);
    }
    return group.unreadCount;
  }

  static int forAnnouncements(
    ChatsController chats,
    CommunityHub community,
  ) {
    if (community.announcementThreadId != null) {
      return forThread(chats, community.announcementThreadId);
    }
    return 0;
  }

  static int totalForCommunity(
    ChatsController chats,
    CommunityHub community,
  ) {
    var total = forAnnouncements(chats, community);
    for (final group in community.groups) {
      total += forGroup(chats, group);
    }
    if (total > 0) {
      return total;
    }

    final hasWiredThreads = community.announcementThreadId != null ||
        community.groups.any((group) => group.threadId != null);
    if (hasWiredThreads) {
      return 0;
    }

    // Communities without chat threads yet fall back to stored preview counts.
    return community.unreadCount;
  }
}
