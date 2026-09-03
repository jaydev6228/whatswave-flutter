import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/media/avatar_photo_picker.dart';
import '../../calls/application/calls_controller.dart';
import '../../chats/application/chats_controller.dart';
import '../../chats/presentation/conversation_screen.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/avatar_preview.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../../shared/widgets/error_dialog.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/status_motion.dart';
import '../../updates/application/updates_controller.dart';
import '../application/communities_controller.dart';
import '../domain/app_invite_link.dart';
import '../domain/community_contact.dart';
import '../domain/community_hub.dart';
import '../domain/contact_access_status.dart';
import 'community_time_format.dart';
import 'community_unread.dart';
import 'package:whatswave/features/shared/widgets/liquid_glass.dart';

class CommunityDetailScreen extends StatefulWidget {
  const CommunityDetailScreen({
    required this.controller,
    required this.chatsController,
    required this.callsController,
    required this.updatesController,
    required this.communityId,
    super.key,
  });

  final CommunitiesController controller;
  final ChatsController chatsController;
  final CallsController callsController;
  final UpdatesController updatesController;
  final String communityId;

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  bool _isEditing = false;
  File? _pendingPhoto;
  bool _pendingRemovePhoto = false;
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.chatsController,
      ]),
      builder: (context, _) {
        final community = widget.controller.communityById(widget.communityId);
        if (community == null) {
          return const Scaffold(
            body: SafeArea(
              child: Center(
                child: EmptyStateCard(
                  icon: Icons.groups_outlined,
                  title: 'Community unavailable',
                  message:
                      'This community may have been removed while the app was open.',
                ),
              ),
            ),
          );
        }

        final canEdit = community.viewerIsAdmin;
        final isBusy = widget.controller.isCommunityBusy(community.id);

        return Scaffold(
          key: const Key('community_detail_screen'),
          appBar: AppBar(
            title: Text(community.title),
            actions: [
              if (canEdit)
                StatusModeSwitcher(
                  alignment: Alignment.centerRight,
                  unboundedWidth: true,
                  child: KeyedSubtree(
                    key: ValueKey<bool>(_isEditing),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_isEditing)
                          TextButton(
                            key: const Key('community_detail_edit_button'),
                            onPressed: isBusy
                                ? null
                                : () => _startEdit(community),
                            child: const Text('Edit'),
                          ),
                        if (_isEditing) ...[
                          TextButton(
                            key: const Key('community_detail_cancel_edit_button'),
                            onPressed: isBusy ? null : _cancelEdit,
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            key: const Key('community_detail_save_button'),
                            onPressed: isBusy
                                ? null
                                : () => _saveEdit(community),
                            child: isBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Done'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (!_isEditing) ...[
                IconButton(
                  key: const Key('community_detail_invite_button'),
                  tooltip: 'Invite members',
                  onPressed: () => _showInviteSheet(context, community),
                  icon: const Icon(Icons.person_add_outlined),
                ),
                PopupMenuButton<_CommunityDetailMenuAction>(
                  key: const Key('community_detail_menu_button'),
                  onSelected: (action) async {
                    switch (action) {
                      case _CommunityDetailMenuAction.delete:
                        await _confirmAndDeleteCommunity(
                          context,
                          controller: widget.controller,
                          community: community,
                        );
                      case _CommunityDetailMenuAction.exit:
                        await _confirmAndExitCommunity(
                          context,
                          controller: widget.controller,
                          community: community,
                        );
                    }
                  },
                  itemBuilder: (menuContext) => [
                    if (community.viewerIsOwner)
                      PopupMenuItem(
                        key: const Key('community_detail_delete_menu_item'),
                        value: _CommunityDetailMenuAction.delete,
                        child: Text(
                          'Deactivate community',
                          style: TextStyle(
                            color: Theme.of(menuContext).colorScheme.error,
                          ),
                        ),
                      )
                    else
                      PopupMenuItem(
                        key: const Key('community_detail_exit_menu_item'),
                        value: _CommunityDetailMenuAction.exit,
                        child: Text(
                          'Exit community',
                          style: TextStyle(
                            color: Theme.of(menuContext).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.only(
                bottom: 24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                const SizedBox(height: 8),
                _CommunityHeader(
                  community: community,
                  isEditing: _isEditing && canEdit,
                  canEdit: canEdit,
                  isBusy: isBusy,
                  titleController: _titleController,
                  descriptionController: _descriptionController,
                  pendingPhoto: _pendingPhoto,
                  pendingRemovePhoto: _pendingRemovePhoto,
                  onEditAvatarTap: (anchorContext) =>
                      _showPhotoOptions(anchorContext, community),
                ),
                const SizedBox(height: 12),
                _CommunityChatRow(
                  key: const Key('community_detail_announcements_row'),
                  leadingIcon: Icons.campaign_outlined,
                  leadingBackground: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.14),
                  leadingColor: Theme.of(context).colorScheme.primary,
                  title: 'Announcements',
                  subtitle: community.announcement.headline,
                  timestamp: community.announcement.publishedAt,
                  unreadCount: CommunityUnread.forAnnouncements(
                    widget.chatsController,
                    community,
                  ),
                  onTap: community.announcementThreadId == null
                      ? null
                      : () => _openThread(
                            context,
                            threadId: community.announcementThreadId!,
                          ),
                ),
                ...community.groups.map((group) {
                  return _CommunityChatRow(
                    key: Key('community_detail_group_${group.id}'),
                    leadingIcon: Icons.groups_outlined,
                    leadingBackground:
                        community.accentColor.withValues(alpha: 0.14),
                    leadingColor: community.accentColor,
                    title: group.name,
                    subtitle: group.threadId == null
                        ? 'Invite members to start chatting'
                        : group.summary,
                    timestamp: group.lastActivityAt,
                    unreadCount: CommunityUnread.forGroup(
                      widget.chatsController,
                      group,
                    ),
                    onTap: group.threadId == null
                        ? null
                        : () => _openThread(context, threadId: group.threadId!),
                  );
                }),
                if (community.memberUids.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _CommunityMembersPanel(
                      community: community,
                      members: _membersOf(widget.controller, community),
                      onManage: (member) => _showMemberRoleSheet(
                        context,
                        community: community,
                        member: member,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _startEdit(CommunityHub community) {
    _titleController.text = community.title;
    _descriptionController.text = community.description;
    setState(() {
      _isEditing = true;
      _pendingPhoto = null;
      _pendingRemovePhoto = false;
    });
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      _pendingPhoto = null;
      _pendingRemovePhoto = false;
    });
  }

  Future<void> _saveEdit(CommunityHub community) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      await showErrorDialog(context, 'Enter a community name.');
      return;
    }

    if (title != community.title) {
      final didRename = await widget.controller.renameCommunity(
        communityId: community.id,
        title: title,
      );
      if (!didRename && mounted) {
        final message = widget.controller.errorMessage ??
            'We could not rename that community right now.';
        widget.controller.clearError();
        await showErrorDialog(context, message);
        return;
      }
    }

    if (_descriptionController.text.trim() != community.description) {
      final didUpdate = await widget.controller.updateCommunityDescription(
        communityId: community.id,
        description: _descriptionController.text,
      );
      if (!didUpdate && mounted) {
        final message = widget.controller.errorMessage ??
            'We could not update that community right now.';
        widget.controller.clearError();
        await showErrorDialog(context, message);
        return;
      }
    }

    if (_pendingRemovePhoto) {
      final didRemove = await widget.controller.deleteCommunityAvatar(
        community.id,
      );
      if (!didRemove && mounted) {
        final message = widget.controller.errorMessage ??
            'We could not remove that community photo right now.';
        widget.controller.clearError();
        await showErrorDialog(context, message);
        return;
      }
    } else if (_pendingPhoto != null) {
      final didUpdate = await widget.controller.updateCommunityAvatar(
        communityId: community.id,
        photo: _pendingPhoto!,
      );
      if (!didUpdate && mounted) {
        final message = widget.controller.errorMessage ??
            'We could not update that community photo right now.';
        widget.controller.clearError();
        await showErrorDialog(context, message);
        return;
      }
    }

    if (!mounted) {
      return;
    }
    _cancelEdit();
  }

  Future<void> _showPhotoOptions(
    BuildContext anchorContext,
    CommunityHub community,
  ) async {
    final canRemove = _pendingPhoto != null ||
        (!_pendingRemovePhoto && community.avatarUrl?.isNotEmpty == true);
    final action = await showAvatarPhotoOptionsSheet(
      anchorContext,
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
          _pendingPhoto = cropped;
          _pendingRemovePhoto = false;
        });
      case AvatarPhotoSheetAction.remove:
        setState(() {
          _pendingPhoto = null;
          _pendingRemovePhoto = true;
        });
    }
  }

  Future<void> _showInviteSheet(
    BuildContext context,
    CommunityHub community,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.82,
          child: _CommunityDetailInviteSheet(
            controller: widget.controller,
            community: community,
          ),
        );
      },
    );
  }

  /// One row per uid on the community's roster, named from this device's
  /// address book where it can be (a member you have never had in your
  /// contacts is still on the roster and still needs a row).
  List<_CommunityMember> _membersOf(
    CommunitiesController controller,
    CommunityHub community,
  ) {
    final members = <_CommunityMember>[
      for (final uid in community.memberUids)
        _CommunityMember(
          uid: uid,
          contact: controller.contactForUid(uid),
          isAdmin: community.isAdminUid(uid),
          isOwner: uid == community.ownerUid,
          isSelf: uid == community.viewerUid,
        ),
    ];
    members.sort((left, right) {
      if (left.isSelf != right.isSelf) {
        return left.isSelf ? -1 : 1;
      }
      if (left.isAdmin != right.isAdmin) {
        return left.isAdmin ? -1 : 1;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return members;
  }

  Future<void> _showMemberRoleSheet(
    BuildContext context, {
    required CommunityHub community,
    required _CommunityMember member,
  }) async {
    final shouldToggle = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('community_detail_member_toggle_admin'),
                leading: Icon(
                  member.isAdmin
                      ? Icons.remove_moderator_outlined
                      : Icons.admin_panel_settings_outlined,
                ),
                title: Text(
                  member.isAdmin
                      ? 'Dismiss as community admin'
                      : 'Make community admin',
                ),
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
            ],
          ),
        );
      },
    );
    if (shouldToggle != true || !context.mounted) {
      return;
    }

    final didChange = await widget.controller.setCommunityAdmin(
      communityId: community.id,
      memberUid: member.uid,
      isAdmin: !member.isAdmin,
    );
    if (didChange || !context.mounted) {
      return;
    }
    // The refusals that matter are readable ones -- the 20-admin cap above
    // all (https://www.whatsapp.com/communities/learning/settingupyourcommunity)
    // -- so they get a dialog rather than a silently unchanged row.
    final message = widget.controller.errorMessage;
    if (message != null) {
      await showErrorDialog(context, message);
      widget.controller.clearError();
    }
  }

  Future<void> _openThread(
    BuildContext context, {
    required String threadId,
  }) async {
    widget.chatsController.openThread(threadId);

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          callsController: widget.callsController,
          controller: widget.chatsController,
          updatesController: widget.updatesController,
          communitiesController: widget.controller,
          threadId: threadId,
        ),
      ),
    );
  }
}

