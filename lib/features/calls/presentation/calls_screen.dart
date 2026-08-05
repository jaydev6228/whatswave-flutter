import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chats/application/chats_controller.dart';
import '../../chats/domain/chat_thread.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/empty_state_card.dart';
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

        return SafeArea(
          child: CustomScrollView(
            key: const Key('calls_screen'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 24),
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
                            if (widget.controller.errorMessage != null) ...[
                              const SizedBox(height: 10),
                              _InlineCallsMessageCard(
                                key: const Key('calls_error_card'),
                                message: widget.controller.errorMessage!,
                                onRetry: !widget.controller.hasLoaded
                                    ? widget.controller.loadOverview
                                    : null,
                                onDismiss: widget.controller.clearError,
                              ),
                            ],
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                      _CallLinkCard(onPressed: _showCallLinkDialog),
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _kCallsScreenHorizontalPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _CallsSectionLabel(
                              title: 'Your contacts',
                              actionLabel: contacts.isEmpty
                                  ? null
                                  : '${contacts.length}',
                            ),
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
                                Expanded(
                                  child: _CallsSectionLabel(
                                    title: 'Recent calls',
                                    actionLabel: widget
                                            .controller.history.isEmpty
                                        ? null
                                        : '${widget.controller.history.length}',
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

  Future<void> _showCallLinkDialog() async {
    final link = _generateCallLink();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Create call link'),
          content: SelectableText(link),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (!mounted || !dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Call link copied to the clipboard.'),
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

  String _generateCallLink() {
    final code = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return 'https://join.whatswave.app/call/$code';
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

class _CallLinkCard extends StatelessWidget {
  const _CallLinkCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('calls_create_link_card'),
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
                  Icon(
                    Icons.link_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Create call link',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Share a quick join link for audio or video.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.72),
                          ),
                        ),
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
              indent: _kCallsRowHorizontalPadding + 36,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
            ),
          ],
        ),
      ),
    );
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
  const _CallsSectionLabel({
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

class _InlineCallsMessageCard extends StatelessWidget {
  const _InlineCallsMessageCard({
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
              key: const Key('calls_retry_button'),
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
