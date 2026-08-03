import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../calls/application/calls_controller.dart';
import '../../calls/domain/call_contact.dart';
import '../../calls/domain/call_history_entry.dart';
import '../../calls/presentation/call_experience_screen.dart';
import '../../chats/application/chats_controller.dart';
import '../../chats/presentation/conversation_screen.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../../updates/application/updates_controller.dart';
import '../application/communities_controller.dart';
import '../domain/app_invite_link.dart';
import '../domain/community_contact.dart';
import '../domain/community_hub.dart';
import '../domain/contact_access_status.dart';
import 'community_detail_screen.dart';

const double _kCommunitiesScreenHorizontalPadding = 16;
const double _kCommunitiesRowHorizontalPadding = 18;

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({
    required this.controller,
    this.callsController,
    this.chatsController,
    this.updatesController,
    super.key,
  });

  final CommunitiesController controller;

  /// When provided, "on WhatsWave" contacts (matched via phoneDirectory,
  /// see CommunityContact.matchedUid) get a real Call action. Null in
  /// contexts that don't wire Calls in (e.g. some tests).
  final CallsController? callsController;

  /// When provided (together with [updatesController]), "on WhatsWave"
  /// contacts also get a real Message action that starts/opens a chat
  /// thread with them.
  final ChatsController? chatsController;
  final UpdatesController? updatesController;

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController =
        TextEditingController(text: widget.controller.searchQuery);
    widget.controller.ensureLoaded();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        if (!widget.controller.hasLoaded && widget.controller.isLoading) {
          return const SafeArea(
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return SafeArea(
          child: CustomScrollView(
            key: const Key('communities_screen'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          _kCommunitiesScreenHorizontalPadding,
                          8,
                          _kCommunitiesScreenHorizontalPadding,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Communities',
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (widget.controller.errorMessage != null) ...[
                              const SizedBox(height: 10),
                              _InlineCommunitiesMessageCard(
                                key: const Key('communities_error_card'),
                                message: widget.controller.errorMessage!,
                                onRetry: !widget.controller.hasLoaded
                                    ? widget.controller.loadOverview
                                    : null,
                                onDismiss: widget.controller.clearError,
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextField(
                              key: const Key('communities_search_field'),
                              controller: _searchController,
                              onChanged: widget.controller.updateSearchQuery,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search_rounded),
                                isDense: true,
                                filled: true,
                                fillColor: theme
                                    .colorScheme.surfaceContainerHighest
                                    .withValues(
                                  alpha: theme.brightness == Brightness.dark
                                      ? 0.24
                                      : 0.56,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 9,
                                ),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 40,
                                  minHeight: 40,
                                ),
                                hintText: widget.controller.selectedSurface ==
                                        CommunitiesSurface.communities
                                    ? 'Search communities'
                                    : 'Search contacts',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.outlineVariant
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: 0.68),
                                  ),
                                ),
                                suffixIcon: _searchController.text
                                        .trim()
                                        .isEmpty
                                    ? null
                                    : IconButton(
                                        onPressed: () {
                                          _searchController.clear();
                                          widget.controller
                                              .updateSearchQuery('');
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 34,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _CompactCommunitiesChip(
                                      key: const Key(
                                        'communities_surface_communities',
                                      ),
                                      label: 'Communities',
                                      isSelected:
                                          widget.controller.selectedSurface ==
                                              CommunitiesSurface.communities,
                                      onTap: () {
                                        widget.controller.selectSurface(
                                          CommunitiesSurface.communities,
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    _CompactCommunitiesChip(
                                      key: const Key(
                                        'communities_surface_contacts',
                                      ),
                                      label: 'Contacts',
                                      isSelected:
                                          widget.controller.selectedSurface ==
                                              CommunitiesSurface.contacts,
                                      onTap: () {
                                        widget.controller.selectSurface(
                                          CommunitiesSurface.contacts,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (widget.controller.selectedSurface ==
                          CommunitiesSurface.communities)
                        _CommunitiesPane(
                          controller: widget.controller,
                          onCreateCommunity: _showCreateCommunitySheet,
                          onOpenCommunity: _openCommunity,
                        )
                      else
                        _ContactsPane(
                          controller: widget.controller,
                          onShareInvite: _shareInvite,
                          onSelectCommunityForContact:
                              _showCommunityPickerForContact,
                          onRequestContactsAccess:
                              widget.controller.requestContactsAccess,
                          onOpenContactSettings:
                              widget.controller.openContactSettings,
                          onCall: widget.callsController == null
                              ? null
                              : _callContact,
                          onMessage: widget.chatsController == null ||
                                  widget.updatesController == null
                              ? null
                              : _messageContact,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openCommunity(CommunityHub community) async {
    await widget.controller.openCommunity(community.id);
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CommunityDetailScreen(
          controller: widget.controller,
          communityId: community.id,
        ),
      ),
    );
  }

  Future<void> _showCreateCommunitySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _CreateCommunitySheet(controller: widget.controller);
      },
    );
  }

  Future<void> _messageContact(CommunityContact contact) async {
    final chatsController = widget.chatsController;
    final updatesController = widget.updatesController;
    final callsController = widget.callsController;
    final matchedUid = contact.matchedUid;
    if (chatsController == null ||
        updatesController == null ||
        callsController == null ||
        matchedUid == null) {
      return;
    }

    final threadId = await chatsController.startThreadWith(
      participantUid: matchedUid,
      participantName: contact.name,
      avatarLabel: contact.avatarLabel,
      accentColor: contact.accentColor,
    );
    if (threadId == null || !mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          callsController: callsController,
          controller: chatsController,
          updatesController: updatesController,
          threadId: threadId,
        ),
      ),
    );
  }

  Future<void> _callContact(CommunityContact contact, CallType type) async {
    final callsController = widget.callsController;
    final matchedUid = contact.matchedUid;
    if (callsController == null || matchedUid == null) {
      return;
    }

    final started = await callsController.startOutgoingCall(
      contact: CallContact(
        id: matchedUid,
        name: contact.name,
        avatarLabel: contact.avatarLabel,
        accentColor: contact.accentColor,
        photoAssetPath: null,
        uid: matchedUid,
      ),
      type: type,
    );
    if (!started || !mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallExperienceScreen(controller: callsController),
      ),
    );
  }

  Future<void> _shareInvite(CommunityContact contact) async {
    final inviteLink = buildCommunityAppInviteLink(contact);
    final didPrepareInvite = await widget.controller.shareAppInvite(contact.id);
    if (!mounted) {
      return;
    }
    if (!didPrepareInvite) {
      _showErrorSnackBar();
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Invite ${contact.name}'),
          content: SelectableText(inviteLink),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: inviteLink));
                if (!mounted || !dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Invite link copied for ${contact.name}.'),
                  ),
                );
              },
              child: const Text('Copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCommunityPickerForContact(CommunityContact contact) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return _CommunityInvitePickerSheet(
          controller: widget.controller,
          contact: contact,
        );
      },
    );
    if (mounted) {
      _showErrorSnackBar();
    }
  }

  void _showErrorSnackBar() {
    final message = widget.controller.errorMessage;
    if (message == null) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    widget.controller.clearError();
  }
}

