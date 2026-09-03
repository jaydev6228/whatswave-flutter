import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../calls/application/calls_controller.dart';
import '../../chats/application/chats_controller.dart';
import '../../chats/presentation/conversation_screen.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/glass_text_field.dart';
import '../../shared/widgets/create_action_row.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../../shared/widgets/error_dialog.dart';
import '../../shared/widgets/info_screen_chrome.dart';
import '../../shared/widgets/search_field.dart';
import '../../updates/application/updates_controller.dart';
import '../application/communities_controller.dart';
import '../domain/app_invite_link.dart';
import '../domain/community_contact.dart';
import '../domain/community_group_preview.dart';
import '../domain/community_hub.dart';
import '../domain/contact_access_status.dart';
import 'community_info_screen.dart';
import 'community_time_format.dart';
import 'community_unread.dart';
import 'package:whatswave/features/shared/widgets/liquid_glass.dart';

class CommunityDetailScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        chatsController,
      ]),
      builder: (context, _) {
        final community = controller.communityById(communityId);
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
        final isBusy = controller.isCommunityBusy(community.id);

        return Scaffold(
          key: const Key('community_detail_screen'),
          appBar: AppBar(
            title: GestureDetector(
              key: const Key('community_detail_title_button'),
              onTap: () => _openCommunityInfo(context, controller, community),
              child: Text(
                community.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            actions: [
              if (canEdit)
                IconButton(
                  key: const Key('community_detail_invite_button'),
                  tooltip: 'Invite members',
                  onPressed: () => _showInviteSheet(context, controller, community),
                  icon: const Icon(Icons.person_add_outlined),
                ),
              Builder(
                builder: (menuContext) => IconButton(
                  key: const Key('community_detail_menu_button'),
                  tooltip: 'Community options',
                  onPressed: isBusy
                      ? null
                      : () => _showCommunityMenu(
                            context,
                            menuContext,
                            controller,
                            community,
                          ),
                  icon: const Icon(Icons.more_vert),
                ),
              ),
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
                    chatsController,
                    community,
                  ),
                  onTap: community.announcementThreadId == null
                      ? null
                      : () => _openThread(
                            context,
                            chatsController: chatsController,
                            callsController: callsController,
                            updatesController: updatesController,
                            communitiesController: controller,
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
                      chatsController,
                      group,
                    ),
                    onTap: group.threadId == null
                        ? null
                        : () => _openThread(
                              context,
                              chatsController: chatsController,
                              callsController: callsController,
                              updatesController: updatesController,
                              communitiesController: controller,
                              threadId: group.threadId!,
                            ),
                    onManage: canEdit
                        ? () => _confirmDetachGroup(
                              context,
                              controller: controller,
                              community: community,
                              group: group,
                            )
                        : null,
                  );
                }),
                if (canEdit)
                  CreateActionRow(
                    rowKey: const Key('community_detail_add_group_button'),
                    label: 'Add group',
                    icon: Icons.group_add_outlined,
                    onTap: () => _showAddGroupSheet(context, controller, community),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> _showInviteSheet(
  BuildContext context,
  CommunitiesController controller,
  CommunityHub community,
) async {
  await showGlassBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    heightFactor: 0.82,
    builder: (_) => _CommunityDetailInviteSheet(
      controller: controller,
      community: community,
    ),
  );
}

Future<void> _showCommunityMenu(
  BuildContext context,
  BuildContext anchorContext,
  CommunitiesController controller,
  CommunityHub community,
) async {
  final theme = Theme.of(anchorContext);
  final action = await showLiquidGlassBubbleMenu<_CommunityDetailMenuAction>(
    anchorContext: anchorContext,
    openBelow: true,
    itemBuilder: (sheetContext) => [
      LiquidGlassBubbleItem(
        key: const Key('community_detail_info_menu_item'),
        icon: Icons.groups_outlined,
        label: 'Community info',
        onTap: () => Navigator.of(sheetContext)
            .pop(_CommunityDetailMenuAction.communityInfo),
      ),
      if (community.viewerIsOwner)
        LiquidGlassBubbleItem(
          key: const Key('community_detail_delete_menu_item'),
          icon: Icons.delete_outline_rounded,
          label: 'Deactivate community',
          color: theme.colorScheme.error,
          onTap: () => Navigator.of(sheetContext)
              .pop(_CommunityDetailMenuAction.delete),
        )
      else
        LiquidGlassBubbleItem(
          key: const Key('community_detail_exit_menu_item'),
          icon: Icons.logout_rounded,
          label: 'Exit community',
          color: theme.colorScheme.error,
          onTap: () =>
              Navigator.of(sheetContext).pop(_CommunityDetailMenuAction.exit),
        ),
    ],
  );
  if (action == null || !context.mounted) {
    return;
  }

  switch (action) {
    case _CommunityDetailMenuAction.communityInfo:
      await _openCommunityInfo(context, controller, community);
    case _CommunityDetailMenuAction.delete:
      await _confirmAndDeleteCommunity(
        context,
        controller: controller,
        community: community,
      );
    case _CommunityDetailMenuAction.exit:
      await _confirmAndExitCommunity(
        context,
        controller: controller,
        community: community,
      );
  }
}

Future<void> _openCommunityInfo(
  BuildContext context,
  CommunitiesController controller,
  CommunityHub community,
) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (infoContext) => CommunityInfoScreen(
        controller: controller,
        communityId: community.id,
        onAddMembers: community.viewerIsAdmin
            ? () => _showInviteSheet(infoContext, controller, community)
            : null,
      ),
    ),
  );
}

