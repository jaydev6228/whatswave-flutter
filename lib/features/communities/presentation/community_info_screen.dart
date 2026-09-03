import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/media/avatar_photo_picker.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/avatar_preview.dart';
import '../../shared/widgets/error_dialog.dart';
import '../../shared/widgets/info_screen_chrome.dart';
import '../../shared/widgets/liquid_glass.dart';
import '../../shared/widgets/status_motion.dart';
import '../application/communities_controller.dart';
import '../domain/community_contact.dart';
import '../domain/community_hub.dart';

/// WhatsApp-style community info -- photo, name, description, members.
/// Same screen pattern as [ContactInfoScreen] for groups and contacts.
class CommunityInfoScreen extends StatefulWidget {
  const CommunityInfoScreen({
    required this.controller,
    required this.communityId,
    this.onAddMembers,
    this.startInEditMode = false,
    super.key,
  });

  final CommunitiesController controller;
  final String communityId;
  final VoidCallback? onAddMembers;
  final bool startInEditMode;

  @override
  State<CommunityInfoScreen> createState() => _CommunityInfoScreenState();
}

class _CommunityInfoScreenState extends State<CommunityInfoScreen> {
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
    _isEditing = widget.startInEditMode;
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
      animation: widget.controller,
      builder: (context, _) {
        final community = widget.controller.communityById(widget.communityId);
        if (community == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Community info')),
            body: const Center(
              child: Text('This community is no longer available.'),
            ),
          );
        }

        if (_isEditing && _titleController.text.isEmpty) {
          _titleController.text = community.title;
          _descriptionController.text = community.description;
        }