class _CommunitiesPane extends StatelessWidget {
  const _CommunitiesPane({
    required this.controller,
    required this.onCreateCommunity,
    required this.onOpenCommunity,
  });

  final CommunitiesController controller;
  final Future<void> Function() onCreateCommunity;
  final Future<void> Function(CommunityHub community) onOpenCommunity;

  @override
  Widget build(BuildContext context) {
    final visibleCommunities = controller.visibleCommunities;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _kCommunitiesScreenHorizontalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.groups_2_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Create a community',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Keep announcements and related groups together.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.tonalIcon(
                      key: const Key('communities_create_button'),
                      onPressed: onCreateCommunity,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('New'),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                indent: 34,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
              ),
              const SizedBox(height: 14),
              _CommunitiesSectionLabel(
                title: 'Your communities',
                actionLabel: visibleCommunities.isEmpty
                    ? '0'
                    : '${visibleCommunities.length}',
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _CompactCommunitiesChip(
                        key: const Key('communities_filter_all'),
                        label: 'All',
                        isSelected: controller.communityFilter ==
                            CommunityListFilter.all,
                        onTap: () {
                          controller.selectCommunityFilter(
                            CommunityListFilter.all,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _CompactCommunitiesChip(
                        key: const Key('communities_filter_unread'),
                        label: 'Unread',
                        isSelected: controller.communityFilter ==
                            CommunityListFilter.unread,
                        onTap: () {
                          controller.selectCommunityFilter(
                            CommunityListFilter.unread,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _CompactCommunitiesChip(
                        key: const Key('communities_filter_announcements'),
                        label: 'Announcements',
                        isSelected: controller.communityFilter ==
                            CommunityListFilter.announcements,
                        onTap: () {
                          controller.selectCommunityFilter(
                            CommunityListFilter.announcements,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (visibleCommunities.isEmpty)
                EmptyStateCard(
                  dense: true,
                  margin: EdgeInsets.zero,
                  icon: Icons.groups_outlined,
                  title: controller.searchQuery.trim().isEmpty
                      ? 'No communities yet'
                      : 'No matching communities',
                  message: controller.searchQuery.trim().isEmpty
                      ? 'Create your first community to organize announcements and shared groups.'
                      : 'Try a different search or switch the community filter.',
                ),
            ],
          ),
        ),
        if (visibleCommunities.isNotEmpty)
          ...visibleCommunities.map((community) {
            return _CommunityCard(
              community: community,
              onTap: () => onOpenCommunity(community),
            );
          }),
      ],
    );
  }
}

class _ContactsPane extends StatelessWidget {
  const _ContactsPane({
    required this.controller,
    required this.onShareInvite,
    required this.onSelectCommunityForContact,
    required this.onRequestContactsAccess,
    required this.onOpenContactSettings,
    this.onCall,
    this.onMessage,
  });

  final CommunitiesController controller;
  final Future<void> Function(CommunityContact contact) onShareInvite;
  final Future<void> Function(CommunityContact contact)
      onSelectCommunityForContact;
  final Future<void> Function() onRequestContactsAccess;
  final Future<void> Function() onOpenContactSettings;
  final Future<void> Function(CommunityContact contact, CallType type)?
      onCall;
  final Future<void> Function(CommunityContact contact)? onMessage;

  @override
  Widget build(BuildContext context) {
    final visibleContacts = controller.visibleContacts;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _kCommunitiesScreenHorizontalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.contactAccessStatus ==
                              ContactAccessStatus.denied
                          ? 'Contacts access is off'
                          : 'Invite from contacts',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      controller.contactAccessStatus ==
                              ContactAccessStatus.granted
                          ? 'See who is already here and share invites with everyone else.'
                          : controller.contactAccessStatus ==
                                  ContactAccessStatus.denied
                              ? 'Turn contacts back on in system settings to invite people from your address book.'
                              : 'Allow contacts to see your address book matches.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                    if (controller.contactAccessStatus !=
                        ContactAccessStatus.granted) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            key: const Key('contacts_permission_allow'),
                            onPressed: controller.isRequestingContactsAccess
                                ? null
                                : onRequestContactsAccess,
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            icon: const Icon(
                              Icons.check_circle_outline_rounded,
                              size: 18,
                            ),
                            label: Text(
                              controller.isRequestingContactsAccess
                                  ? 'Checking...'
                                  : 'Allow contacts',
                            ),
                          ),
                          if (controller.contactAccessStatus ==
                              ContactAccessStatus.denied)
                            OutlinedButton(
                              key: const Key('contacts_permission_settings'),
                              onPressed: onOpenContactSettings,
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text('Open settings'),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
              ),
              const SizedBox(height: 14),
              _CommunitiesSectionLabel(
                title: 'Contacts',
                actionLabel: controller.contactAccessStatus ==
                        ContactAccessStatus.granted
                    ? '${visibleContacts.length}'
                    : null,
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _CompactCommunitiesChip(
                        key: const Key('contacts_filter_all'),
                        label: 'All',
                        isSelected:
                            controller.contactFilter == ContactListFilter.all,
                        onTap: () {
                          controller.selectContactFilter(ContactListFilter.all);
                        },
                      ),
                      const SizedBox(width: 8),
                      _CompactCommunitiesChip(
                        key: const Key('contacts_filter_on_app'),
                        label: 'On WhatsWave',
                        isSelected: controller.contactFilter ==
                            ContactListFilter.onWhatsWave,
                        onTap: () {
                          controller.selectContactFilter(
                            ContactListFilter.onWhatsWave,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _CompactCommunitiesChip(
                        key: const Key('contacts_filter_invite'),
                        label: 'Needs invite',
                        isSelected: controller.contactFilter ==
                            ContactListFilter.invite,
                        onTap: () {
                          controller.selectContactFilter(
                            ContactListFilter.invite,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (controller.contactAccessStatus != ContactAccessStatus.granted)
                const EmptyStateCard(
                  dense: true,
                  margin: EdgeInsets.zero,
                  icon: Icons.contact_phone_outlined,
                  title: 'Contacts are hidden for now',
                  message:
                      'Allow contact access to browse people already on WhatsWave and invite the rest.',
                )
              else if (visibleContacts.isEmpty)
                EmptyStateCard(
                  dense: true,
                  margin: EdgeInsets.zero,
                  icon: Icons.person_search_outlined,
                  title: controller.searchQuery.trim().isEmpty
                      ? 'No contacts match this filter'
                      : 'No matching contacts',
                  message: controller.searchQuery.trim().isEmpty
                      ? 'Switch filters or grant access again to refresh the contact discovery view.'
                      : 'Try a different search term or change the contact filter.',
                ),
            ],
          ),
        ),
        if (controller.contactAccessStatus == ContactAccessStatus.granted &&
            visibleContacts.isNotEmpty)
          ...visibleContacts.map((contact) {
            return _ContactCard(
              controller: controller,
              contact: contact,
              onShareInvite: () => onShareInvite(contact),
              onSelectCommunity: () => onSelectCommunityForContact(contact),
              onCall: onCall == null
                  ? null
                  : (type) => onCall!(contact, type),
              onMessage: onMessage == null
                  ? null
                  : () => onMessage!(contact),
            );
          }),
      ],
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.community,
    required this.onTap,
  });

  final CommunityHub community;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupSummary = community.groups.take(3).map((group) {
      return group.unreadCount > 0
          ? '${group.name} ${group.unreadCount}'
          : group.name;
    }).join('  •  ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('community_card_${community.id}'),
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _kCommunitiesRowHorizontalPadding,
                10,
                _kCommunitiesRowHorizontalPadding,
                10,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AvatarBadge(
                    label: community.avatarLabel,
                    color: community.accentColor,
                    size: 54,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                community.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (community.unreadCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${community.unreadCount}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${community.memberCount} members • ${community.groupCount} groups',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.64),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          community.announcement.headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          community.announcement.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.74),
                            height: 1.28,
                          ),
                        ),
                        if (groupSummary.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            groupSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              indent: _kCommunitiesRowHorizontalPadding + 66,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.controller,
    required this.contact,
    required this.onShareInvite,
    required this.onSelectCommunity,
    this.onCall,
    this.onMessage,
  });

  final CommunitiesController controller;
  final CommunityContact contact;
  final VoidCallback onShareInvite;
  final VoidCallback onSelectCommunity;
  final VoidCallback? onMessage;
  final Future<void> Function(CallType type)? onCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sharedCommunities = controller.sharedCommunityNames(contact);
    final isBusy = controller.isContactBusy(contact.id);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            _kCommunitiesRowHorizontalPadding,
            10,
            _kCommunitiesRowHorizontalPadding,
            10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AvatarBadge(
                label: contact.avatarLabel,
                color: contact.accentColor,
                size: 50,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            contact.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: contact.isOnWhatsWave
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            contact.isOnWhatsWave ? 'On WhatsWave' : 'Invite',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: contact.isOnWhatsWave
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      contact.phoneNumber,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.66),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      contact.about,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.74),
                      ),
                    ),
                    if (sharedCommunities.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        'In ${sharedCommunities.join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        contact.isOnWhatsWave
                          ? FilledButton.tonalIcon(
                              key: Key('contact_primary_action_${contact.id}'),
                              onPressed: isBusy ? null : onSelectCommunity,
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              icon: isBusy
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(
                                      Icons.group_add_outlined,
                                      size: 18,
                                    ),
                              label: const Text('Add to community'),
                            )
                          : FilledButton.tonalIcon(
                              key: Key('contact_primary_action_${contact.id}'),
                              onPressed: isBusy || contact.appInviteSent
                                  ? null
                                  : onShareInvite,
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              icon: const Icon(
                                Icons.send_to_mobile_rounded,
                                size: 18,
                              ),
                              label: Text(
                                contact.appInviteSent
                                    ? 'Invite sent'
                                    : 'Share app',
                              ),
                            ),
                        if (onMessage != null &&
                            contact.isOnWhatsWave &&
                            contact.matchedUid != null)
                          IconButton.filledTonal(
                            key: Key('contact_message_${contact.id}'),
                            tooltip: 'Message',
                            visualDensity: VisualDensity.compact,
                            onPressed: isBusy ? null : onMessage,
                            icon: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 18,
                            ),
                          ),
                        if (onCall != null &&
                            contact.isOnWhatsWave &&
                            contact.matchedUid != null) ...[
                          IconButton.filledTonal(
                            key: Key('contact_call_audio_${contact.id}'),
                            tooltip: 'Voice call',
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                isBusy ? null : () => onCall!(CallType.audio),
                            icon: const Icon(Icons.call_outlined, size: 18),
                          ),
                          IconButton.filledTonal(
                            key: Key('contact_call_video_${contact.id}'),
                            tooltip: 'Video call',
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                isBusy ? null : () => onCall!(CallType.video),
                            icon:
                                const Icon(Icons.videocam_outlined, size: 18),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          indent: _kCommunitiesRowHorizontalPadding + 62,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ],
    );
  }
}

