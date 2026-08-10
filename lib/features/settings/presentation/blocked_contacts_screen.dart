import 'package:flutter/material.dart';

import '../../chats/application/chats_controller.dart';
import '../../chats/domain/chat_thread.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/empty_state_card.dart';

const double _kBlockedContactsHorizontalPadding = 16;

/// Every chat currently blocked, in one place -- blocking itself already
/// exists per-contact (see ContactInfoScreen's Block action), but there
/// was previously no central list of who's blocked, matching WhatsApp's
/// own "Blocked contacts" settings screen.
class BlockedContactsScreen extends StatelessWidget {
  const BlockedContactsScreen({required this.chatsController, super.key});

  final ChatsController chatsController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: chatsController,
      builder: (context, _) {
        final blocked = chatsController.threads
            .where((thread) => thread.isBlocked)
            .toList(growable: false)
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        return Scaffold(
          key: const Key('blocked_contacts_screen'),
          appBar: AppBar(
            title: const Text(
              'Blocked contacts',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: blocked.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: EmptyStateCard(
                      icon: Icons.block_outlined,
                      title: 'No blocked contacts',
                      message:
                          'Contacts you block from a chat\'s info screen show '
                          'up here.',
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      _kBlockedContactsHorizontalPadding,
                      8,
                      _kBlockedContactsHorizontalPadding,
                      24 + MediaQuery.paddingOf(context).bottom,
                    ),
                    itemCount: blocked.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final thread = blocked[index];
                      return _BlockedContactRow(
                        thread: thread,
                        onUnblock: () => chatsController.setThreadBlocked(
                          threadId: thread.id,
                          isBlocked: false,
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

class _BlockedContactRow extends StatelessWidget {
  const _BlockedContactRow({required this.thread, required this.onUnblock});

  final ChatThread thread;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AvatarBadge(
            label: thread.avatarLabel,
            color: thread.accentColor,
            avatarUrl: thread.avatarUrl,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              thread.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            key: Key('unblock_${thread.id}'),
            onPressed: onUnblock,
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
  }
}