enum _CommunityDetailMenuAction { delete, exit }

Future<void> _confirmAndExitCommunity(
  BuildContext context, {
  required CommunitiesController controller,
  required CommunityHub community,
}) async {
  final shouldExit = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return LiquidGlassDialog(
        title: const Text('Exit community?'),
        content: Text(
          'You will stop receiving announcements from "${community.title}". '
          'The community and its groups stay for everyone else.',
        ),
        actions: [
          TextButton(
            key: const Key('community_detail_cancel_exit_button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('community_detail_confirm_exit_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Exit',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
              ),
            ),
          ),
        ],
      );
    },
  );
  if (shouldExit != true || !context.mounted) {
    return;
  }
  final didExit = await controller.exitCommunity(community.id);
  if (!context.mounted) {
    return;
  }
  if (didExit) {
    Navigator.of(context).pop();
  }
}

Future<void> _confirmAndDeleteCommunity(
  BuildContext context, {
  required CommunitiesController controller,
  required CommunityHub community,
}) async {
  final shouldDelete = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return LiquidGlassDialog(
        title: const Text('Deactivate community?'),
        // Says what deactivation actually does, which is not what this
        // used to claim ("permanently removes X and its groups for
        // everyone"): the groups are disconnected and survive as ordinary
        // group chats, only the community and its announcement group go,
        // and it cannot be undone
        // (https://faq.whatsapp.com/785738926054798).
        content: Text(
          '"${community.title}" disappears for everyone. Its groups keep '
          'working as ordinary group chats, its announcements close, and '
          'this cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Deactivate',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
              ),
            ),
          ),
        ],
      );
    },
  );

  if (shouldDelete != true) {
    return;
  }

  final didDelete = await controller.deactivateCommunity(community.id);
  if (!context.mounted) {
    return;
  }
  if (didDelete) {
    Navigator.of(context).pop();
  } else if (controller.errorMessage != null) {
    await showErrorDialog(context, controller.errorMessage!);
    controller.clearError();
  }
}