class _CompactCommunitiesChip extends StatelessWidget {
  const _CompactCommunitiesChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.62)
                : colorScheme.outlineVariant.withValues(alpha: 0.26),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CommunitiesSectionLabel extends StatelessWidget {
  const _CommunitiesSectionLabel({
    required this.title,
    this.actionLabel,
  });

  final String title;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (actionLabel != null)
          Text(
            actionLabel!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
      ],
    );
  }
}

class _InlineCommunitiesMessageCard extends StatelessWidget {
  const _InlineCommunitiesMessageCard({
    required this.message,
    required this.onDismiss,
    this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onDismiss;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.34),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(
              key: const Key('communities_retry_button'),
              onPressed: onRetry,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              child: const Text('Retry'),
            ),
          ],
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _CreateCommunitySheet extends StatefulWidget {
  const _CreateCommunitySheet({required this.controller});

  final CommunitiesController controller;

  @override
  State<_CreateCommunitySheet> createState() => _CreateCommunitySheetState();
}

class _CreateCommunitySheetState extends State<_CreateCommunitySheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              key: const Key('communities_create_sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create community',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Start with an announcement space and one shared group, then invite people in.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                TextField(
                  key: const Key('communities_create_name_field'),
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Community name',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('communities_create_description_field'),
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                  ),
                ),
                if (widget.controller.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.controller.errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('communities_create_submit_button'),
                        onPressed: widget.controller.isCreatingCommunity
                            ? null
                            : () async {
                                final navigator = Navigator.of(context);
                                final messenger = ScaffoldMessenger.of(context);
                                final didCreate =
                                    await widget.controller.createCommunity(
                                  title: _nameController.text,
                                  description: _descriptionController.text,
                                );
                                if (!mounted) {
                                  return;
                                }
                                if (didCreate) {
                                  navigator.pop();
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Community created successfully.'),
                                    ),
                                  );
                                }
                              },
                        child: widget.controller.isCreatingCommunity
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Create'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CommunityInvitePickerSheet extends StatelessWidget {
  const _CommunityInvitePickerSheet({
    required this.controller,
    required this.contact,
  });

  final CommunitiesController controller;
  final CommunityContact contact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final communities = controller.communities;
        final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.82;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxSheetHeight),
              child: Column(
                key: const Key('community_invite_sheet'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add ${contact.name} to a community',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (communities.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: EmptyStateCard(
                              icon: Icons.groups_outlined,
                              title: 'Create a community first',
                              message:
                                  'Once you have a community, you can invite this contact into it here.',
                            ),
                          )
                        else
                          ...communities.map((community) {
                            final membershipState =
                                contact.membershipStateFor(community.id);
                            final isBusy =
                                controller.isContactBusy(contact.id) ||
                                    controller.isCommunityBusy(community.id);

                            Future<void> inviteContact() async {
                              final didInvite =
                                  await controller.inviteContactToCommunity(
                                communityId: community.id,
                                contactId: contact.id,
                              );
                              if (!context.mounted) {
                                return;
                              }
                              if (didInvite) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${contact.name} was invited to ${community.title}.',
                                    ),
                                  ),
                                );
                              }
                            }

                            return Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Card(
                                child: ListTile(
                                  key: Key(
                                    'community_invite_contact_${contact.id}_${community.id}',
                                  ),
                                  onTap: membershipState !=
                                              CommunityMembershipState.none ||
                                          isBusy
                                      ? null
                                      : inviteContact,
                                  contentPadding: const EdgeInsets.all(14),
                                  leading: AvatarBadge(
                                    label: community.avatarLabel,
                                    color: community.accentColor,
                                    size: 48,
                                  ),
                                  title: Text(community.title),
                                  subtitle: Text(
                                    '${community.memberCount} members • ${community.groupCount} groups',
                                  ),
                                  trailing: FilledButton.tonal(
                                    onPressed: membershipState !=
                                                CommunityMembershipState.none ||
                                            isBusy
                                        ? null
                                        : inviteContact,
                                    child: Text(
                                      isBusy ? '...' : membershipState.label,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
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
}
