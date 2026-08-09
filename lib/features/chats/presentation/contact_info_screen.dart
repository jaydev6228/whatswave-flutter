import 'package:flutter/material.dart';

import '../../shared/widgets/avatar_badge.dart';
import '../../updates/presentation/widgets/status_media_source.dart';
import '../application/chats_controller.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_thread.dart';
import 'attachment_viewer_screen.dart';

/// WhatsApp-style contact info: shared media, common groups, and
/// destructive actions (clear chat, block), reached by tapping the
/// contact/group name in the conversation app bar.
class ContactInfoScreen extends StatefulWidget {
  const ContactInfoScreen({
    required this.controller,
    required this.threadId,
    super.key,
  });

  final ChatsController controller;
  final String threadId;

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  List<ChatThread> _commonGroups = const <ChatThread>[];
  bool _hasLoadedCommonGroups = false;

  @override
  void initState() {
    super.initState();
    _loadCommonGroups();
  }

  Future<void> _loadCommonGroups() async {
    final thread = widget.controller.threadById(widget.threadId);
    if (thread == null || thread.isGroup) {
      return;
    }
    final groups = await widget.controller.groupThreadsSharedWith(
      thread.participantUid ?? thread.id,
    );
    if (!mounted) return;
    setState(() {
      _commonGroups = groups;
      _hasLoadedCommonGroups = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final thread = widget.controller.threadById(widget.threadId);

        if (thread == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Contact info')),
            body: Center(
              child: Text(
                'This contact is no longer available.',
                style: theme.textTheme.titleMedium,
              ),
            ),
          );
        }

        final mediaAttachments = thread.messages
            .expand((message) => message.attachments)
            .where(
              (attachment) =>
                  attachment.type == ChatAttachmentType.photo ||
                  attachment.type == ChatAttachmentType.video,
            )
            .toList(growable: false);

        return Scaffold(
          appBar: AppBar(
            title: Text(thread.isGroup ? 'Group info' : 'Contact info'),
          ),
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Column(
                            children: [
                              AvatarBadge(
                                label: thread.avatarLabel,
                                color: thread.accentColor,
                                avatarUrl: thread.avatarUrl,
                                size: 84,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                thread.name,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                thread.isGroup
                                    ? 'Group · ${thread.messages.length} messages'
                                    : 'Contact',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.64),
                                ),
                              ),
                              if (thread.isBlocked) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.error
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Blocked',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: theme.colorScheme.error,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (mediaAttachments.isNotEmpty) ...[
                          Text(
                            'Shared media',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SharedMediaGrid(
                            attachments: mediaAttachments,
                            threadName: thread.name,
                          ),
                          const SizedBox(height: 28),
                        ],
                        if (!thread.isGroup &&
                            _hasLoadedCommonGroups &&
                            _commonGroups.isNotEmpty) ...[
                          Text(
                            'Common groups',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _FlatInfoPanel(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (var index = 0;
                                    index < _commonGroups.length;
                                    index++) ...[
                                  if (index > 0)
                                    Divider(
                                      height: 1,
                                      color: theme.colorScheme.outlineVariant
                                          .withValues(alpha: 0.24),
                                    ),
                                  _CommonGroupRow(group: _commonGroups[index]),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],
                        Text(
                          'Actions',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _FlatInfoPanel(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              _ActionRow(
                                actionKey:
                                    const Key('contact_info_clear_chat_button'),
                                icon: Icons.delete_sweep_outlined,
                                label: 'Clear chat',
                                onTap: thread.messages.isEmpty
                                    ? null
                                    : () => _confirmClearChat(thread),
                              ),
                              Divider(
                                height: 1,
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.24),
                              ),
                              _ActionRow(
                                actionKey:
                                    const Key('contact_info_block_button'),
                                icon: thread.isBlocked
                                    ? Icons.block_flipped
                                    : Icons.block_outlined,
                                label: thread.isBlocked
                                    ? 'Unblock ${thread.name}'
                                    : 'Block ${thread.name}',
                                onTap: () => _confirmToggleBlock(thread),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmClearChat(ChatThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clear this chat?'),
          content: Text(
            'Messages with ${thread.name} will be removed from this device. '
            "This can't be undone.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('contact_info_confirm_clear_chat_button'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Clear chat'),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) {
      await widget.controller.clearThreadMessages(thread.id);
    }
  }

  Future<void> _confirmToggleBlock(ChatThread thread) async {
    final willBlock = !thread.isBlocked;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            willBlock ? 'Block ${thread.name}?' : 'Unblock ${thread.name}?',
          ),
          content: Text(
            willBlock
                ? '${thread.name} will no longer be able to call or message you.'
                : '${thread.name} will be able to call and message you again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('contact_info_confirm_block_button'),
              style: willBlock
                  ? FilledButton.styleFrom(
                      backgroundColor:
                          Theme.of(dialogContext).colorScheme.error,
                    )
                  : null,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(willBlock ? 'Block' : 'Unblock'),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) {
      await widget.controller.setThreadBlocked(
        threadId: thread.id,
        isBlocked: willBlock,
      );
    }
  }
}

class _FlatInfoPanel extends StatelessWidget {
  const _FlatInfoPanel({
    required this.child,
    this.padding = const EdgeInsets.all(4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
        ),
      ),
      child: child,
    );
  }
}

class _SharedMediaGrid extends StatelessWidget {
  const _SharedMediaGrid({
    required this.attachments,
    required this.threadName,
  });

  final List<ChatAttachment> attachments;
  final String threadName;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: attachments.length,
      itemBuilder: (context, index) {
        final attachment = attachments[index];
        final localPath = attachment.localMediaPath;
        final hasRealPhoto = attachment.type == ChatAttachmentType.photo &&
            localPath != null &&
            statusMediaSourceExists(localPath);

        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('contact_info_media_${attachment.id}'),
              onTap: () => showAttachmentPreview(
                context,
                attachment: attachment,
                threadName: threadName,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasRealPhoto)
                    Image(
                      image: imageProviderForStatusMediaPath(localPath)!,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) {
                          return child;
                        }
                        return ColoredBox(
                          color: attachment.tintColor.withValues(alpha: 0.18),
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: attachment.tintColor,
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  else
                    ColoredBox(
                      color: attachment.tintColor.withValues(alpha: 0.18),
                      child: Icon(
                        attachment.type == ChatAttachmentType.video
                            ? Icons.videocam_outlined
                            : Icons.photo_outlined,
                        color: attachment.tintColor,
                      ),
                    ),
                  if (attachment.type == ChatAttachmentType.video)
                    const Center(
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CommonGroupRow extends StatelessWidget {
  const _CommonGroupRow({required this.group});

  final ChatThread group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          AvatarBadge(
              label: group.avatarLabel, color: group.accentColor, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.actionKey,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Key actionKey;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final color = enabled
        ? theme.colorScheme.error
        : theme.colorScheme.error.withValues(alpha: 0.38);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: actionKey,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
