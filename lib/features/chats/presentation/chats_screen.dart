import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/status_story.dart';
import '../../calls/application/calls_controller.dart';
import '../../communities/application/communities_controller.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../../shared/widgets/error_dialog.dart';
import '../../shared/widgets/liquid_glass.dart';
import '../../shared/widgets/swipe_action_background.dart';
import '../../updates/application/updates_controller.dart';
import '../../updates/presentation/status_compose_actions.dart';
import '../../updates/presentation/story_viewer_launcher.dart';
import '../../updates/presentation/widgets/status_ring_avatar.dart';
import '../application/chats_controller.dart';
import '../domain/chat_message.dart';
import '../domain/chat_thread.dart';
import 'conversation_screen.dart';

const double _kChatsScreenHorizontalPadding = 16;
const double _kChatsRowHorizontalPadding = 18;

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({
    required this.callsController,
    required this.communitiesController,
    required this.controller,
    required this.updatesController,
    this.animateTypingIndicators,
    super.key,
  });

  final CallsController callsController;
  final CommunitiesController communitiesController;
  final ChatsController controller;
  final UpdatesController updatesController;
  final bool? animateTypingIndicators;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final ScrollController _scrollController;
  late final ImagePicker _imagePicker;

  @override
  void initState() {
    super.initState();
    _searchController =
        TextEditingController(text: widget.controller.searchQuery);
    _searchFocusNode = FocusNode(debugLabel: 'chats_search_focus');
    _scrollController = ScrollController();
    _imagePicker = ImagePicker();
    widget.controller.ensureLoaded();
    widget.updatesController.ensureLoaded();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animateTypingIndicators = _resolveTypingIndicatorAnimation();
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.updatesController,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final visibleThreads = widget.controller.inboxThreads(
          query: widget.controller.searchQuery,
          filter: widget.controller.selectedFilter,
        );

        final bottomSafeInset = MediaQuery.paddingOf(context).bottom;

        return SafeArea(
          // Let the scroll view's background/overscroll paint under the
          // home indicator instead of stopping short of it; bottomSafeInset
          // is added back into the list's own bottom padding below so the
          // last item still clears the true screen edge by the same amount.
          bottom: false,
          child: NotificationListener<UserScrollNotification>(
            onNotification: (notification) {
              if (notification.direction != ScrollDirection.idle) {
                _dismissSearchFocus();
              }
              return false;
            },
            child: CustomScrollView(
              key: const PageStorageKey<String>('chats_scroll_view'),
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _kChatsScreenHorizontalPadding,
                      8,
                      _kChatsScreenHorizontalPadding,
                      6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Chats',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _StatusStrip(
                      controller: widget.updatesController,
                      imagePicker: _imagePicker,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _kChatsScreenHorizontalPadding,
                      6,
                      _kChatsScreenHorizontalPadding,
                      6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          key: const Key('chat_search_field'),
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          textInputAction: TextInputAction.search,
                          onTapOutside: (_) => _dismissSearchFocus(),
                          onChanged: widget.controller.updateSearchQuery,
                          decoration: InputDecoration(
                            hintText: 'Search',
                            isDense: true,
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest
                                .withValues(
                                    alpha: theme.brightness == Brightness.dark
                                        ? 0.24
                                        : 0.56),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            prefixIcon: const Icon(Icons.search_rounded),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
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
                            suffixIcon: _searchController.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _dismissSearchFocus();
                                      _searchController.clear();
                                      widget.controller.updateSearchQuery('');
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // No fixed height here (was SizedBox(height: 34)) --
                        // a text-containing chip row must size to its own
                        // content or its label clips at large text scale.
                        // A horizontal SingleChildScrollView already sizes
                        // its cross axis to the child's natural height on
                        // its own. See docs/ui_layout_guidelines.md rule 1.
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              LiquidGlassChip(
                                key: const Key('chat_filter_all'),
                                label: 'All',
                                isSelected: widget.controller.selectedFilter ==
                                    ChatListFilter.all,
                                onTap: () {
                                  _dismissSearchFocus();
                                  widget.controller
                                      .updateFilter(ChatListFilter.all);
                                },
                              ),
                              const SizedBox(width: 8),
                              LiquidGlassChip(
                                key: const Key('chat_filter_unread'),
                                label: 'Unread',
                                isSelected: widget.controller.selectedFilter ==
                                    ChatListFilter.unread,
                                onTap: () {
                                  _dismissSearchFocus();
                                  widget.controller
                                      .updateFilter(ChatListFilter.unread);
                                },
                              ),
                              const SizedBox(width: 8),
                              LiquidGlassChip(
                                key: const Key('chat_filter_groups'),
                                label: 'Groups',
                                isSelected: widget.controller.selectedFilter ==
                                    ChatListFilter.groups,
                                onTap: () {
                                  _dismissSearchFocus();
                                  widget.controller
                                      .updateFilter(ChatListFilter.groups);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        _ArchivedCard(
                          archivedCount: widget.controller.archivedCount,
                          onTap: _openArchivedChats,
                        ),
                        if (widget.controller.errorMessage != null &&
                            !widget.controller.hasLoaded) ...[
                          const SizedBox(height: 8),
                          EmptyStateCard(
                            dense: true,
                            margin: EdgeInsets.zero,
                            icon: Icons.error_outline_rounded,
                            title: 'Could not load chats',
                            message: widget.controller.errorMessage!,
                            onRetry: widget.controller.loadThreads,
                            retryLabel: 'Reload',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (widget.controller.isLoading && !widget.controller.hasLoaded)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (visibleThreads.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverToBoxAdapter(
                      child: EmptyStateCard(
                        icon: Icons.forum_outlined,
                        title: _emptyStateTitle(widget.controller),
                        message: _emptyStateMessage(widget.controller),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.only(bottom: 100 + bottomSafeInset),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final thread = visibleThreads[index];
                          return _ArchiveableChatListItem(
                            thread: thread,
                            story: widget.updatesController.storyForParticipant(
                              avatarLabel: thread.avatarLabel,
                              name: thread.name,
                            ),
                            animateTypingIndicators: animateTypingIndicators,
                            isBusy: widget.controller.isThreadBusy(thread.id),
                            isArchivedView: false,
                            showDivider: index != visibleThreads.length - 1,
                            onOpen: () => _openThread(thread),
                            onStoryTap: thread.hasStory
                                ? () => _openThreadStory(thread)
                                : null,
                            onArchiveToggle: () async {
                              _dismissSearchFocus();
                              return widget.controller.setThreadArchived(
                                threadId: thread.id,
                                isArchived: true,
                              );
                            },
                            onDelete: () async {
                              _dismissSearchFocus();
                              return widget.controller.deleteThread(thread.id);
                            },
                          );
                        },
                        childCount: visibleThreads.length,
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

  Future<void> _openThread(ChatThread thread) async {
    _dismissSearchFocus();
    await widget.controller.openThread(thread.id);
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          callsController: widget.callsController,
          controller: widget.controller,
          updatesController: widget.updatesController,
          threadId: thread.id,
        ),
      ),
    );

    _dismissSearchFocus();
  }

  Future<void> _openThreadStory(ChatThread thread) async {
    _dismissSearchFocus();
    await widget.updatesController.ensureLoaded();
    if (!mounted) {
      return;
    }

    final story = widget.updatesController.storyForParticipant(
      avatarLabel: thread.avatarLabel,
      name: thread.name,
    );
    if (story == null) {
      await _showComingSoon(
        context,
        'That status is no longer available.',
      );
      return;
    }

    await openStatusStoryViewer(
      context,
      controller: widget.updatesController,
      story: story,
    );
  }

  Future<void> _openArchivedChats() async {
    _dismissSearchFocus();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ArchivedChatsScreen(
          callsController: widget.callsController,
          controller: widget.controller,
          updatesController: widget.updatesController,
        ),
      ),
    );
  }

  void _dismissSearchFocus() {
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
    }
  }

  Future<void> _showComingSoon(BuildContext context, String message) {
    return showErrorDialog(context, message, title: 'Unavailable');
  }

  bool _resolveTypingIndicatorAnimation() {
    if (widget.animateTypingIndicators != null) {
      return widget.animateTypingIndicators!;
    }
    return !WidgetsBinding.instance.runtimeType
        .toString()
        .contains('TestWidgetsFlutterBinding');
  }

  String _emptyStateTitle(ChatsController controller) {
    if (controller.searchQuery.trim().isNotEmpty) {
      return 'No matching chats';
    }
    return switch (controller.selectedFilter) {
      ChatListFilter.all => 'No chats yet',
      ChatListFilter.unread => 'No unread chats',
      ChatListFilter.groups => 'No group chats',
    };
  }

  String _emptyStateMessage(ChatsController controller) {
    if (controller.searchQuery.trim().isNotEmpty) {
      return 'Try another name or message preview to find the thread you want.';
    }
    return switch (controller.selectedFilter) {
      ChatListFilter.all =>
        'When conversations start, this inbox will show recent threads, groups, and shared media.',
      ChatListFilter.unread =>
        'You are all caught up. New unread messages will appear in this filtered view.',
      ChatListFilter.groups =>
        'Groups will appear here once people or communities invite you in.',
    };
  }
}

class _ArchivedCard extends StatelessWidget {
  const _ArchivedCard({
    required this.archivedCount,
    required this.onTap,
  });

  final int archivedCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('chat_archived_row'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.archive_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text(
                'Archived',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (archivedCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$archivedCount',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ArchivedChatsScreen extends StatefulWidget {
  const ArchivedChatsScreen({
    required this.callsController,
    required this.controller,
    required this.updatesController,
    super.key,
  });

  final CallsController callsController;
  final ChatsController controller;
  final UpdatesController updatesController;

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.updatesController,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final archivedThreads = widget.controller.archivedThreads(
          query: _searchController.text,
        );
        final bottomSafeInset = MediaQuery.paddingOf(context).bottom;

        return Scaffold(
          key: const Key('archived_chats_screen'),
          appBar: AppBar(
            title: const Text(
              'Archived chats',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _kChatsScreenHorizontalPadding,
                      12,
                      _kChatsScreenHorizontalPadding,
                      12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          key: const Key('archived_chats_search_field'),
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search archived chats',
                            isDense: true,
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest
                                .withValues(
                              alpha: theme.brightness == Brightness.dark
                                  ? 0.24
                                  : 0.56,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            prefixIcon: const Icon(Icons.search_rounded),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
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
                            suffixIcon: _searchController.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (archivedThreads.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottomSafeInset),
                    sliver: SliverToBoxAdapter(
                      child: EmptyStateCard(
                        icon: Icons.archive_outlined,
                        title: _searchController.text.trim().isEmpty
                            ? 'No archived chats yet'
                            : 'No matches in archived chats',
                        message: _searchController.text.trim().isEmpty
                            ? 'Archive quieter conversations here to keep the main inbox focused.'
                            : 'Try another chat name or preview keyword.',
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.only(bottom: 24 + bottomSafeInset),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final thread = archivedThreads[index];
                          return _ArchiveableChatListItem(
                            thread: thread,
                            story: widget.updatesController.storyForParticipant(
                              avatarLabel: thread.avatarLabel,
                              name: thread.name,
                            ),
                            animateTypingIndicators: false,
                            isBusy: widget.controller.isThreadBusy(thread.id),
                            isArchivedView: true,
                            showDivider: index != archivedThreads.length - 1,
                            onOpen: () => _openArchivedThread(thread),
                            onStoryTap: thread.hasStory
                                ? () => _openArchivedThreadStory(thread)
                                : null,
                            onArchiveToggle: () {
                              return widget.controller.setThreadArchived(
                                threadId: thread.id,
                                isArchived: false,
                              );
                            },
                            onDelete: () {
                              return widget.controller.deleteThread(thread.id);
                            },
                          );
                        },
                        childCount: archivedThreads.length,
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

  Future<void> _openArchivedThread(ChatThread thread) async {
    await widget.controller.openThread(thread.id);
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          callsController: widget.callsController,
          controller: widget.controller,
          updatesController: widget.updatesController,
          threadId: thread.id,
        ),
      ),
    );
  }

  Future<void> _openArchivedThreadStory(ChatThread thread) async {
    await widget.updatesController.ensureLoaded();
    if (!mounted) {
      return;
    }

    final story = widget.updatesController.storyForParticipant(
      avatarLabel: thread.avatarLabel,
      name: thread.name,
    );
    if (story == null) {
      return;
    }

    await openStatusStoryViewer(
      context,
      controller: widget.updatesController,
      story: story,
    );
  }
}

class _ArchiveableChatListItem extends StatelessWidget {
  const _ArchiveableChatListItem({
    required this.thread,
    required this.story,
    required this.animateTypingIndicators,
    required this.isBusy,
    required this.isArchivedView,
    required this.showDivider,
    required this.onOpen,
    required this.onStoryTap,
    required this.onArchiveToggle,
    required this.onDelete,
  });

  final ChatThread thread;
  final StatusStory? story;
  final bool animateTypingIndicators;
  final bool isBusy;
  final bool isArchivedView;
  final bool showDivider;
  final VoidCallback onOpen;
  final VoidCallback? onStoryTap;
  final Future<bool> Function() onArchiveToggle;
  final Future<bool> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Archive/unarchive keeps its existing swipe direction per view; delete
    // takes over whichever direction was previously unused there.
    final deleteDirection = isArchivedView
        ? DismissDirection.endToStart
        : DismissDirection.startToEnd;

    return Column(
      children: [
        Dismissible(
          key: Key(
              'chat_swipe_${thread.id}_${isArchivedView ? 'archived' : 'inbox'}'),
          direction: isBusy
              ? DismissDirection.none
              : DismissDirection.horizontal,
          movementDuration: const Duration(milliseconds: 220),
          resizeDuration: const Duration(milliseconds: 180),
          background: isArchivedView
              ? const SwipeActionBackground(
                  alignment: Alignment.centerLeft,
                  icon: Icons.unarchive_rounded,
                  label: 'Move to inbox',
                )
              : SwipeActionBackground(
                  alignment: Alignment.centerLeft,
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  color: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                ),
          secondaryBackground: isArchivedView
              ? SwipeActionBackground(
                  alignment: Alignment.centerRight,
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  color: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                )
              : const SwipeActionBackground(
                  alignment: Alignment.centerRight,
                  icon: Icons.archive_outlined,
                  label: 'Archive',
                ),
          confirmDismiss: (direction) async {
            if (direction == deleteDirection) {
              final confirmed = await _confirmDelete(context);
              if (!confirmed) {
                return false;
              }
              return onDelete();
            }
            return onArchiveToggle();
          },
          child: _ChatTile(
            thread: thread,
            story: story,
            animateTypingIndicators: animateTypingIndicators,
            isBusy: isBusy,
            onOpen: onOpen,
            onStoryTap: onStoryTap,
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: _kChatsRowHorizontalPadding + 68,
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.22),
          ),
      ],
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete this chat?'),
          content: Text(
            'This removes "${thread.name}" from your chat list. '
            'It comes back if they message you again.',
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




class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.thread,
    required this.story,
    required this.animateTypingIndicators,
    required this.isBusy,
    required this.onOpen,
    required this.onStoryTap,
  });

  final ChatThread thread;
  final StatusStory? story;
  final bool animateTypingIndicators;
  final bool isBusy;
  final VoidCallback onOpen;
  final VoidCallback? onStoryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewStyle = theme.textTheme.bodyMedium?.copyWith(
      color: thread.isTyping
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurface.withValues(alpha: 0.72),
      fontWeight: thread.isTyping ? FontWeight.w700 : FontWeight.w500,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('chat_tile_${thread.id}'),
        onTap: isBusy ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            _kChatsRowHorizontalPadding,
            10,
            _kChatsRowHorizontalPadding,
            10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ChatAvatar(
                thread: thread,
                story: story,
                size: 56,
                onTap: onStoryTap,
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
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  key: Key('chat_title_${thread.id}'),
                                  thread.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              if (thread.isGroup) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.group_rounded,
                                  size: 15,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.46),
                                ),
                              ],
                              if (thread.isMuted) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.volume_off_rounded,
                                  size: 15,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.42),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (thread.isTyping)
                      _TypingStatusLine(
                        threadId: thread.id,
                        label: thread.typingParticipantLabel,
                        color: theme.colorScheme.primary,
                        animate: animateTypingIndicators,
                        style: previewStyle?.copyWith(height: 1.12),
                      )
                    else
                      Row(
                        children: [
                          if (thread.listDeliveryState != null) ...[
                            _DeliveryIcon(state: thread.listDeliveryState!),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              key: Key('chat_preview_${thread.id}'),
                              thread.listPreview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: previewStyle?.copyWith(height: 1.16),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _threadTimeLabel(thread.latestActivityAt),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: thread.unreadCount > 0
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.52),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (thread.isPinned)
                        Padding(
                          padding: EdgeInsets.only(
                            right: thread.unreadCount > 0 ? 6 : 0,
                          ),
                          child: Icon(
                            Icons.push_pin_rounded,
                            size: 14,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.42),
                          ),
                        ),
                      if (thread.unreadCount > 0)
                        _UnreadBadge(count: thread.unreadCount),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({
    required this.thread,
    required this.story,
    required this.size,
    this.onTap,
  });

  final ChatThread thread;
  final StatusStory? story;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = thread.hasStory
        ? StatusRingAvatar(
            key: ValueKey<String>('chat_story_ring_${thread.id}'),
            label: thread.avatarLabel,
            color: thread.accentColor,
            totalSegments: story?.totalSegments ?? 1,
            seenSegments: story?.clampedSeenSegments ?? 0,
            size: size,
          )
        : AvatarBadge(
            label: thread.avatarLabel,
            color: thread.accentColor,
            size: size,
          );

    if (!thread.hasStory || onTap == null) {
      return avatar;
    }

    return GestureDetector(
      key: ValueKey<String>('chat_story_avatar_${thread.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: avatar,
    );
  }
}

class _TypingStatusLine extends StatelessWidget {
  const _TypingStatusLine({
    required this.threadId,
    required this.label,
    required this.color,
    required this.animate,
    this.style,
  });

  final String threadId;
  final String label;
  final Color color;
  final bool animate;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final effectiveLabel = label.trim().isEmpty ? 'Typing' : label.trim();
    return Semantics(
      label: '$effectiveLabel is typing',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Flexible(
              child: Text(
                effectiveLabel,
                key: Key('chat_typing_name_$threadId'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            const SizedBox(width: 6),
            _TypingDotsIndicator(
              key: Key('chat_typing_indicator_$threadId'),
              threadId: threadId,
              color: color,
              animate: animate,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingDotsIndicator extends StatefulWidget {
  const _TypingDotsIndicator({
    required this.threadId,
    required this.color,
    required this.animate,
    super.key,
  });

  final String threadId;
  final Color color;
  final bool animate;

  @override
  State<_TypingDotsIndicator> createState() => _TypingDotsIndicatorState();
}

class _TypingDotsIndicatorState extends State<_TypingDotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller.value = 0.32;
    }
  }

  @override
  void didUpdateWidget(covariant _TypingDotsIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate == widget.animate) {
      return;
    }
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0.32;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _opacityForDot(int index) {
    final progress = (_controller.value + (index * 0.18)) % 1.0;
    final triangle = 1.0 - ((progress * 2) - 1).abs();
    return 0.24 + (triangle * 0.76);
  }

  double _scaleForDot(int index) {
    final progress = (_controller.value + (index * 0.18)) % 1.0;
    final triangle = 1.0 - ((progress * 2) - 1).abs();
    return 0.82 + (triangle * 0.24);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (index) {
            return Padding(
              padding: EdgeInsets.only(right: index == 2 ? 0 : 4),
              child: Transform.scale(
                scale: _scaleForDot(index),
                child: Opacity(
                  key: Key('chat_typing_dot_${widget.threadId}_$index'),
                  opacity: _opacityForDot(index),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _DeliveryIcon extends StatelessWidget {
  const _DeliveryIcon({required this.state});

  final MessageDeliveryState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (state) {
      MessageDeliveryState.sending => Icons.schedule_rounded,
      MessageDeliveryState.sent => Icons.check_rounded,
      MessageDeliveryState.delivered => Icons.done_all_rounded,
      MessageDeliveryState.read => Icons.done_all_rounded,
      MessageDeliveryState.failed => Icons.error_outline_rounded,
    };
    final color = state == MessageDeliveryState.read
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.45);

    return Icon(icon, size: 16, color: color);
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _threadTimeLabel(DateTime? date) {
  if (date == null) {
    return '';
  }

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final dayDifference = today.difference(target).inDays;

  if (dayDifference == 0) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  if (dayDifference == 1) {
    return 'Yesterday';
  }

  const weekdayLabels = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  if (dayDifference < 7) {
    return weekdayLabels[date.weekday - 1];
  }

  const monthLabels = <String>[
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
  return '${monthLabels[date.month - 1]} ${date.day}';
}

/// Status now lives here instead of its own bottom-nav tab -- the ring
/// color already told you seen-vs-unseen everywhere else in the app, so a
/// separate Recent/Viewed screen was showing the same thing twice. Tapping
/// a story opens the full-screen viewer (StoryViewerLauncher); tapping the
/// "+" on your own circle opens the same compose flow UpdatesScreen offers.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.controller,
    required this.imagePicker,
  });

  final UpdatesController controller;
  final ImagePicker imagePicker;

  @override
  Widget build(BuildContext context) {
    final myStatus = controller.myStatus;
    final hasMyStatus = myStatus != null && myStatus.hasSegments;
    final otherStories = controller.stories
        .where((story) => !story.isMine && story.hasSegments)
        .toList(growable: false);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: _kChatsScreenHorizontalPadding,
      ),
      child: Row(
        children: [
          _MyStatusStripItem(
            status: hasMyStatus ? myStatus : null,
            isBusy: controller.isComposingStatus,
            onView: hasMyStatus
                ? () => openStatusStoryViewer(
                      context,
                      controller: controller,
                      story: myStatus,
                    )
                : null,
            onAdd: () => showStatusComposeChoice(context, controller, imagePicker),
          ),
          for (final story in otherStories) ...[
            const SizedBox(width: 14),
            _StatusStripItem(
              story: story,
              onTap: () => openStatusStoryViewer(
                context,
                controller: controller,
                story: story,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MyStatusStripItem extends StatelessWidget {
  const _MyStatusStripItem({
    required this.status,
    required this.isBusy,
    required this.onView,
    required this.onAdd,
  });

  final StatusStory? status;
  final bool isBusy;
  final VoidCallback? onView;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          key: const Key('chats_status_mine'),
          onTap: onView ?? onAdd,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (status != null)
                StatusRingAvatar(
                  label: status!.avatarLabel,
                  color: status!.accentColor,
                  totalSegments: status!.totalSegments,
                  seenSegments: status!.seenSegments,
                  size: 56,
                )
              else
                const AvatarBadge(
                  label: 'JD',
                  color: AppPalette.emerald,
                  size: 56,
                ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Material(
                  color: theme.colorScheme.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const Key('chats_status_add_button'),
                    customBorder: const CircleBorder(),
                    onTap: isBusy ? null : onAdd,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: isBusy
                            ? SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              )
                            : Icon(
                                Icons.add_rounded,
                                size: 13,
                                color: theme.colorScheme.onPrimary,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 68,
          child: Text(
            'My status',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusStripItem extends StatelessWidget {
  const _StatusStripItem({
    required this.story,
    required this.onTap,
  });

  final StatusStory story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      key: Key('chats_status_${story.id}'),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusRingAvatar(
            label: story.avatarLabel,
            color: story.accentColor,
            totalSegments: story.totalSegments,
            seenSegments: story.seenSegments,
            size: 56,
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 62,
            child: Text(
              story.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
