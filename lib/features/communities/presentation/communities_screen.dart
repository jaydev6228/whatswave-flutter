import 'package:flutter/material.dart';

import '../../calls/application/calls_controller.dart';
import '../../chats/application/chats_controller.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/create_action_row.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../../shared/widgets/glass_text_field.dart';
import '../../shared/widgets/liquid_glass.dart';
import '../../shared/widgets/search_field.dart';
import '../../updates/application/updates_controller.dart';
import '../application/communities_controller.dart';
import '../domain/community_hub.dart';
import 'community_detail_screen.dart';
import 'community_time_format.dart';
import 'community_unread.dart';

const double _kCommunitiesScreenHorizontalPadding = 16;
const double _kCommunitiesRowHorizontalPadding = 18;

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({
    required this.controller,
    required this.chatsController,
    required this.callsController,
    required this.updatesController,
    super.key,
  });

  final CommunitiesController controller;
  final ChatsController chatsController;
  final CallsController callsController;
  final UpdatesController updatesController;

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
      animation: Listenable.merge([
        widget.controller,
        widget.chatsController,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        if (!widget.controller.hasLoaded && widget.controller.isLoading) {
          return const SafeArea(
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final bottomSafeInset = MediaQuery.paddingOf(context).bottom;

        return SafeArea(
          bottom: false,
          child: CustomScrollView(
            key: const Key('communities_screen'),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(bottom: 100 + bottomSafeInset),
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
                            Text(
                              'Communities',
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
                                key: const Key('communities_error_card'),
                                dense: true,
                                margin: EdgeInsets.zero,
                                icon: Icons.error_outline_rounded,
                                title: 'Could not load communities',
                                message: widget.controller.errorMessage!,
                                onRetry: widget.controller.loadOverview,
                                retryKey: const Key('communities_retry_button'),
                              ),
                            ],
                            const SizedBox(height: 12),
                            SearchField(
                              fieldKey: const Key('communities_search_field'),
                              controller: _searchController,
                              hintText: 'Search communities',
                              onChanged: widget.controller.updateSearchQuery,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _CommunitiesPane(
                        controller: widget.controller,
                        chatsController: widget.chatsController,
                        onCreateCommunity: _showCreateCommunitySheet,
                        onOpenCommunity: _openCommunity,
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
          chatsController: widget.chatsController,
          callsController: widget.callsController,
          updatesController: widget.updatesController,
          communityId: community.id,
        ),
      ),
    );
  }

  Future<void> _showCreateCommunitySheet() async {
    await showGlassBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _CreateCommunitySheet(controller: widget.controller);
      },
    );
  }
}

class _CommunitiesPane extends StatelessWidget {
  const _CommunitiesPane({
    required this.controller,
    required this.chatsController,
    required this.onCreateCommunity,
    required this.onOpenCommunity,
  });

  final CommunitiesController controller;
  final ChatsController chatsController;
  final Future<void> Function() onCreateCommunity;
  final Future<void> Function(CommunityHub community) onOpenCommunity;

  @override
  Widget build(BuildContext context) {
    final visibleCommunities = controller.visibleCommunities;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // This row is a control, not the first item of the list below it,
        // and previously it was built exactly like a community row (filled
        // 48pt avatar, w800 title, a second grey line where the message
        // preview goes) so the eye read it as one. It now differs on every
        // axis the eye sorts by: a hairline glass "+" circle instead of a
        // filled community avatar, one primary-coloured label instead of
        // title-over-preview, and a full-bleed section break instead of the
        // avatar-indented divider that visually joined it to the list.
        CreateActionRow(
          rowKey: const Key('communities_create_button'),
          label: 'New community',
          onTap: onCreateCommunity,
        ),
        // Full-bleed (indent 0), unlike the avatar-indented dividers between
        // community rows -- an indented rule reads as "next item", a
        // full-width one as "end of section".
        Divider(
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
        const SizedBox(height: 4),
        if (visibleCommunities.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _kCommunitiesScreenHorizontalPadding,
              vertical: 18,
            ),
            child: EmptyStateCard(
              dense: true,
              margin: EdgeInsets.zero,
              icon: Icons.groups_outlined,
              title: controller.searchQuery.trim().isEmpty
                  ? 'No communities yet'
                  : 'No matching communities',
              message: controller.searchQuery.trim().isEmpty
                  ? 'Communities keep your announcement channel and related groups in one place.'
                  : 'Try a different search term.',
            ),
          ),
        if (visibleCommunities.isNotEmpty)
          ...visibleCommunities.map((community) {
            return _CommunityCard(
              community: community,
              unreadCount: CommunityUnread.totalForCommunity(
                chatsController,
                community,
              ),
              onTap: () => onOpenCommunity(community),
            );
          }),
      ],
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.community,
    required this.unreadCount,
    required this.onTap,
  });

  final CommunityHub community;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                    size: 52,
                    avatarUrl: community.avatarUrl,
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
                            Text(
                              formatCommunityTimestamp(
                                  community.lastActivityAt),
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
                                community.listPreview,
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
              indent: _kCommunitiesRowHorizontalPadding + 64,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
            ),
          ],
        ),
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
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              key: const Key('communities_create_sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New community',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Communities bring related groups together with an announcements channel only admins can post in.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.72),
                      ),
                ),
                const SizedBox(height: 18),
                // LiquidGlass*, not StatusChrome*: StatusChrome is fixed
                // dark with white glyphs because it floats over story media.
                // This sheet sits on the app's own surface, so it needs the
                // theme-aware family or it goes black-on-white in light mode.
                GlassTextField(
                  fieldKey: const Key('communities_create_name_field'),
                  controller: _nameController,
                  hintText: 'Community name',
                  textInputAction: TextInputAction.next,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                GlassTextField(
                  fieldKey: const Key('communities_create_description_field'),
                  controller: _descriptionController,
                  hintText: 'Description (optional)',
                  maxLines: 2,
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
                GlassPrimaryButton(
                  actionKey: const Key('communities_create_submit_button'),
                  label: 'Create community',
                  fullWidth: true,
                  isLoading: widget.controller.isCreatingCommunity,
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final didCreate = await widget.controller.createCommunity(
                      title: _nameController.text,
                      description: _descriptionController.text,
                    );
                    if (!mounted) {
                      return;
                    }
                    if (didCreate) {
                      navigator.pop();
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
