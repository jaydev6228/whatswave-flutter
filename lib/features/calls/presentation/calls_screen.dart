import 'package:flutter/material.dart';

import '../../chats/application/chats_controller.dart';
import '../../chats/domain/chat_thread.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../../shared/widgets/swipe_action_background.dart';
import '../application/calls_controller.dart';
import '../domain/call_contact.dart';
import '../domain/call_history_entry.dart';
import 'call_flow.dart';

const double _kCallsScreenHorizontalPadding = 16;
const double _kCallsRowHorizontalPadding = 18;

class CallsScreen extends StatefulWidget {
  const CallsScreen({
    required this.controller,
    this.chatsController,
    super.key,
  });

  final CallsController controller;

  /// Optional -- when provided, the "Your contacts" section is derived from
  /// this controller's real, already-live-synced chat threads instead of
  /// [CallsController.favorites]'s repository-sourced (demo, in Fake mode)
  /// list. Mirrors CommunitiesScreen's chatsController pattern.
  final ChatsController? chatsController;

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.ensureLoaded();
    widget.chatsController?.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final chatsController = widget.chatsController;
    return AnimatedBuilder(
      animation: chatsController == null
          ? widget.controller
          : Listenable.merge([widget.controller, chatsController]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final contacts = chatsController == null
            ? widget.controller.favorites
            : _contactsFromThreads(chatsController.threads);

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
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Calls',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
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
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _kCallsScreenHorizontalPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _CallsSectionLabel(title: 'Your contacts'),
                            const SizedBox(height: 10),
                            if (contacts.isEmpty)
                              const EmptyStateCard(
                                dense: true,
                                margin: EdgeInsets.zero,
                                icon: Icons.favorite_border_rounded,
                                title: 'No contacts yet',
                                message:
                                    'People you message will appear here for one-tap calling.',
                              )
                            else
                              // Fixed-height horizontal list (a ListView
                              // needs a bounded cross axis from its
                              // ancestor) -- clamp text scale so the tile's
                              // name label can't push its Column past this
                              // budget, and keep real headroom above the
                              // clamped worst case rather than the exact
                              // minimum. See docs/ui_layout_guidelines.md
                              // rules 1 and 4 -- this exact box previously
                              // overflowed by a few px at a real device's
                              // font scale.
                              MediaQuery.withClampedTextScaling(
                                maxScaleFactor: 1.3,
                                child: SizedBox(
                                  height: 140,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemBuilder: (context, index) {
                                      final contact = contacts[index];
                                      return _FavoriteCallTile(
                                        contact: contact,
                                        onAudioPressed: () {
                                          startCallFlow(
                                            context,
                                            controller: widget.controller,
                                            contact: contact,
                                            type: CallType.audio,
                                          );
                                        },
                                        onVideoPressed: () {
                                          startCallFlow(
                                            context,
                                            controller: widget.controller,
                                            contact: contact,
                                            type: CallType.video,
                                          );
                                        },
                                      );
                                    },
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 12),
                                    itemCount: contacts.length,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                const Expanded(
                                  child: _CallsSectionLabel(
                                    title: 'Recent calls',
                                  ),
                                ),
                                if (widget.controller.history.isNotEmpty)
                                  TextButton(
                                    key: const Key(
                                      'calls_clear_history_button',
                                    ),
                                    onPressed:
                                        widget.controller.isClearingHistory
                                            ? null
                                            : _confirmClearHistory,
                                    child: Text(
                                      widget.controller.isClearingHistory
                                          ? 'Clearing...'
                                          : 'Clear',
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (widget.controller.history.isEmpty)
                              const EmptyStateCard(
                                dense: true,
                                margin: EdgeInsets.zero,
                                icon: Icons.call_missed_outgoing_outlined,
                                title: 'No recent calls',
                                message:
                                    'Start an audio or video call and it will appear here.',
                              ),
                          ],
                        ),
                      ),
                      if (widget.controller.history.isNotEmpty)
                        ...widget.controller.history.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Dismissible(
                              key: Key('call_swipe_${entry.id}'),
                              direction:
                                  widget.controller.isDeletingHistoryEntry(
                                entry.id,
                              )
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
                                    contact: CallContact(
                                      id: entry.contactId,
                                      name: entry.name,
                                      avatarLabel: entry.avatarLabel,
                                      accentColor: entry.accentColor,
                                      isGroup: entry.isGroup,
                                      uid: entry.uid,
                                    ),
                                    type: entry.type,
                                  );
                                },
                              ),
                            ),
                          );
                        }),
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

  Future<void> _confirmClearHistory() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clear recent calls?'),
          content: const Text(
            'This removes recent call history from this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (shouldClear == true) {
      await widget.controller.clearHistory();
    }
  }

  Future<bool> _confirmDeleteCall(CallHistoryEntry entry) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete this call?'),
          content: Text('This removes the call with ${entry.name} from your recent calls.'),
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

  /// Only threads with a real other-participant uid can actually be called
  /// (see ChatThread.participantUid) -- a demo/local thread has none and is
  /// filtered out rather than shown as a contact nothing can call for real.
  List<CallContact> _contactsFromThreads(List<ChatThread> threads) {
    return threads
        .where((thread) => thread.participantUid != null && !thread.isGroup)
        .map(
          (thread) => CallContact(
            id: thread.id,
            name: thread.name,
            avatarLabel: thread.avatarLabel,
            accentColor: thread.accentColor,
            uid: thread.participantUid,
          ),
        )
        .toList(growable: false);
  }
}

class _FavoriteCallTile extends StatelessWidget {
  const _FavoriteCallTile({
    required this.contact,
    required this.onAudioPressed,
    required this.onVideoPressed,
  });

  final CallContact contact;
  final VoidCallback onAudioPressed;
  final VoidCallback onVideoPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 94,
      child: Column(
        children: [
          AvatarBadge(
            label: contact.avatarLabel,
            color: contact.accentColor,
            size: 60,
          ),
          const SizedBox(height: 8),
          Text(
            contact.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FavoriteActionButton(
                buttonKey: Key('calls_favorite_audio_${contact.id}'),
                icon: Icons.call_rounded,
                onPressed: onAudioPressed,
              ),
              const SizedBox(width: 8),
              _FavoriteActionButton(
                buttonKey: Key('calls_favorite_video_${contact.id}'),
                icon: Icons.videocam_rounded,
                onPressed: onVideoPressed,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FavoriteActionButton extends StatelessWidget {
  const _FavoriteActionButton({
    required this.icon,
    required this.onPressed,
    this.buttonKey,
  });

  final Key? buttonKey;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: buttonKey,
      onTap: onPressed,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(
          icon,
          size: 18,
          color: theme.colorScheme.primary,
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
    final accentColor = entry.status.isAttentionWorthy
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('calls_recent_item_${entry.id}'),
        onTap: onPressed,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _kCallsRowHorizontalPadding,
                10,
                _kCallsRowHorizontalPadding,
                10,
              ),
              child: Row(
                children: [
                  AvatarBadge(
                    label: entry.avatarLabel,
                    color: entry.accentColor,
                    size: 52,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              entry.direction == CallDirection.outgoing
                                  ? Icons.north_east_rounded
                                  : Icons.south_west_rounded,
                              size: 15,
                              color: accentColor,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${entry.status.label} ${entry.type.label.toLowerCase()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: accentColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.durationSeconds > 0
                              ? '${_formatRelativeTime(entry.startedAt)} • ${_formatDuration(entry.durationSeconds)}'
                              : _formatRelativeTime(entry.startedAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.66),
                          ),
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
