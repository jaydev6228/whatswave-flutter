import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../communities/application/communities_controller.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../application/chats_controller.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_thread.dart';
import '../domain/group_participant.dart';
import 'add_group_members_screen.dart';
import 'shared_media_screen.dart';

/// WhatsApp-style contact info: shared media, common groups, and
/// destructive actions (clear chat, block), reached by tapping the
/// contact/group name in the conversation app bar. For a group thread,
/// doubles as "Group info": participant list with admin roles, add/remove
/// members, rename, description, and leaving the group.
class ContactInfoScreen extends StatefulWidget {
  const ContactInfoScreen({
    required this.controller,
    required this.communitiesController,
    required this.threadId,
    super.key,
  });

  final ChatsController controller;
  final CommunitiesController communitiesController;
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
                              if (thread.isGroup &&
                                  thread.currentUserIsGroupAdmin)
                                GestureDetector(
                                  key: const Key(
                                    'contact_info_change_group_icon_button',
                                  ),
                                  onTap: () => _pickAndUpdateGroupAvatar(
                                    thread,
                                  ),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      AvatarBadge(
                                        label: thread.avatarLabel,
                                        color: thread.accentColor,
                                        avatarUrl: thread.avatarUrl,
                                        size: 84,
                                      ),
                                      Positioned(
                                        right: -2,
                                        bottom: -2,
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: theme.colorScheme.surface,
                                              width: 2,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.camera_alt_rounded,
                                            size: 16,
                                            color: theme.colorScheme.onPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                AvatarBadge(
                                  label: thread.avatarLabel,
                                  color: thread.accentColor,
                                  avatarUrl: thread.avatarUrl,
                                  size: 84,
                                ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      thread.name,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  if (thread.isGroup &&
                                      thread.currentUserIsGroupAdmin) ...[
                                    const SizedBox(width: 6),
                                    IconButton(
                                      key: const Key(
                                        'contact_info_rename_group_button',
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _confirmRenameGroup(thread),
                                    ),
                                  ],
                                ],
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
                        if (thread.isGroup) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  (thread.groupDescription?.isNotEmpty ?? false)
                                      ? thread.groupDescription!
                                      : 'Add a group description',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color:
                                        theme.colorScheme.onSurface.withValues(
                                      alpha: (thread.groupDescription
                                                  ?.isNotEmpty ??
                                              false)
                                          ? 0.8
                                          : 0.5,
                                    ),
                                  ),
                                ),
                              ),
                              if (thread.currentUserIsGroupAdmin) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  key: const Key(
                                    'contact_info_edit_description_button',
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () =>
                                      _confirmEditDescription(thread),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 28),
                        ],
                        if (mediaAttachments.isNotEmpty) ...[
                          Text(
                            'Shared media',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _FlatInfoPanel(
                            padding: EdgeInsets.zero,
                            child: _SharedMediaDisclosureRow(
                              attachments: mediaAttachments,
                              threadName: thread.name,
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],
                        if (thread.isGroup &&
                            (thread.participants?.isNotEmpty ?? false)) ...[
                          Text(
                            '${thread.participants!.length} participants',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _FlatInfoPanel(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                if (thread.currentUserIsGroupAdmin) ...[
                                  _ActionRow(
                                    actionKey: const Key(
                                      'contact_info_add_participants_button',
                                    ),
                                    icon: Icons.person_add_alt_outlined,
                                    label: 'Add participants',
                                    onTap: () => _addParticipants(thread),
                                  ),
                                  Divider(
                                    height: 1,
                                    color: theme.colorScheme.outlineVariant
                                        .withValues(alpha: 0.24),
                                  ),
                                ],
                                for (var index = 0;
                                    index < thread.participants!.length;
                                    index++) ...[
                                  if (index > 0)
                                    Divider(
                                      height: 1,
                                      color: theme.colorScheme.outlineVariant
                                          .withValues(alpha: 0.24),
                                    ),
                                  _ParticipantRow(
                                    participant: thread.participants![index],
                                    canManage: thread.currentUserIsGroupAdmin &&
                                        !thread.participants![index].isSelf,
                                    onTap: () => _showParticipantOptions(
                                      thread,
                                      thread.participants![index],
                                    ),
                                  ),
                                ],
                              ],
                            ),
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
                              if (thread.isGroup)
                                _ActionRow(
                                  actionKey: const Key(
                                    'contact_info_exit_group_button',
                                  ),
                                  icon: Icons.logout_rounded,
                                  label: 'Exit group',
                                  onTap: () => _confirmLeaveGroup(thread),
                                )
                              else
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

  Future<void> _confirmRenameGroup(ChatThread thread) async {
    // Uncontrolled TextFormField, not a caller-owned TextEditingController
    // -- see _editMessage's doc comment in conversation_screen.dart for why
    // disposing a controller right after showDialog resolves is unsafe.
    var currentName = thread.name;
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Group name'),
          content: TextFormField(
            key: const Key('rename_group_field'),
            initialValue: thread.name,
            autofocus: true,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            onChanged: (value) => currentName = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm_rename_group_button'),
              onPressed: () => Navigator.of(dialogContext).pop(currentName),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    final trimmed = newName?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == thread.name) {
      return;
    }
    if (!mounted) {
      return;
    }
    await widget.controller.renameGroup(threadId: thread.id, name: trimmed);
  }

  Future<void> _confirmEditDescription(ChatThread thread) async {
    var currentDescription = thread.groupDescription ?? '';
    final newDescription = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Group description'),
          content: TextFormField(
            key: const Key('edit_group_description_field'),
            initialValue: thread.groupDescription ?? '',
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (value) => currentDescription = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm_edit_group_description_button'),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(currentDescription),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    final trimmed = newDescription?.trim();
    if (trimmed == null || trimmed == (thread.groupDescription ?? '')) {
      return;
    }
    if (!mounted) {
      return;
    }
    await widget.controller.updateGroupDescription(
      threadId: thread.id,
      description: trimmed,
    );
  }

  Future<void> _pickAndUpdateGroupAvatar(ChatThread thread) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) {
      return;
    }
    await widget.controller.updateGroupAvatar(
      threadId: thread.id,
      photo: File(picked.path),
    );
  }

  Future<void> _addParticipants(ChatThread thread) async {
    final memberUids = await pickGroupMembersToAdd(
      context,
      communitiesController: widget.communitiesController,
      thread: thread,
    );
    if (memberUids == null || memberUids.isEmpty || !mounted) {
      return;
    }
    await widget.controller.addGroupMembers(
      threadId: thread.id,
      memberUids: memberUids,
    );
  }

  Future<void> _showParticipantOptions(
    ChatThread thread,
    GroupParticipant participant,
  ) async {
    final action = await showModalBottomSheet<_ParticipantAction>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('participant_option_toggle_admin'),
                leading: Icon(
                  participant.isAdmin
                      ? Icons.remove_moderator_outlined
                      : Icons.admin_panel_settings_outlined,
                ),
                title: Text(
                  participant.isAdmin ? 'Dismiss as admin' : 'Make group admin',
                ),
                onTap: () => Navigator.of(sheetContext)
                    .pop(_ParticipantAction.toggleAdmin),
              ),
              ListTile(
                key: const Key('participant_option_remove'),
                leading: Icon(
                  Icons.person_remove_outlined,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: Text(
                  'Remove ${participant.name}',
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ParticipantAction.remove),
              ),
            ],
          ),
        );
      },
    );

    if (action == null || !mounted) {
      return;
    }

    switch (action) {
      case _ParticipantAction.toggleAdmin:
        await widget.controller.setGroupAdmin(
          threadId: thread.id,
          memberUid: participant.uid,
          isAdmin: !participant.isAdmin,
        );
      case _ParticipantAction.remove:
        await _confirmRemoveParticipant(thread, participant);
    }
  }

  Future<void> _confirmRemoveParticipant(
    ChatThread thread,
    GroupParticipant participant,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Remove ${participant.name}?'),
          content: Text(
            '${participant.name} will be removed from ${thread.name}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm_remove_participant_button'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) {
      await widget.controller.removeGroupMember(
        threadId: thread.id,
        memberUid: participant.uid,
      );
    }
  }

  Future<void> _confirmLeaveGroup(ChatThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Exit group?'),
          content: Text(
            "You'll no longer receive messages from ${thread.name}.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm_exit_group_button'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Exit group'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await widget.controller.leaveGroup(thread.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

enum _ParticipantAction { toggleAdmin, remove }

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

/// A single-row summary of a thread's shared media -- a preview thumbnail
/// of the most recent item plus an item count, tapping through to
/// [SharedMediaScreen]'s full grid. Replaces showing the grid inline,
/// which pushed common groups/destructive actions much further down the
/// scroll for any thread with more than a few shared items.
class _SharedMediaDisclosureRow extends StatelessWidget {
  const _SharedMediaDisclosureRow({
    required this.attachments,
    required this.threadName,
  });

  final List<ChatAttachment> attachments;
  final String threadName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // .last, not .first -- attachments is built from thread.messages in
    // chronological (oldest-first) order, so the most recently shared item
    // is the last one.
    final previewAttachment = attachments.last;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('contact_info_shared_media_row'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SharedMediaScreen(
              attachments: attachments,
              threadName: threadName,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: SharedMediaThumbnail(attachment: previewAttachment),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  attachments.length == 1
                      ? '1 item'
                      : '${attachments.length} items',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
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

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.canManage,
    required this.onTap,
  });

  final GroupParticipant participant;

  /// Whether the viewer is an admin who may act on this row (promote/
  /// demote/remove) -- false for their own row or when they're not an
  /// admin, in which case the row is informational only.
  final bool canManage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('participant_row_${participant.uid}'),
        onTap: canManage ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              AvatarBadge(
                label: participant.avatarLabel,
                color: participant.accentColor,
                avatarUrl: participant.avatarUrl,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  participant.isSelf ? 'You' : participant.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (participant.isAdmin) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Admin',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
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
