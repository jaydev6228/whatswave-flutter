import 'package:flutter/material.dart';

import '../../calls/application/calls_controller.dart';
import '../../communities/application/communities_controller.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../../updates/application/updates_controller.dart';
import '../application/chats_controller.dart';
import '../domain/chat_message.dart';
import '../domain/chat_thread.dart';
import 'conversation_screen.dart';

/// Every message the user has starred, across all chats -- WhatsApp's
/// "Starred messages" screen, reached from Settings > Chats.
class StarredMessagesScreen extends StatelessWidget {
  const StarredMessagesScreen({
    required this.chatsController,
    required this.callsController,
    required this.updatesController,
    required this.communitiesController,
    super.key,
  });

  final ChatsController chatsController;
  final CallsController callsController;
  final UpdatesController updatesController;
  final CommunitiesController communitiesController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: chatsController,
      builder: (context, _) {
        final entries = chatsController.starredMessages;
        return Scaffold(
          key: const Key('starred_messages_screen'),
          appBar: AppBar(
            title: const Text(
              'Starred messages',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: entries.isEmpty
                ? Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: EmptyStateCard(
                        dense: true,
                        margin: EdgeInsets.zero,
                        icon: Icons.star_border_rounded,
                        title: 'No starred messages',
                        message:
                            'Tap and hold any message, then choose Star to '
                            'find it here later.',
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.only(
                      bottom: 24 + MediaQuery.paddingOf(context).bottom,
                    ),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 16 + 44 + 12,
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.22),
                    ),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _StarredMessageRow(
                        thread: entry.thread,
                        message: entry.message,
                        onTap: () => _openThread(context, entry.thread.id),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  Future<void> _openThread(BuildContext context, String threadId) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          callsController: callsController,
          controller: chatsController,
          updatesController: updatesController,
          communitiesController: communitiesController,
          threadId: threadId,
        ),
      ),
    );
  }
}

class _StarredMessageRow extends StatelessWidget {
  const _StarredMessageRow({
    required this.thread,
    required this.message,
    required this.onTap,
  });

  final ChatThread thread;
  final ChatMessage message;
  final VoidCallback onTap;

  String get _preview {
    if (message.hasText) {
      return message.text;
    }
    if (message.hasAttachments) {
      return message.attachments.first.compactLabel;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('starred_message_${message.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AvatarBadge(
                label: thread.avatarLabel,
                color: thread.accentColor,
                avatarUrl: thread.avatarUrl,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            thread.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      thread.isGroup
                          ? '${message.senderName}: $_preview'
                          : _preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
