import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/media/avatar_photo_picker.dart';
import '../../calls/application/calls_controller.dart';
import '../../communities/application/communities_controller.dart';
import '../../communities/domain/community_hub.dart';
import '../../communities/presentation/community_detail_screen.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/error_dialog.dart';
import '../../shared/widgets/thread_avatar.dart';
import '../../updates/application/updates_controller.dart';
import '../application/chats_controller.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_thread.dart';
import '../domain/group_participant.dart';
import 'add_group_members_screen.dart';
import 'shared_media_screen.dart';
import 'starred_messages_screen.dart';

/// WhatsApp-style contact info: shared media, common groups, and
/// destructive actions (clear chat, block), reached by tapping the
/// contact/group name in the conversation app bar. For a group thread,
/// doubles as "Group info": participant list with admin roles, add/remove
/// members, rename, description, and leaving the group.
class ContactInfoScreen extends StatefulWidget {
  const ContactInfoScreen({
    required this.controller,
    required this.communitiesController,
    required this.callsController,
    required this.updatesController,
    required this.threadId,
    super.key,
  });

  final ChatsController controller;
  final CommunitiesController communitiesController;
  final CallsController callsController;
  final UpdatesController updatesController;
  final String threadId;

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  List<ChatThread> _commonGroups = const <ChatThread>[];
  bool _hasLoadedCommonGroups = false;
  bool _isEditingGroup = false;
  TextEditingController? _groupNameController;
  TextEditingController? _groupDescriptionController;
  File? _pendingGroupIconPhoto;
  bool _pendingRemoveGroupIcon = false;

