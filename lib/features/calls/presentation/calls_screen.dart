import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';

import '../../communities/application/communities_controller.dart';
import '../../communities/domain/community_contact.dart';
import '../../communities/domain/contact_access_status.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/call_history_avatar.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/swipe_action_background.dart';
import '../application/calls_controller.dart';
import '../domain/call_contact.dart';
import '../domain/call_history_entry.dart';
import 'call_flow.dart';
import 'calls_contact_search.dart';

const double _kCallsScreenHorizontalPadding = 16;
const double _kCallsRowHorizontalPadding = 18;

class CallsScreen extends StatefulWidget {
  const CallsScreen({
    required this.controller,
    this.communitiesController,
    super.key,
  });

  final CallsController controller;

  /// When provided, the search field finds WhatsWave users from the device
  /// address book (matched via phoneDirectory), even if you've never chatted.
  final CommunitiesController? communitiesController;

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    widget.controller.ensureLoaded();
    widget.communitiesController?.ensureLoaded();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final communitiesController = widget.communitiesController;
    final listenables = <Listenable>[widget.controller];
    if (communitiesController != null) {
      listenables.add(communitiesController);
    }

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final theme = Theme.of(context);
        final searchQuery = _searchController.text.trim();
        final isSearching = searchQuery.isNotEmpty;
        final searchResults = communitiesController == null ||
                !communitiesController.contactAccessStatus.hasAnyAccess
            ? const <CommunityContact>[]
            : searchWhatsWaveContacts(
                communitiesController.contacts,
                searchQuery,
              );