class _CommunityHeader extends StatelessWidget {
  const _CommunityHeader({
    required this.community,
    required this.isEditing,
    required this.canEdit,
    required this.isBusy,
    required this.titleController,
    required this.descriptionController,
    required this.pendingPhoto,
    required this.pendingRemovePhoto,
    required this.onEditAvatarTap,
  });

  final CommunityHub community;
  final bool isEditing;
  final bool canEdit;
  final bool isBusy;
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final File? pendingPhoto;
  final bool pendingRemovePhoto;
  final void Function(BuildContext anchorContext) onEditAvatarTap;

  static const double _avatarSize = 88;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w900,
    );

    Widget? descriptionSection;
    Widget descriptionChild = const SizedBox.shrink();
    if (isEditing && canEdit) {
      descriptionChild = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          key: const Key('community_detail_description_field'),
          controller: descriptionController,
          minLines: 1,
          maxLines: 4,
          maxLength: 200,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            hintText: 'What is this community about?',
            counterText: '',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
      );
    } else if (community.description.trim().isNotEmpty) {
      descriptionChild = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          community.description,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
      );
    }
    descriptionSection = StatusModeSwitcher(
      child: KeyedSubtree(
        key: ValueKey<String>(isEditing && canEdit ? 'edit' : 'read'),
        child: descriptionChild,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LiquidGlassSurface(
        borderRadius: const BorderRadius.all(Radius.circular(22)),
        blurred: false,
        showShadow: false,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: SizedBox(
          width: double.infinity,
          child: AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? const Duration(milliseconds: 1)
                : kStatusMotionDuration,
            curve: kStatusMotionCurve,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                _buildAvatar(context),
                const SizedBox(height: 10),
                StatusModeSwitcher(
                  child: KeyedSubtree(
                    key: ValueKey<bool>(isEditing && canEdit),
                    child: isEditing && canEdit
                        ? TextField(
                            key: const Key('community_detail_rename_field'),
                            controller: titleController,
                            textAlign: TextAlign.center,
                            maxLength: 60,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              hintText: 'Community name',
                              counterText: '',
                            ),
                            style: nameStyle,
                          )
                        : Text(
                            community.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: nameStyle,
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${community.memberCount} members · ${community.groupCount} groups',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                descriptionSection,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final effectiveUrl = pendingRemovePhoto
        ? null
        : (pendingPhoto?.path ?? community.avatarUrl);

    Widget avatar = pendingPhoto != null
        ? ClipOval(
            child: Image.file(
              pendingPhoto!,
              width: _avatarSize,
              height: _avatarSize,
              fit: BoxFit.cover,
            ),
          )
        : AvatarBadge(
            label: community.avatarLabel,
            color: community.accentColor,
            size: _avatarSize,
            avatarUrl: effectiveUrl,
          );

    if (!isEditing || !canEdit) {
      return GestureDetector(
        key: const Key('community_detail_avatar'),
        onTap: () => showAvatarPreview(
          context,
          label: community.title,
          builder: (size) => AvatarBadge(
            label: community.avatarLabel,
            color: community.accentColor,
            size: size,
            avatarUrl: community.avatarUrl,
          ),
        ),
        child: avatar,
      );
    }

    return Builder(
      builder: (anchorContext) => GestureDetector(
        key: const Key('community_detail_change_photo_button'),
        onTap: isBusy ? null : () => onEditAvatarTap(anchorContext),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            AvatarCameraBadge(isBusy: isBusy),
          ],
        ),
      ),
    );
  }
}

class _CommunityChatRow extends StatelessWidget {
  const _CommunityChatRow({
    required this.leadingIcon,
    required this.leadingBackground,
    required this.leadingColor,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.unreadCount,
    required this.onTap,
    super.key,
  });

  final IconData leadingIcon;
  final Color leadingBackground;
  final Color leadingColor;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final int unreadCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: leadingBackground,
                child: Icon(
                  leadingIcon,
                  color: leadingColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Opacity(
                  opacity: enabled ? 1 : 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            formatCommunityTimestamp(timestamp),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.56),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: unreadCount > 0
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurface
                                        .withValues(alpha: 0.68),
                                fontWeight: unreadCount > 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: theme.colorScheme.primary,
                              child: Text(
                                unreadCount > 99 ? '99+' : '$unreadCount',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ] else if (enabled) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.38),
                            ),
                          ],
                        ],
                      ),
                    ],
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

