import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../application/communities_controller.dart';
import '../domain/app_invite_link.dart';
import '../domain/community_contact.dart';
import '../domain/community_group_preview.dart';
import '../domain/community_hub.dart';
import '../domain/contact_access_status.dart';

class CommunityDetailScreen extends StatelessWidget {
  const CommunityDetailScreen({
    required this.controller,
    required this.communityId,
    super.key,
  });

  final CommunitiesController controller;
  final String communityId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
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

        return Scaffold(
          key: const Key('community_detail_screen'),
          appBar: AppBar(
            title: Text(community.title),
          ),
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CommunityHeroCard(community: community),
                        const SizedBox(height: 18),
                        FilledButton.tonalIcon(
                          key: const Key('community_detail_invite_button'),
                          onPressed: () async {
                            await showModalBottomSheet<void>(
                              context: context,
                              showDragHandle: true,
                              isScrollControlled: true,
                              builder: (_) {
                                return FractionallySizedBox(
                                  heightFactor: 0.82,
                                  child: _CommunityDetailInviteSheet(
                                    controller: controller,
                                    community: community,
                                  ),
                                );
                              },
                            );
                          },
                          icon: const Icon(Icons.group_add_outlined),
                          label: const Text('Invite people'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Announcement channel',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 12),
                        _AnnouncementCard(community: community),
                        const SizedBox(height: 24),
                        Text(
                          'Group previews',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 12),
                        _CommunityGroupPreviewPanel(groups: community.groups),
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

    _showErrorSnackBar();
  }

  Future<void> _shareAppInvite(CommunityContact contact) async {
    final didPrepareInvite = await widget.controller.shareAppInvite(contact.id);
    if (!mounted) {
      return;
    }
    if (!didPrepareInvite) {
      _showErrorSnackBar();
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
                    'Invite people',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Search contacts and send a community invite or app link for ${community.title}.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('community_detail_invite_search_field'),
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Search contacts, numbers, or notes',
                      suffixIcon: _searchController.text.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: _searchController.clear,
                              icon: const Icon(Icons.close_rounded),
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
                            subtitle: contacts.length == 1
                                ? '1 matching contact'
                                : '${contacts.length} matching contacts',
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
                              title: 'Ready to invite',
                              subtitle:
                                  'These contacts are already on WhatsWave and can join right away.',
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
                              title: 'Invite pending',
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
                              title: 'Already in this community',
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
                              title: 'Needs app invite first',
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
    final isBusy = controller.isContactBusy(contact.id) ||
        (contact.isOnWhatsWave && controller.isCommunityBusy(community.id));

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
          label = isBusy ? 'Inviting...' : 'Invite';
          onPressed = isBusy ? null : () => _inviteContact(contact);
        case CommunityMembershipState.invited:
          label = 'Invited';
          onPressed = null;
        case CommunityMembershipState.member:
          label = 'Member';
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
                      const SizedBox(height: 4),
                      Text(
                        contact.about,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.62),
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
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 140),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                      },
                      child: Text(
                        label,
                        key: ValueKey(label),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                      ),
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

class _CommunityHeroCard extends StatelessWidget {
  const _CommunityHeroCard({required this.community});

  final CommunityHub community;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _FlatCommunityPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarBadge(
            label: community.avatarLabel,
            color: community.accentColor,
            size: 64,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  community.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(community.description),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text('${community.memberCount} members'),
                    ),
                    Chip(
                      label: Text('${community.groupCount} groups'),
                    ),
                    if (community.invitedContactIds.isNotEmpty)
                      Chip(
                        label: Text(
                          '${community.invitedContactIds.length} invited',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.community});

  final CommunityHub community;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _FlatCommunityPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            community.announcement.headline,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(community.announcement.body),
          const SizedBox(height: 12),
          Text(
            _formatRelativeTime(community.announcement.publishedAt),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityGroupPreviewPanel extends StatelessWidget {
  const _CommunityGroupPreviewPanel({required this.groups});

  final List<CommunityGroupPreview> groups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _FlatCommunityPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: List<Widget>.generate(groups.length, (index) {
          final group = groups[index];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            group.summary,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (group.unreadCount > 0) ...[
                      const SizedBox(width: 12),
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: theme.colorScheme.primary,
                        child: Text(
                          '${group.unreadCount}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (index != groups.length - 1)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _FlatCommunityPanel extends StatelessWidget {
  const _FlatCommunityPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
        ),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

String _formatRelativeTime(DateTime timestamp) {
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final startOfTimestamp =
      DateTime(timestamp.year, timestamp.month, timestamp.day);
  final dayDifference = startOfToday.difference(startOfTimestamp).inDays;

  final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
  final meridiem = timestamp.hour >= 12 ? 'PM' : 'AM';
  final timeLabel =
      '$hour:${timestamp.minute.toString().padLeft(2, '0')} $meridiem';

  if (dayDifference == 0) {
    return 'Today, $timeLabel';
  }
  if (dayDifference == 1) {
    return 'Yesterday, $timeLabel';
  }
  return '${timestamp.month}/${timestamp.day}, $timeLabel';
}