        final theme = Theme.of(context);
        final canEdit = community.viewerIsAdmin;
        final isBusy = widget.controller.isCommunityBusy(community.id);
        final nameStyle = theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        );
        final members = _communityMembersOf(widget.controller, community);

        return Scaffold(
          key: const Key('community_info_screen'),
          appBar: AppBar(
            title: const Text('Community info'),
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
                            key: const Key('community_info_edit_button'),
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
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    20 + MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IdentityCard(
                          community: community,
                          nameStyle: nameStyle,
                          isEditing: _isEditing && canEdit,
                          isBusy: isBusy,
                          titleController: _titleController,
                          descriptionController: _descriptionController,
                          pendingPhoto: _pendingPhoto,
                          pendingRemovePhoto: _pendingRemovePhoto,
                          onEditAvatarTap: (anchorContext) =>
                              _showPhotoOptions(anchorContext, community),
                        ),
                        const SizedBox(height: 14),
                        InfoSectionHeading(
                          '${community.displayMemberCount} members',
                        ),
                        InfoFlatPanel(
                          padding: EdgeInsets.zero,
                          child: Column(
                            key: const Key('community_detail_members_panel'),
                            children: [
                              if (community.viewerIsAdmin &&
                                  widget.onAddMembers != null &&
                                  !_isEditing) ...[
                                InfoPrimaryActionRow(
                                  actionKey: const Key(
                                    'community_info_add_members_button',
                                  ),
                                  icon: Icons.person_add_alt_outlined,
                                  label: 'Add members',
                                  onTap: widget.onAddMembers,
                                ),
                                Divider(
                                  height: 1,
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.22),
                                ),
                              ],
                              for (var index = 0;
                                  index < members.length;
                                  index++) ...[
                                if (index > 0)
                                  Divider(
                                    height: 1,
                                    color: theme.colorScheme.outlineVariant
                                        .withValues(alpha: 0.22),
                                  ),
                                _CommunityMemberRow(
                                  member: members[index],
                                  canManage: community.viewerIsAdmin &&
                                      !members[index].isSelf &&
                                      !members[index].isOwner &&
                                      !_isEditing,
                                  onManage: (anchorContext) =>
                                      _showMemberRoleMenu(
                                    anchorContext,
                                    community: community,
                                    member: members[index],
                                  ),
                                ),
                              ],
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

  Future<void> _showMemberRoleMenu(
    BuildContext anchorContext, {
    required CommunityHub community,
    required _CommunityMember member,
  }) async {
    final theme = Theme.of(anchorContext);
    final action = await showLiquidGlassBubbleMenu<_CommunityMemberAction>(
      anchorContext: anchorContext,
      itemBuilder: (sheetContext) => [
        LiquidGlassBubbleItem(
          key: const Key('community_detail_member_toggle_admin'),
          icon: member.isAdmin
              ? Icons.remove_moderator_outlined
              : Icons.admin_panel_settings_outlined,
          label: member.isAdmin
              ? 'Dismiss as community admin'
              : 'Make community admin',
          onTap: () => Navigator.of(sheetContext)
              .pop(_CommunityMemberAction.toggleAdmin),
        ),
        LiquidGlassBubbleItem(
          key: const Key('community_detail_member_remove'),
          icon: Icons.person_remove_outlined,
          label: 'Remove ${member.name}',
          color: theme.colorScheme.error,
          onTap: () =>
              Navigator.of(sheetContext).pop(_CommunityMemberAction.remove),
        ),
      ],
    );
    if (action == null || !anchorContext.mounted) {
      return;
    }

    switch (action) {
      case _CommunityMemberAction.toggleAdmin:
        final didChange = await widget.controller.setCommunityAdmin(
          communityId: community.id,
          memberUid: member.uid,
          isAdmin: !member.isAdmin,
        );
        if (didChange || !anchorContext.mounted) {
          return;
        }
        final message = widget.controller.errorMessage;
        if (message != null) {
          await showErrorDialog(anchorContext, message);
          widget.controller.clearError();
        }
      case _CommunityMemberAction.remove:
        await _confirmRemoveMember(
          anchorContext,
          community: community,
          member: member,
        );
    }
  }

  Future<void> _confirmRemoveMember(
    BuildContext context, {
    required CommunityHub community,
    required _CommunityMember member,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return LiquidGlassDialog(
          title: Text('Remove ${member.name}?'),
          content: Text(
            '${member.name} will leave "${community.title}" and its '
            'announcements. They stay in any other groups they were added to.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            LiquidGlassDialogAction(
              key: const Key('confirm_remove_community_member_button'),
              label: 'Remove',
              isDestructive: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    final didRemove = await widget.controller.removeCommunityMember(
      communityId: community.id,
      memberUid: member.uid,
    );
    if (didRemove || !context.mounted) {
      return;
    }
    final message = widget.controller.errorMessage;
    if (message != null) {
      await showErrorDialog(context, message);
      widget.controller.clearError();
    }
  }
}

enum _CommunityMemberAction { toggleAdmin, remove }

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.community,
    required this.nameStyle,
    required this.isEditing,
    required this.isBusy,
    required this.titleController,
    required this.descriptionController,
    required this.pendingPhoto,
    required this.pendingRemovePhoto,
    required this.onEditAvatarTap,
  });

  final CommunityHub community;
  final TextStyle? nameStyle;
  final bool isEditing;
  final bool isBusy;
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final File? pendingPhoto;
  final bool pendingRemovePhoto;
  final void Function(BuildContext anchorContext) onEditAvatarTap;

  static const double _avatarSize = 68;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget descriptionChild = const SizedBox.shrink();
    if (isEditing) {
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
          community.description.trim(),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
      );
    }

    return LiquidGlassSurface(
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
                  key: ValueKey<bool>(isEditing),
                  child: isEditing
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
              const SizedBox(height: 8),
              Text(
                '${community.displayMemberCount} members · ${community.groupCount} groups',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                  fontWeight: FontWeight.w600,
                ),
              ),
              StatusModeSwitcher(
                child: KeyedSubtree(
                  key: ValueKey<String>(isEditing ? 'edit' : 'read'),
                  child: descriptionChild,
                ),
              ),
            ],
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

    if (!isEditing) {
      return GestureDetector(
        key: const Key('community_detail_avatar'),
        onTap: () => showAvatarPreview(
          context,
          label: community.title,
          builder: (size) => AvatarBadge(
            label: community.avatarLabel,
            color: community.accentColor,
            avatarUrl: community.avatarUrl,
            size: size,
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
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.photo_camera_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

List<_CommunityMember> _communityMembersOf(
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

class _CommunityMemberRow extends StatelessWidget {
  const _CommunityMemberRow({
    required this.member,
    required this.canManage,
    required this.onManage,
  });

  final _CommunityMember member;
  final bool canManage;
  final void Function(BuildContext anchorContext) onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Builder(
      builder: (anchorContext) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('community_detail_member_row_${member.uid}'),
            onTap: canManage ? () => onManage(anchorContext) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  AvatarBadge(
                    label: member.avatarLabel,
                    color:
                        member.contact?.accentColor ?? theme.colorScheme.primary,
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
                      key: Key(
                        'community_detail_member_admin_badge_${member.uid}',
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
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
      },
    );
  }
}