  @override
  void dispose() {
    _groupNameController?.dispose();
    _groupDescriptionController?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCommonGroups();
    // Refetches from the repository directly rather than relying on
    // whatever's already cached -- see ChatsController.refreshStarredMessages
    // doc comment. Without this, opening Contact/Group info before ever
    // opening Settings > Starred messages this session would show a stale
    // (possibly empty) starred count.
    unawaited(widget.controller.refreshStarredMessages());
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
      animation: Listenable.merge([
        widget.controller,
        widget.communitiesController,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final thread = widget.controller.threadById(widget.threadId);
        final communityContext =
            widget.communitiesController.communityContextForThread(
          widget.threadId,
        );
        final isCommunityAnnouncement =
            communityContext?.isAnnouncement ?? false;
        final isCommunityGroup =
            thread?.isCommunityGroup ?? communityContext != null;

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

        // Sourced from the controller's own starred cache, not
        // thread.messages -- that's only ever the currently-loaded window
        // (see ChatsController.starredMessages doc comment), so it would
        // undercount (or show zero for) a starred message this session
        // hasn't paged in yet.
        final threadStarredCount = widget.controller.starredMessages
            .where((entry) => entry.thread.id == thread.id)
            .length;

        final canEditGroup = thread.isGroup &&
            thread.currentUserIsGroupAdmin &&
            !isCommunityAnnouncement;
        final isGroupIconBusy =
            widget.controller.isThreadBusy(thread.id);

        return Scaffold(
          appBar: AppBar(
            title: Text(thread.isGroup ? 'Group info' : 'Contact info'),
            actions: [
              if (canEditGroup && !_isEditingGroup)
                TextButton(
                  key: const Key('contact_info_edit_button'),
                  onPressed: isGroupIconBusy
                      ? null
                      : () => _startGroupEdit(thread),
                  child: const Text('Edit'),
                ),
              if (_isEditingGroup) ...[
                TextButton(
                  key: const Key('contact_info_cancel_edit_button'),
                  onPressed: isGroupIconBusy ? null : _cancelGroupEdit,
                  child: const Text('Cancel'),
                ),
                TextButton(
                  key: const Key('contact_info_save_button'),
                  onPressed: isGroupIconBusy
                      ? null
                      : () => _saveGroupEdit(thread),
                  child: isGroupIconBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Done'),
                ),
              ],
            ],
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
                              _buildGroupAvatarHeader(
                                thread: thread,
                                theme: theme,
                                isBusy: isGroupIconBusy,
                              ),
                              const SizedBox(height: 14),
                              if (_isEditingGroup && canEditGroup)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: TextField(
                                    key: const Key('rename_group_field'),
                                    controller: _groupNameController,
                                    textAlign: TextAlign.center,
                                    maxLength: 60,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: const InputDecoration(
                                      hintText: 'Group name',
                                      counterText: '',
                                    ),
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                )
                              else
                                Text(
                                  thread.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                _groupSubtitle(
                                  thread: thread,
                                  isCommunityGroup: isCommunityGroup,
                                  isCommunityAnnouncement:
                                      isCommunityAnnouncement,
                                ),
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
                        if (communityContext != null) ...[
                          Text(
                            'Community',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _FlatInfoPanel(
                            padding: EdgeInsets.zero,
                            child: _CommunityLinkRow(
                              community: communityContext.community,
                              onTap: () => _openCommunity(
                                communityContext.community.id,
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],
                        if (isCommunityAnnouncement) ...[
                          _FlatInfoPanel(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Only community admins can send messages here. '
                                    'Members can read announcements but not reply.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.76),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],
                        if (thread.isGroup) ...[
                          if (_isEditingGroup && canEditGroup)
                            TextField(
                              key: const Key('edit_group_description_field'),
                              controller: _groupDescriptionController,
                              minLines: 2,
                              maxLines: 4,
                              maxLength: 200,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Group description',
                                hintText: 'What is this group about?',
                              ),
                            )
                          else
                            Text(
                              (thread.groupDescription?.isNotEmpty ?? false)
                                  ? thread.groupDescription!
                                  : 'Add a group description',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: (thread.groupDescription?.isNotEmpty ??
                                          false)
                                      ? 0.8
                                      : 0.5,
                                ),
                              ),
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
                        if (threadStarredCount > 0) ...[
                          Text(
                            'Starred messages',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _FlatInfoPanel(
                            padding: EdgeInsets.zero,
                            child: _StarredMessagesDisclosureRow(
                              count: threadStarredCount,
                              onTap: () => _openStarredMessages(
                                context,
                                thread.id,
                              ),
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
                                if (thread.currentUserIsGroupAdmin &&
                                    !isCommunityAnnouncement) ...[
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
                              if (thread.isGroup && !isCommunityAnnouncement)
                                _ActionRow(
                                  actionKey: const Key(
                                    'contact_info_exit_group_button',
                                  ),
                                  icon: Icons.logout_rounded,
                                  label: 'Exit group',
                                  onTap: () => _confirmLeaveGroup(thread),
                                )
                              else if (!thread.isGroup)
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

  Future<void> _openCommunity(String communityId) async {
    await widget.communitiesController.openCommunity(communityId);
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CommunityDetailScreen(
          controller: widget.communitiesController,
          chatsController: widget.controller,
          callsController: widget.callsController,
          updatesController: widget.updatesController,
          communityId: communityId,
        ),
      ),
    );
  }

  Future<void> _openStarredMessages(
    BuildContext context,
    String threadId,
  ) async {
    // Scoped to this thread, StarredMessagesScreen pops itself with the
    // tapped message's id instead of pushing its own ConversationScreen
    // (see its onTap) -- propagate that straight back through to whoever
    // opened this Contact info screen, so the whole chain unwinds to a
    // single jump on the original conversation rather than stacking a
    // fresh screen at every level.
    final jumpTargetMessageId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => StarredMessagesScreen(
          chatsController: widget.controller,
          callsController: widget.callsController,
          updatesController: widget.updatesController,
          communitiesController: widget.communitiesController,
          threadId: threadId,
        ),
      ),
    );
    if (jumpTargetMessageId != null && context.mounted) {
      Navigator.of(context).pop(jumpTargetMessageId);
    }
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

  Widget _buildGroupAvatarHeader({
    required ChatThread thread,
    required ThemeData theme,
    required bool isBusy,
  }) {
    final canEdit = thread.isGroup && thread.currentUserIsGroupAdmin;
    final avatar = _pendingGroupIconPhoto != null
        ? ClipOval(
            child: Image.file(
              _pendingGroupIconPhoto!,
              width: 84,
              height: 84,
              fit: BoxFit.cover,
            ),
          )
        : _pendingRemoveGroupIcon
            ? ThreadAvatar(
                thread: thread.copyWith(clearAvatarUrl: true),
                size: 84,
              )
            : ThreadAvatar(thread: thread, size: 84);

    if (!_isEditingGroup || !canEdit) {
      return avatar;
    }

    return GestureDetector(
      key: const Key('contact_info_change_group_icon_button'),
      onTap: isBusy ? null : () => _showGroupPhotoOptions(thread),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          AvatarCameraBadge(isBusy: isBusy),
        ],
      ),
    );
  }

  void _startGroupEdit(ChatThread thread) {
    _groupNameController?.dispose();
    _groupDescriptionController?.dispose();
    setState(() {
      _isEditingGroup = true;
      _pendingGroupIconPhoto = null;
      _pendingRemoveGroupIcon = false;
      _groupNameController = TextEditingController(text: thread.name);
      _groupDescriptionController = TextEditingController(
        text: thread.groupDescription ?? '',
      );
    });
  }

  void _cancelGroupEdit() {
    _groupNameController?.dispose();
    _groupDescriptionController?.dispose();
    setState(() {
      _isEditingGroup = false;
      _pendingGroupIconPhoto = null;
      _pendingRemoveGroupIcon = false;
      _groupNameController = null;
      _groupDescriptionController = null;
    });
  }

  Future<void> _saveGroupEdit(ChatThread thread) async {
    final name = _groupNameController?.text.trim() ?? thread.name;
    final description = _groupDescriptionController?.text.trim() ?? '';

    if (name.isEmpty) {
      await showErrorDialog(context, 'Give the group a name.');
      return;
    }

    if (name != thread.name) {
      final didRename = await widget.controller.renameGroup(
        threadId: thread.id,
        name: name,
      );
      if (!didRename && mounted) {
        final message = widget.controller.errorMessage ??
            'We could not rename that group right now.';
        widget.controller.clearError();
        await showErrorDialog(context, message);
        return;
      }
    }

    if (description != (thread.groupDescription ?? '')) {
      final didUpdateDescription =
          await widget.controller.updateGroupDescription(
        threadId: thread.id,
        description: description,
      );
      if (!didUpdateDescription && mounted) {
        final message = widget.controller.errorMessage ??
            'We could not update that group right now.';
        widget.controller.clearError();
        await showErrorDialog(context, message);
        return;
      }
    }

    if (_pendingRemoveGroupIcon) {
      final didDelete = await widget.controller.deleteGroupAvatar(thread.id);
      if (!didDelete && mounted) {
        final message = widget.controller.errorMessage ??
            'We could not remove that group photo right now.';
        widget.controller.clearError();
        await showErrorDialog(context, message);
        return;
      }
    } else if (_pendingGroupIconPhoto != null) {
      final didUpdate = await widget.controller.updateGroupAvatar(
        threadId: thread.id,
        photo: _pendingGroupIconPhoto!,
      );
      if (!didUpdate && mounted) {
        final message = widget.controller.errorMessage ??
            'We could not update that group photo right now.';
        widget.controller.clearError();
        await showErrorDialog(context, message);
        return;
      }
    }

    if (!mounted) {
      return;
    }
    _cancelGroupEdit();
  }

  Future<void> _showGroupPhotoOptions(ChatThread thread) async {
    final canRemove = _pendingGroupIconPhoto != null ||
        (!_pendingRemoveGroupIcon && thread.avatarUrl?.isNotEmpty == true);
    final action = await showAvatarPhotoOptionsSheet(
      context,
      canRemove: canRemove,
    );
    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case AvatarPhotoSheetAction.choose:
        final cropped = await pickAndCropAvatarPhoto(context);
        if (!mounted || cropped == null) {
          return;
        }
        setState(() {
          _pendingGroupIconPhoto = cropped;
          _pendingRemoveGroupIcon = false;
        });
      case AvatarPhotoSheetAction.remove:
        setState(() {
          _pendingGroupIconPhoto = null;
          _pendingRemoveGroupIcon = true;
        });
    }
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

String _groupSubtitle({
  required ChatThread thread,
  required bool isCommunityGroup,
  required bool isCommunityAnnouncement,
}) {
  final messageCount = '${thread.messages.length} messages';
  if (isCommunityAnnouncement) {
    return 'Announcements · $messageCount';
  }
  if (isCommunityGroup) {
    return 'Community group · $messageCount';
  }
  if (thread.isGroup) {
    return 'Group · $messageCount';
  }
  return 'Contact';
}

class _CommunityLinkRow extends StatelessWidget {
  const _CommunityLinkRow({
    required this.community,
    required this.onTap,
  });

  final CommunityHub community;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('contact_info_community_link_${community.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              AvatarBadge(
                label: community.avatarLabel,
                color: community.accentColor,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      community.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${community.memberCount} members · ${community.groupCount} groups',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.64),
                      ),
                    ),
                  ],
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

/// A single-row summary of how many messages are starred in this one
/// thread, tapping through to [StarredMessagesScreen] scoped to it -- the
/// per-chat counterpart to the global Settings > Chats > Starred messages
/// list, for finding a starred message without leaving the conversation
/// it's in.
class _StarredMessagesDisclosureRow extends StatelessWidget {
  const _StarredMessagesDisclosureRow({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('contact_info_starred_messages_row'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.star_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  count == 1 ? '1 starred message' : '$count starred messages',
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