        if (!widget.controller.hasLoaded && widget.controller.isLoading) {
          return const SafeArea(
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final bottomSafeInset = MediaQuery.paddingOf(context).bottom;

        return SafeArea(
          bottom: false,
          child: CustomScrollView(
            key: const Key('calls_screen'),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(bottom: 100 + bottomSafeInset),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          _kCallsScreenHorizontalPadding,
                          8,
                          _kCallsScreenHorizontalPadding,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Calls',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (widget.controller.errorMessage != null &&
                                !widget.controller.hasLoaded) ...[
                              const SizedBox(height: 10),
                              EmptyStateCard(
                                key: const Key('calls_error_card'),
                                dense: true,
                                margin: EdgeInsets.zero,
                                icon: Icons.error_outline_rounded,
                                title: 'Could not load calls',
                                message: widget.controller.errorMessage!,
                                onRetry: widget.controller.loadOverview,
                                retryKey: const Key('calls_retry_button'),
                              ),
                            ],
                            const SizedBox(height: 12),
                            SearchField(
                              fieldKey: const Key('calls_search_field'),
                              controller: _searchController,
                              hintText: 'Search name, number, or username',
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                      if (isSearching) ...[
                        const SizedBox(height: 8),
                        if (communitiesController == null)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: _kCallsScreenHorizontalPadding,
                            ),
                            child: EmptyStateCard(
                              dense: true,
                              margin: EdgeInsets.zero,
                              icon: Icons.person_search_outlined,
                              title: 'Contact search unavailable',
                              message:
                                  'Sign in with contacts access to find people on WhatsWave.',
                            ),
                          )
                        else if (!communitiesController
                            .contactAccessStatus.hasAnyAccess)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: _kCallsScreenHorizontalPadding,
                            ),
                            child: EmptyStateCard(
                              dense: true,
                              margin: EdgeInsets.zero,
                              icon: Icons.contact_phone_outlined,
                              title: 'Allow contact access',
                              message:
                                  'Grant contact access to search people on WhatsWave by name, number, or username.',
                              onRetry:
                                  communitiesController.requestContactsAccess,
                              retryKey: const Key('calls_request_contacts'),
                            ),
                          )
                        else if (searchResults.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: _kCallsScreenHorizontalPadding,
                            ),
                            child: EmptyStateCard(
                              dense: true,
                              margin: EdgeInsets.zero,
                              icon: Icons.person_search_outlined,
                              title: 'No matching contacts',
                              message:
                                  'Try another name, phone number, or WhatsWave username.',
                            ),
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.fromLTRB(
                                  _kCallsScreenHorizontalPadding,
                                  4,
                                  _kCallsScreenHorizontalPadding,
                                  0,
                                ),
                                child: _CallsSectionLabel(
                                  title: 'On WhatsWave',
                                ),
                              ),
                              ...searchResults.map(
                                (contact) => _SearchContactRow(
                                  contact: contact,
                                  isBusy: communitiesController
                                      .isContactBusy(contact.id),
                                  onCall: (type) => _startCallFromContact(
                                    contact,
                                    type,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                      if (!isSearching) ...[
                        if (widget.controller.history.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(
                              _kCallsScreenHorizontalPadding,
                              12,
                              _kCallsScreenHorizontalPadding,
                              0,
                            ),
                            child: EmptyStateCard(
                              dense: true,
                              margin: EdgeInsets.zero,
                              icon: Icons.call_missed_outgoing_outlined,
                              title: 'No recent calls',
                              message:
                                  'Start an audio or video call and it will appear here.',
                            ),
                          )
                        else ...[
                          const SizedBox(height: 16),
                          ...widget.controller.history.map((entry) {
                            return Dismissible(
                              key: Key('call_swipe_${entry.id}'),
                              direction: widget.controller
                                      .isDeletingHistoryEntry(entry.id)
                                  ? DismissDirection.none
                                  : DismissDirection.endToStart,
                              background: SwipeActionBackground(
                                alignment: Alignment.centerRight,
                                icon: Icons.delete_outline_rounded,
                                label: 'Delete',
                                color: theme.colorScheme.errorContainer,
                                foregroundColor:
                                    theme.colorScheme.onErrorContainer,
                              ),
                              confirmDismiss: (_) =>
                                  _confirmDeleteCall(entry),
                              onDismissed: (_) {
                                widget.controller.deleteHistoryEntry(
                                  entry.id,
                                );
                              },
                              child: _RecentCallCard(
                                entry: entry,
                                onPressed: () {
                                  startCallFlow(
                                    context,
                                    controller: widget.controller,
                                    contact: _contactForHistoryEntry(entry),
                                    type: entry.type,
                                  );
                                },
                              ),
                            );
                          }),
                        ],
                      ],
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

  /// Builds the [CallContact] for a recent-call entry. For a group entry the
  /// member uids/names/avatars are recovered from the entry's participant
  /// snapshot (minus the current user) so re-calling the group works -- an
  /// entry without any of the other participants would otherwise trip the
  /// calls controller's "no other members to call" guard.
  CallContact _contactForHistoryEntry(CallHistoryEntry entry) {
    if (!entry.isGroup) {
      return CallContact(
        id: entry.contactId,
        name: entry.name,
        avatarLabel: entry.avatarLabel,
        accentColor: entry.accentColor,
        uid: entry.uid,
        avatarUrl: entry.avatarUrl,
      );
    }

    final currentUid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    final participants = entry.participants ?? const [];
    final others = participants
        .where((p) => p.uid.isNotEmpty && p.uid != currentUid)
        .toList(growable: false);
    return CallContact(
      id: entry.contactId,
      name: entry.name,
      avatarLabel: entry.avatarLabel,
      accentColor: entry.accentColor,
      isGroup: true,
      uid: entry.uid,
      avatarUrl: entry.avatarUrl,
      memberUids: others.isEmpty
          ? null
          : others.map((p) => p.uid).toList(growable: false),
      memberDisplayNames: {for (final p in others) p.uid: p.name},
      memberAvatarUrls: {
        for (final p in others)
          if (p.avatarUrl != null) p.uid: p.avatarUrl!,
      },
    );
  }

  void _startCallFromContact(CommunityContact contact, CallType type) {
    startCallFlow(
      context,
      controller: widget.controller,
      contact: CallContact(
        id: contact.id,
        name: contact.name,
        avatarLabel: contact.avatarLabel,
        accentColor: contact.accentColor,
        uid: contact.matchedUid,
      ),
      type: type,
    );
  }

  Future<bool> _confirmDeleteCall(CallHistoryEntry entry) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete this call?'),
          content: Text(
            'This removes the call with ${entry.name} from your recent calls.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'Delete',
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                ),
              ),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
}

class _SearchContactRow extends StatelessWidget {
  const _SearchContactRow({
    required this.contact,
    required this.isBusy,
    required this.onCall,
  });

  final CommunityContact contact;
  final bool isBusy;
  final void Function(CallType type) onCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = contact.username == null || contact.username!.isEmpty
        ? contact.phoneNumber
        : '@${contact.username}';

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _kCallsRowHorizontalPadding,
          6,
          8,
          6,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    contact.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.66,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: Key('calls_search_audio_${contact.id}'),
              tooltip: 'Voice call',
              onPressed: isBusy ? null : () => onCall(CallType.audio),
              icon: const Icon(Icons.call_outlined),
            ),
            IconButton(
              key: Key('calls_search_video_${contact.id}'),
              tooltip: 'Video call',
              onPressed: isBusy ? null : () => onCall(CallType.video),
              icon: const Icon(Icons.videocam_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentCallCard extends StatelessWidget {
  const _RecentCallCard({
    required this.entry,
    required this.onPressed,
  });

  final CallHistoryEntry entry;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMissed = entry.logDisplayKind == CallLogDisplayKind.missed;
    final arrowColor = isMissed
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    final subtitle = entry.durationSeconds > 0
        ? '${_formatRelativeTime(entry.startedAt)} • ${_formatDuration(entry.durationSeconds)}'
        : _formatRelativeTime(entry.startedAt);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('calls_recent_item_${entry.id}'),
        onTap: onPressed,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _kCallsRowHorizontalPadding,
                vertical: 8,
              ),
              child: Row(
                children: [
                  CallHistoryAvatar(
                    entry: entry,
                    size: 52,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                entry.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: isMissed
                                      ? theme.colorScheme.error
                                      : null,
                                ),
                              ),
                            ),
                            if (entry.isGroup) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.group_rounded,
                                size: 15,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.46),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              entry.logDirectionIcon,
                              size: 15,
                              color: arrowColor,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.66),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    entry.type.icon,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              indent: _kCallsRowHorizontalPadding + 64,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallsSectionLabel extends StatelessWidget {
  const _CallsSectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
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

  const weekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  if (dayDifference < 7) {
    return '${weekdays[timestamp.weekday - 1]}, $timeLabel';
  }

  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[timestamp.month - 1]} ${timestamp.day}, $timeLabel';
}

String _formatDuration(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  if (minutes >= 60) {
    final hours = totalSeconds ~/ 3600;
    final remainingMinutes = (totalSeconds % 3600) ~/ 60;
    return '$hours:${remainingMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