class _CommunityDetailInviteSheet extends StatefulWidget {
  const _CommunityDetailInviteSheet({
    required this.controller,
    required this.community,
  });

  final CommunitiesController controller;
  final CommunityHub community;

  @override
  State<_CommunityDetailInviteSheet> createState() =>
      _CommunityDetailInviteSheetState();
}

class _CommunityDetailInviteSheetState
    extends State<_CommunityDetailInviteSheet> {
  late final TextEditingController _searchController;

  String get _normalizedQuery => _searchController.text.trim().toLowerCase();
  bool get _isSearching => _normalizedQuery.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()
      ..addListener(_handleSearchChange);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChange)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChange() {
    if (mounted) {
      setState(() {});
    }
  }

  bool _matchesSearch(CommunityContact contact) {
    if (_normalizedQuery.isEmpty) {
      return true;
    }

    return contact.name.toLowerCase().contains(_normalizedQuery) ||
        contact.phoneNumber.toLowerCase().contains(_normalizedQuery) ||
        contact.about.toLowerCase().contains(_normalizedQuery);
  }

  List<CommunityContact> _sortedMatchingContacts(
      Iterable<CommunityContact> contacts) {
    final matchingContacts =
        contacts.where(_matchesSearch).toList(growable: false);
    matchingContacts.sort((left, right) => left.name.compareTo(right.name));
    return matchingContacts;
  }

  Future<void> _inviteContact(CommunityContact contact) async {
    final didInvite = await widget.controller.inviteContactToCommunity(
      communityId: widget.community.id,
      contactId: contact.id,
    );
    if (!mounted) {
      return;
    }
    if (didInvite) {
      await HapticFeedback.selectionClick();
      return;
    }

    await _showErrorDialogForController();
  }

  Future<void> _shareAppInvite(CommunityContact contact) async {
    final didPrepareInvite = await widget.controller.shareAppInvite(contact.id);
    if (!mounted) {
      return;
    }
    if (!didPrepareInvite) {
      await _showErrorDialogForController();
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: buildCommunityAppInviteLink(contact)),
    );
    if (!mounted) {
      return;
    }
    await HapticFeedback.selectionClick();
  }

  Future<void> _showErrorDialogForController() async {
    final message = widget.controller.errorMessage;
    if (message == null) {
      return;
    }

    await showErrorDialog(context, message);
    widget.controller.clearError();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final community = widget.community;
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        final contacts = _sortedMatchingContacts(controller.contacts);
        final readyContacts = contacts.where((contact) {
          return contact.isOnWhatsWave &&
              contact.membershipStateFor(community.id) ==
                  CommunityMembershipState.none;
        }).toList(growable: false);
        final invitedContacts = contacts.where((contact) {
          return contact.isOnWhatsWave &&
              contact.membershipStateFor(community.id) ==
                  CommunityMembershipState.invited;
        }).toList(growable: false);
        final memberContacts = contacts.where((contact) {
          return contact.isOnWhatsWave &&
              contact.membershipStateFor(community.id) ==
                  CommunityMembershipState.member;
        }).toList(growable: false);
        final needsAppInviteContacts = contacts
            .where((contact) => !contact.isOnWhatsWave)
            .toList(growable: false);
        final hasMatches = readyContacts.isNotEmpty ||
            invitedContacts.isNotEmpty ||
            memberContacts.isNotEmpty ||
            needsAppInviteContacts.isNotEmpty;

        return SafeArea(
          top: false,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Column(
                key: const Key('community_detail_invite_sheet'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add members',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Search your contacts to add people to ${community.title}.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                  ),
                  const SizedBox(height: 16),
                  SearchField(
                    fieldKey: const Key('community_detail_invite_search_field'),
                    controller: _searchController,
                    hintText: 'Search name or number',
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        if (!controller.contactAccessStatus.hasAnyAccess)
                          Column(
                            children: [
                              const EmptyStateCard(
                                icon: Icons.contact_phone_outlined,
                                title: 'Contacts are hidden for now',
                                message:
                                    'Allow contact access to search your phone book and invite people into this community here.',
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  FilledButton.icon(
                                    key: const Key(
                                      'community_detail_request_contacts_button',
                                    ),
                                    onPressed:
                                        controller.isRequestingContactsAccess
                                            ? null
                                            : () async {
                                                await controller
                                                    .requestContactsAccess();
                                              },
                                    icon:
                                        const Icon(Icons.contact_phone_rounded),
                                    label: Text(
                                      controller.isRequestingContactsAccess
                                          ? 'Checking...'
                                          : 'Allow contacts',
                                    ),
                                  ),
                                  if (controller.contactAccessStatus ==
                                      ContactAccessStatus.denied)
                                    OutlinedButton(
                                      key: const Key(
                                        'community_detail_open_settings_button',
                                      ),
                                      onPressed: () async {
                                        await controller.openContactSettings();
                                      },
                                      child: const Text('Open settings'),
                                    ),
                                ],
                              ),
                            ],
                          )
                        else if (controller.contacts.isEmpty)
                          const EmptyStateCard(
                            icon: Icons.person_search_outlined,
                            title: 'No contacts available yet',
                            message:
                                'Once contacts are available, you can search them and invite the right people into this community here.',
                          )
                        else if (!hasMatches)
                          const EmptyStateCard(
                            icon: Icons.person_search_outlined,
                            title: 'No matching contacts',
                            message:
                                'Try a different name, phone number, or note to find someone else.',
                          )
                        else if (_isSearching)
                          _CommunityInviteSection(
                            title: 'Search results',
                            subtitle: 'People matching your search.',
                            children: contacts
                                .map(
                                  (contact) => _buildInviteListItem(
                                    controller: controller,
                                    community: community,
                                    contact: contact,
                                  ),
                                )
                                .toList(growable: false),
                          )
                        else ...[
                          if (readyContacts.isNotEmpty)
                            _CommunityInviteSection(
                              title: 'Add to community',
                              subtitle:
                                  'These contacts are on WhatsWave and can be added now.',
                              children: readyContacts
                                  .map(
                                    (contact) => _buildInviteListItem(
                                      controller: controller,
                                      community: community,
                                      contact: contact,
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          if (invitedContacts.isNotEmpty)
                            _CommunityInviteSection(
                              title: 'Pending',
                              subtitle:
                                  'These people already have a community invite waiting.',
                              children: invitedContacts
                                  .map(
                                    (contact) => _buildInviteListItem(
                                      controller: controller,
                                      community: community,
                                      contact: contact,
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          if (memberContacts.isNotEmpty)
                            _CommunityInviteSection(
                              title: 'Already added',
                              subtitle:
                                  'These contacts are already part of ${community.title}.',
                              children: memberContacts
                                  .map(
                                    (contact) => _buildInviteListItem(
                                      controller: controller,
                                      community: community,
                                      contact: contact,
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          if (needsAppInviteContacts.isNotEmpty)
                            _CommunityInviteSection(
                              title: 'Invite to WhatsWave first',
                              subtitle:
                                  'Share the app with these contacts before adding them to this community.',
                              children: needsAppInviteContacts
                                  .map(
                                    (contact) => _buildInviteListItem(
                                      controller: controller,
                                      community: community,
                                      contact: contact,
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                        ],
                      ],
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

  _CommunityInviteListItem _buildInviteListItem({
    required CommunitiesController controller,
    required CommunityHub community,
    required CommunityContact contact,
  }) {
    final membershipState = contact.membershipStateFor(community.id);
    // Only the row being added may go busy. isCommunityBusy is a single
    // per-community flag the invite mutation sets for the whole community,
    // so ORing it in here flipped every contact's button to "Adding..." at
    // once when one row was tapped.
    final isBusy = controller.isContactBusy(contact.id);

    late final String label;
    late final VoidCallback? onPressed;

    if (!contact.isOnWhatsWave) {
      label = contact.appInviteSent
          ? 'Invite sent'
          : isBusy
              ? 'Sharing...'
              : 'Share app';
      onPressed = contact.appInviteSent || isBusy
          ? null
          : () => _shareAppInvite(contact);
    } else {
      switch (membershipState) {
        case CommunityMembershipState.none:
          label = isBusy ? 'Adding...' : 'Add';
          onPressed = isBusy ? null : () => _inviteContact(contact);
        case CommunityMembershipState.invited:
          label = 'Pending';
          onPressed = null;
        case CommunityMembershipState.member:
          label = 'Added';
          onPressed = null;
      }
    }

    return _CommunityInviteListItem(
      contact: contact,
      actionKey: Key('community_detail_invite_action_${contact.id}'),
      label: label,
      onPressed: onPressed,
    );
  }
}

class _CommunityInviteSection extends StatelessWidget {
  const _CommunityInviteSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.68),
                ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _CommunityInviteListItem extends StatelessWidget {
  const _CommunityInviteListItem({
    required this.contact,
    required this.actionKey,
    required this.label,
    required this.onPressed,
  });

  final CommunityContact contact;
  final Key actionKey;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionWidth = math.min(
      MediaQuery.sizeOf(context).width * 0.34,
      124.0,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
          ),
        ),
        child: InkWell(
          key: Key('community_detail_invite_contact_${contact.id}'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AvatarBadge(
                  label: contact.avatarLabel,
                  color: contact.accentColor,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        contact.phoneNumber,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: actionWidth,
                  child: FilledButton.tonal(
                    key: actionKey,
                    onPressed: onPressed,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A community member as the roster renders them: a uid, whatever this
/// device knows them as, and their role.
class _CommunityMember {
  const _CommunityMember({
    required this.uid,
    required this.contact,
    required this.isAdmin,
    required this.isOwner,
    required this.isSelf,
  });

  final String uid;
  final CommunityContact? contact;
  final bool isAdmin;
  final bool isOwner;
  final bool isSelf;

  String get name => isSelf ? 'You' : contact?.name ?? 'WhatsWave member';

  String get avatarLabel => contact?.avatarLabel ?? (isSelf ? 'Y' : '?');
}

/// The members roster. Until this existed the only place a person appeared
/// at all was the invite sheet, so there was nowhere to promote anyone
/// from.
class _CommunityMembersPanel extends StatelessWidget {
  const _CommunityMembersPanel({
    required this.community,
    required this.members,
    required this.onManage,
  });

  final CommunityHub community;
  final List<_CommunityMember> members;
  final ValueChanged<_CommunityMember> onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading('${members.length} members'),
        _FlatInfoPanel(
          padding: EdgeInsets.zero,
          child: Column(
            key: const Key('community_detail_members_panel'),
            children: [
              for (var index = 0; index < members.length; index++) ...[
                if (index > 0)
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.22),
                  ),
                _CommunityMemberRow(
                  member: members[index],
                  // Roles are an admin's to hand out, and nobody may act on
                  // their own row or on the creator's: self-promotion would
                  // make the list meaningless, and demoting the owner is how
                  // two admins would lock them out of their own community.
                  canManage: community.viewerIsAdmin &&
                      !members[index].isSelf &&
                      !members[index].isOwner,
                  onTap: () => onManage(members[index]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CommunityMemberRow extends StatelessWidget {
  const _CommunityMemberRow({
    required this.member,
    required this.canManage,
    required this.onTap,
  });

  final _CommunityMember member;
  final bool canManage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('community_detail_member_row_${member.uid}'),
        onTap: canManage ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              AvatarBadge(
                label: member.avatarLabel,
                color: member.contact?.accentColor ?? theme.colorScheme.primary,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w400),
                ),
              ),
              if (member.isAdmin) ...[
                const SizedBox(width: 8),
                Container(
                  key: Key('community_detail_member_admin_badge_${member.uid}'),
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

/// Local copies of contact info's section heading and flat panel: those are
/// private to lib/features/chats, and this is the same list-section look
/// (heading, glass panel, outlineVariant dividers at 0.22).
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _FlatInfoPanel extends StatelessWidget {
  const _FlatInfoPanel({
    required this.child,
    this.padding = const EdgeInsets.all(2),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LiquidGlassSurface(
      // Unblurred: the panel sits on an opaque scaffold, so a BackdropFilter
      // would cost a saveLayer per section for no visible frost.
      blurred: false,
      showShadow: false,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      borderColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
      padding: padding,
      child: child,
    );
  }
}