Future<void> _confirmDetachGroup(
  BuildContext context, {
  required CommunitiesController controller,
  required CommunityHub community,
  required CommunityGroupPreview group,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return LiquidGlassDialog(
        title: Text('Remove ${group.name}?'),
        content: Text(
          '"${group.name}" will leave this community and keep going as a '
          'regular group chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          LiquidGlassDialogAction(
            key: const Key('confirm_detach_community_group_button'),
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

  final didDetach = await controller.detachGroupFromCommunity(
    communityId: community.id,
    groupId: group.id,
  );
  if (didDetach || !context.mounted) {
    return;
  }
  final message = controller.errorMessage;
  if (message != null) {
    await showErrorDialog(context, message);
    controller.clearError();
  }
}

Future<void> _showAddGroupSheet(
  BuildContext context,
  CommunitiesController controller,
  CommunityHub community,
) async {
  final groupName = await showGlassBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _AddGroupSheet(
          communityTitle: community.title,
        ),
      );
    },
  );
  if (groupName == null || groupName.isEmpty || !context.mounted) {
    return;
  }

  final didCreate = await controller.addGroupToCommunity(
    communityId: community.id,
    name: groupName,
  );
  if (!didCreate && context.mounted) {
    final message = controller.errorMessage ??
        'We could not add that group right now.';
    controller.clearError();
    await showErrorDialog(context, message);
  }
}

Future<void> _openThread(
  BuildContext context, {
  required ChatsController chatsController,
  required CallsController callsController,
  required UpdatesController updatesController,
  required CommunitiesController communitiesController,
  required String threadId,
}) async {
  chatsController.openThread(threadId);

  await Navigator.of(context).push<void>(
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

enum _CommunityDetailMenuAction { communityInfo, delete, exit }

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
          LiquidGlassDialogAction(
            key: const Key('community_detail_confirm_exit_button'),
            label: 'Exit',
            isDestructive: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
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
          LiquidGlassDialogAction(
            label: 'Deactivate',
            isDestructive: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
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
    this.onManage,
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
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onManage,
        onSecondaryTap: onManage,
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
              _membershipState(contact, community) ==
                  CommunityMembershipState.none;
        }).toList(growable: false);
        final invitedContacts = contacts.where((contact) {
          return contact.isOnWhatsWave &&
              _membershipState(contact, community) ==
                  CommunityMembershipState.invited;
        }).toList(growable: false);
        final memberContacts = contacts.where((contact) {
          return contact.isOnWhatsWave &&
              _membershipState(contact, community) ==
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
                  InfoFlatPanel(
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        key: const Key('community_detail_copy_invite_link'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        leading: Icon(
                          Icons.link_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: const Text('Invite link'),
                        subtitle: Text(
                          buildCommunityJoinLink(community),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(
                              text: buildCommunityJoinLink(community),
                            ),
                          );
                          if (context.mounted) {
                            await HapticFeedback.selectionClick();
                          }
                        },
                      ),
                    ),
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
                                  GlassPrimaryButton(
                                    actionKey: const Key(
                                      'community_detail_request_contacts_button',
                                    ),
                                    icon: Icons.contact_phone_rounded,
                                    label: controller.isRequestingContactsAccess
                                        ? 'Checking...'
                                        : 'Allow contacts',
                                    isLoading:
                                        controller.isRequestingContactsAccess,
                                    onPressed: controller
                                            .isRequestingContactsAccess
                                        ? null
                                        : () async {
                                            await controller
                                                .requestContactsAccess();
                                          },
                                  ),
                                  if (controller.contactAccessStatus ==
                                      ContactAccessStatus.denied)
                                    GlassPrimaryButton(
                                      actionKey: const Key(
                                        'community_detail_open_settings_button',
                                      ),
                                      label: 'Open settings',
                                      onPressed: () async {
                                        await controller.openContactSettings();
                                      },
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

  CommunityMembershipState _membershipState(
    CommunityContact contact,
    CommunityHub community,
  ) {
    if (contact.matchedUid != null &&
        community.memberUids.contains(contact.matchedUid)) {
      return CommunityMembershipState.member;
    }
    if (community.invitedContactIds.contains(contact.id) ||
        contact.pendingCommunityInviteIds.contains(community.id)) {
      return CommunityMembershipState.invited;
    }
    return contact.membershipStateFor(community.id);
  }

  _CommunityInviteListItem _buildInviteListItem({
    required CommunitiesController controller,
    required CommunityHub community,
    required CommunityContact contact,
  }) {
    final membershipState = _membershipState(contact, community);
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
      key: Key('community_detail_invite_contact_${contact.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: LiquidGlassSurface(
        blurred: false,
        showShadow: false,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        borderColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
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
              child: GlassCompactActionButton(
                actionKey: actionKey,
                label: label,
                onPressed: onPressed,
                muted: onPressed == null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Name entry for attaching a new group. Owns its [TextEditingController]
/// so the field is not disposed while the sheet route is still animating out.
class _AddGroupSheet extends StatefulWidget {
  const _AddGroupSheet({required this.communityTitle});

  final String communityTitle;

  @override
  State<_AddGroupSheet> createState() => _AddGroupSheetState();
}

class _AddGroupSheetState extends State<_AddGroupSheet> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add group',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'New groups in ${widget.communityTitle} start with every '
            'community member.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 14),
          GlassTextField(
            fieldKey: const Key('community_detail_add_group_name_field'),
            controller: _nameController,
            hintText: 'Group name',
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: GlassPrimaryButton(
              actionKey: const Key('community_detail_add_group_confirm_button'),
              label: 'Add',
              onPressed: _submit,
            ),
          ),
        ],
      ),
    );
  }
}
