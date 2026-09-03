import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/media/avatar_photo_picker.dart';
import '../../../core/utils/user_profile_lookup.dart';
import '../../calls/application/calls_controller.dart';
import '../../communities/application/communities_controller.dart';
import '../../communities/domain/community_hub.dart';
import '../../communities/presentation/community_detail_screen.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/error_dialog.dart';
import '../../shared/widgets/avatar_preview.dart';
import '../../shared/widgets/status_motion.dart';
import '../../shared/widgets/thread_avatar.dart';
import '../../updates/application/updates_controller.dart';
import '../application/chats_controller.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_thread.dart';
import '../domain/group_participant.dart';
import 'add_group_members_screen.dart';
import 'shared_media_screen.dart';
import 'starred_messages_screen.dart';
import 'package:whatswave/features/shared/widgets/liquid_glass.dart';

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
  UserProfileSnapshot? _contactProfile;
  bool _isEditingGroup = false;
  // Long-lived, not created on entering edit mode and disposed on leaving
  // it. The name/description fields now fade out over 300ms, so they are
  // still building for a while after edit mode ends -- disposing on leave
  // threw "A TextEditingController was used after being disposed" on the
  // first frame of the exit, and re-entering edit mid-fade would have done
  // the same to the field on its way out.
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _groupDescriptionController =
      TextEditingController();
  File? _pendingGroupIconPhoto;
  bool _pendingRemoveGroupIcon = false;

  @override
  void dispose() {
    _groupNameController.dispose();
    _groupDescriptionController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCommonGroups();
    _loadContactProfile();
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

  Future<void> _loadContactProfile() async {
    final thread = widget.controller.threadById(widget.threadId);
    if (thread == null || thread.isGroup) {
      return;
    }
    // Same key fallback as _loadCommonGroups: demo threads carry no
    // participantUid, and their id is the contact slug the demo profile is
    // keyed by. A real thread always has the uid, so the fallback never
    // matters there.
    final profile = await widget.controller.contactProfile(
      thread.participantUid ?? thread.id,
    );
    if (!mounted) return;
    setState(() => _contactProfile = profile);
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

        // One style for both the editable field and the static header, so
        // entering edit mode doesn't resize the name and reflow the page.
        // titleLarge made a group name the loudest thing on the screen,
        // louder than the app bar title naming the screen.
        final nameStyle = theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        );

        final about = _contactProfile?.about?.trim() ?? '';
        // Published profile first (the owner registered it, so it's
        // authoritative), then this device's address book. Without the
        // fallback a contact who hasn't run a build that publishes
        // phoneNumber shows no number at all -- see
        // CommunitiesController.phoneNumberForUid.
        final publishedPhone = _contactProfile?.phoneNumber?.trim() ?? '';
        final phone = publishedPhone.isNotEmpty
            ? publishedPhone
            : widget.communitiesController
                    .phoneNumberForUid(thread.participantUid ?? thread.id)
                    ?.trim() ??
                '';

        final canEditGroup = thread.isGroup &&
            thread.currentUserIsGroupAdmin &&
            !isCommunityAnnouncement;
        final isGroupIconBusy = widget.controller.isThreadBusy(thread.id);

        return Scaffold(
          appBar: AppBar(
            title: Text(thread.isGroup ? 'Group info' : 'Contact info'),
            actions: [
              // One switcher rather than three conditional children: the
              // action area swaps wholesale between "Edit" and
              // "Cancel/Done", and cross-fading the whole row is what stops
              // Done appearing on top of where Edit was standing. Keyed on
              // the mode only, so the Done button's busy spinner rebuilds in
              // place instead of restarting the transition.
              StatusModeSwitcher(
                alignment: Alignment.centerRight,
                unboundedWidth: true,
                child: KeyedSubtree(
                  key: ValueKey<bool>(_isEditingGroup),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                        _buildIdentityCard(
                          context: context,
                          thread: thread,
                          theme: theme,
                          nameStyle: nameStyle,
                          canEditGroup: canEditGroup,
                          isGroupIconBusy: isGroupIconBusy,
                          about: about,
                          phone: phone,
                        ),
                        const SizedBox(height: 14),
                        if (communityContext != null) ...[
                          _SectionHeading('Community'),
                          _FlatInfoPanel(
                            padding: EdgeInsets.zero,
                            child: _CommunityLinkRow(
                              community: communityContext.community,
                              onTap: () => _openCommunity(
                                communityContext.community.id,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
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
                          const SizedBox(height: 14),
                        ],
                        if (mediaAttachments.isNotEmpty) ...[
                          _SectionHeading('Shared media'),
                          _FlatInfoPanel(
                            padding: EdgeInsets.zero,
                            child: _SharedMediaDisclosureRow(
                              attachments: mediaAttachments,
                              threadName: thread.name,
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (threadStarredCount > 0) ...[
                          _SectionHeading('Starred messages'),
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
                          const SizedBox(height: 14),
                        ],
                        if (thread.isGroup &&
                            (thread.participants?.isNotEmpty ?? false)) ...[
                          _SectionHeading(
                            '${thread.participants!.length} participants',
                          ),
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
                                        .withValues(alpha: 0.22),
                                  ),
                                ],
                                for (var index = 0;
                                    index < thread.participants!.length;
                                    index++) ...[
                                  if (index > 0)
                                    Divider(
                                      height: 1,
                                      color: theme.colorScheme.outlineVariant
                                          .withValues(alpha: 0.22),
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
                          const SizedBox(height: 14),
                        ],
                        if (!thread.isGroup &&
                            _hasLoadedCommonGroups &&
                            _commonGroups.isNotEmpty) ...[
                          _SectionHeading('Common groups'),
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
                                          .withValues(alpha: 0.22),
                                    ),
                                  _CommonGroupRow(group: _commonGroups[index]),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        _SectionHeading('Actions'),
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
                                    .withValues(alpha: 0.22),
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
        return LiquidGlassDialog(
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
            LiquidGlassDialogAction(
              key: const Key('contact_info_confirm_clear_chat_button'),
              label: 'Clear chat',
              isDestructive: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
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
        return LiquidGlassDialog(
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

  /// Everything that identifies this thread, in one card above the lists.
  ///
  /// The identity used to be scattered: a bare centred avatar and name, an
  /// "About" list row that read like a setting rather than a fact about the
  /// person, and -- for groups -- a description floating unowned between two
  /// sections. One card, styled unlike the rows below it, says "this is who
  /// this is" and leaves the panels underneath to be what you can do.
  ///
  /// The "Contact" / "Group - N messages" subtitle is gone. Neither told the
  /// reader anything they did not already know from the screen they opened.
  Widget _buildIdentityCard({
    required BuildContext context,
    required ChatThread thread,
    required ThemeData theme,
    required TextStyle? nameStyle,
    required bool canEditGroup,
    required bool isGroupIconBusy,
    required String about,
    required String phone,
  }) {
    final details = <Widget>[];

    // The group description swaps between a read-only line, an editable
    // field, and nothing at all (a group with no description yet). One
    // switcher covering all three keeps its own top spacing, because a
    // spacer in the caller's loop would leave an 8pt phantom gap under the
    // name for every description-less group.
    Widget? groupDescription;
    if (thread.isGroup) {
      Widget descriptionChild = const SizedBox.shrink();
      if (_isEditingGroup && canEditGroup) {
        descriptionChild = Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            key: const Key('edit_group_description_field'),
            controller: _groupDescriptionController,
            minLines: 1,
            maxLines: 3,
            maxLength: 200,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.sentences,
            // isDense alone does nothing here -- the app theme sets an
            // explicit 18/16 contentPadding, which with a two-line rest
            // height left a 15-character description standing taller than
            // two participant rows. The counter is chrome for a limit a
            // description never approaches.
            decoration: const InputDecoration(
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              hintText: 'What is this group about?',
              counterText: '',
            ),
          ),
        );
      } else if (thread.groupDescription?.trim().isNotEmpty ?? false) {
        descriptionChild = Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _identityDetail(theme, thread.groupDescription!.trim()),
        );
      }
      groupDescription = StatusModeSwitcher(
        child: KeyedSubtree(
          key: ValueKey<String>(
            _isEditingGroup && canEditGroup ? 'edit' : 'read',
          ),
          child: descriptionChild,
        ),
      );
    } else {
      if (about.isNotEmpty) {
        details.add(
          _identityDetail(theme, about,
              rowKey: const Key('contact_info_about_row')),
        );
      }
      if (phone.isNotEmpty) {
        details.add(
          _identityDetail(
            theme,
            phone,
            rowKey: const Key('contact_info_phone_row'),
            emphasise: true,
          ),
        );
      }
    }

    return LiquidGlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(22)),
      blurred: false,
      showShadow: false,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: SizedBox(
        width: double.infinity,
        // The fields are taller than the text they replace. Without this the
        // card snapped to its edit-mode height on the first frame and then
        // spent the whole crossfade with the new content arriving into a box
        // that had already finished moving.
        child: AnimatedSize(
          // One millisecond, not statusMotionDuration's Duration.zero, under
          // reduced motion: RenderAnimatedSize settles inside its own
          // performLayout at zero and asserts "a RenderObject must not
          // re-dirty itself while still being laid out". A single frame is
          // below the threshold of motion anyway.
          duration: MediaQuery.disableAnimationsOf(context)
              ? const Duration(milliseconds: 1)
              : kStatusMotionDuration,
          curve: kStatusMotionCurve,
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              _buildGroupAvatarHeader(
                thread: thread,
                theme: theme,
                isBusy: isGroupIconBusy,
              ),
              const SizedBox(height: 10),
              StatusModeSwitcher(
                child: KeyedSubtree(
                  key: ValueKey<bool>(_isEditingGroup && canEditGroup),
                  child: (_isEditingGroup && canEditGroup)
                      ? TextField(
                          key: const Key('rename_group_field'),
                          controller: _groupNameController,
                          textAlign: TextAlign.center,
                          maxLength: 60,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            hintText: 'Group name',
                            counterText: '',
                          ),
                          style: nameStyle,
                        )
                      : Text(
                          thread.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle,
                        ),
                ),
              ),
              if (groupDescription != null) groupDescription,
              for (final detail in details) ...[
                const SizedBox(height: 8),
                detail,
              ],
              if (thread.isBlocked) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Blocked',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.error,
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

  /// A line of identity under the name -- an About, a phone number, a group
  /// description. No leading icon and no caption underneath: in a card that
  /// is plainly about this one person, "About" labelled the obvious and
  /// made a fact read like a settings row.
  Widget _identityDetail(
    ThemeData theme,
    String value, {
    Key? rowKey,
    bool emphasise = false,
  }) {
    return Text(
      value,
      key: rowKey,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface
            .withValues(alpha: emphasise ? 0.9 : 0.72),
        fontWeight: emphasise ? FontWeight.w600 : null,
      ),
    );
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
              width: 68,
              height: 68,
              fit: BoxFit.cover,
            ),
          )
        : _pendingRemoveGroupIcon
            ? ThreadAvatar(
                thread: thread.copyWith(clearAvatarUrl: true),
                size: 68,
              )
            : ThreadAvatar(thread: thread, size: 68);

    if (!_isEditingGroup || !canEdit) {
      // Tapping opens it full screen, the same way a photo in the thread
      // does. ThreadAvatar is handed the larger size rather than the 68pt
      // one being scaled up, so a group's composite icon re-composes its
      // members' avatars at that size instead of blurring.
      return GestureDetector(
        key: const Key('contact_info_avatar'),
        onTap: () => showAvatarPreview(
          context,
          label: thread.name,
          builder: (size) => ThreadAvatar(thread: thread, size: size),
        ),
        child: avatar,
      );
    }

    // Builder so the options bubble anchors to the avatar itself. Handed
    // the screen's context it would measure the whole page and open in the
    // middle of nowhere.
    return Builder(
      builder: (anchorContext) => GestureDetector(
        key: const Key('contact_info_change_group_icon_button'),
        onTap:
            isBusy ? null : () => _showGroupPhotoOptions(anchorContext, thread),
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

  void _startGroupEdit(ChatThread thread) {
    _groupNameController.text = thread.name;
    _groupDescriptionController.text = thread.groupDescription ?? '';
    setState(() {
      _isEditingGroup = true;
      _pendingGroupIconPhoto = null;
      _pendingRemoveGroupIcon = false;
    });
  }

  void _cancelGroupEdit() {
    setState(() {
      _isEditingGroup = false;
      _pendingGroupIconPhoto = null;
      _pendingRemoveGroupIcon = false;
    });
  }

  Future<void> _saveGroupEdit(ChatThread thread) async {
    final name = _groupNameController.text.trim();
    final description = _groupDescriptionController.text.trim();

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

  Future<void> _showGroupPhotoOptions(
    BuildContext anchorContext,
    ChatThread thread,
  ) async {
    final canRemove = _pendingGroupIconPhoto != null ||
        (!_pendingRemoveGroupIcon && thread.avatarUrl?.isNotEmpty == true);
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
        return LiquidGlassDialog(
          title: Text('Remove ${participant.name}?'),
          content: Text(
            '${participant.name} will be removed from ${thread.name}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            LiquidGlassDialogAction(
              key: const Key('confirm_remove_participant_button'),
              label: 'Remove',
              isDestructive: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
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
        return LiquidGlassDialog(
          title: const Text('Exit group?'),
          content: Text(
            "You'll no longer receive messages from ${thread.name}.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            LiquidGlassDialogAction(
              key: const Key('confirm_exit_group_button'),
              label: 'Exit group',
              isDestructive: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
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

/// Section labels read as list-section captions, not page titles -- the
/// screen stacks up to six of them, and at title size they pushed most of
/// the content below the fold on a compact phone.
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              AvatarBadge(
                label: community.avatarLabel,
                color: community.accentColor,
                size: 38,
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
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${community.displayMemberCount} members · ${community.groupCount} groups',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.64),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: SharedMediaThumbnail(attachment: previewAttachment),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  attachments.length == 1
                      ? '1 item'
                      : '${attachments.length} items',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w400),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.star_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  count == 1 ? '1 starred message' : '$count starred messages',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w400),
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

/// One line of the contact's own published profile -- the value reads
/// first and its caption underneath, matching how [_CommunityLinkRow]
/// stacks title over subtitle rather than introducing a second row idiom.
class _CommonGroupRow extends StatelessWidget {
  const _CommonGroupRow({required this.group});

  final ChatThread group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          AvatarBadge(
              label: group.avatarLabel, color: group.accentColor, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w400),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              AvatarBadge(
                label: participant.avatarLabel,
                color: participant.accentColor,
                avatarUrl: participant.avatarUrl,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  participant.isSelf ? 'You' : participant.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w400),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w400,
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
