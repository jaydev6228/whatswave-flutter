import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/status_story.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../application/updates_controller.dart';
import 'media_status_composer_screen.dart';
import 'story_viewer_launcher.dart';
import 'text_status_composer_screen.dart';
import 'widgets/text_status_canvas.dart';
import 'widgets/status_ring_avatar.dart';

const double _kUpdatesScreenHorizontalPadding = 16;
const double _kUpdatesRowHorizontalPadding = 18;

class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({
    required this.controller,
    super.key,
  });

  final UpdatesController controller;

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    widget.controller.ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant UpdatesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    widget.controller.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final myStatus = widget.controller.myStatus;
        final recentStories = widget.controller.recentStories;
        final viewedStories = widget.controller.viewedStories;

        return SafeArea(
          child: RefreshIndicator(
            onRefresh: widget.controller.loadUpdates,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          _kUpdatesScreenHorizontalPadding,
                          8,
                          _kUpdatesScreenHorizontalPadding,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Updates',
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
                              _InlineUpdatesMessageCard(
                                message: widget.controller.errorMessage!,
                                onRetry: widget.controller.loadUpdates,
                              ),
                            ],
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                      _MyStatusCard(
                        story: myStatus,
                        onTap: myStatus != null && myStatus.hasSegments
                            ? () => _openStoryViewer(story: myStatus)
                            : null,
                        onManageTap: myStatus != null && myStatus.hasSegments
                            ? _openMyStatusManager
                            : null,
                        onTextTap: _openTextStatusComposer,
                        onMediaTap: _pickStatusMedia,
                        isBusy: widget.controller.isComposingStatus,
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
                if (widget.controller.isLoading && !widget.controller.hasLoaded)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(
                        key: Key('updates_loading_indicator'),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 24),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!widget.controller.hasContent)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: _kUpdatesScreenHorizontalPadding,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const EmptyStateCard(
                                    key: Key('updates_empty_state'),
                                    icon: Icons.auto_awesome_motion_outlined,
                                    title: 'No updates yet',
                                    message:
                                        'Once stories and channels are available, this screen will show recent and viewed updates here.',
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      key: const Key(
                                        'updates_empty_reload_button',
                                      ),
                                      onPressed: widget.controller.loadUpdates,
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('Reload updates'),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            _StorySection(
                              title: 'Recent updates',
                              stories: recentStories,
                              onStoryTap: (story) =>
                                  _openStoryViewer(story: story),
                            ),
                            if (recentStories.isNotEmpty &&
                                viewedStories.isNotEmpty)
                              const SizedBox(height: 18),
                            _StorySection(
                              title: 'Viewed updates',
                              stories: viewedStories,
                              onStoryTap: (story) =>
                                  _openStoryViewer(story: story),
                            ),
                            // Channels aren't implemented yet -- hidden
                            // entirely rather than showing an empty
                            // "Channels to explore" section with nothing
                            // real behind it.
                          ],
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

  Future<void> _openTextStatusComposer() async {
    final draft = await Navigator.of(context).push<TextStatusComposerDraft>(
      MaterialPageRoute<TextStatusComposerDraft>(
        builder: (_) => const TextStatusComposerScreen(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || draft == null) {
      return;
    }

    final didCreate = await widget.controller.createStatus(
      type: StatusStoryType.text,
      caption: draft.caption,
      textStyle: draft.textStyle,
    );
    if (!mounted || !didCreate) {
      return;
    }

    _showStatusSharedFeedback(StatusStoryType.text);
  }

  Future<void> _pickStatusMedia() async {
    if (widget.controller.isComposingStatus) {
      return;
    }

    try {
      final pickedMedia = await _imagePicker.pickMedia(
        requestFullMetadata: false,
      );
      if (!mounted || pickedMedia == null) {
        return;
      }

      final statusType = _statusTypeForPickedMedia(pickedMedia);
      if (statusType == null) {
        _showStatusError(
          'That media type is not supported for status updates yet.',
        );
        return;
      }

      final initialSourceSizeHint = await _resolveInitialStatusMediaSize(
        pickedMedia,
        statusType,
      );
      if (!mounted) {
        return;
      }

      final draft = await Navigator.of(context).push<MediaStatusComposerDraft>(
        MaterialPageRoute<MediaStatusComposerDraft>(
          builder: (_) => MediaStatusComposerScreen(
            type: statusType,
            localMediaPath: pickedMedia.path,
            initialSourceSizeHint: initialSourceSizeHint,
          ),
          fullscreenDialog: true,
        ),
      );
      if (!mounted || draft == null) {
        return;
      }

      final didCreate = await widget.controller.createStatus(
        type: statusType,
        caption: draft.caption,
        localMediaPath: pickedMedia.path,
        textStyle: draft.textStyle,
        mediaTransform: draft.mediaTransform,
        overlayItems: draft.overlayItems,
        emoji: draft.emoji,
        stickers: draft.stickers,
        musicTrack: draft.musicTrack,
        durationMillis: draft.durationMillis,
      );
      if (!mounted || !didCreate) {
        return;
      }

      _showStatusSharedFeedback(statusType);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showStatusError(
        'We could not open your gallery right now. Please try again.',
      );
    }
  }

  Future<Size?> _resolveInitialStatusMediaSize(
    XFile pickedMedia,
    StatusStoryType statusType,
  ) async {
    if (statusType != StatusStoryType.photo) {
      return null;
    }

    try {
      final bytes = await File(pickedMedia.path).readAsBytes();
      if (bytes.isEmpty) {
        return null;
      }

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  StatusStoryType? _statusTypeForPickedMedia(XFile media) {
    final normalizedMimeType = media.mimeType?.trim().toLowerCase();
    if (normalizedMimeType?.startsWith('image/') == true) {
      return StatusStoryType.photo;
    }
    if (normalizedMimeType?.startsWith('video/') == true) {
      return StatusStoryType.video;
    }

    final lowerPath = media.path.trim().toLowerCase();
    const photoExtensions = <String>[
      '.jpg',
      '.jpeg',
      '.png',
      '.heic',
      '.heif',
      '.gif',
      '.webp',
    ];
    for (final extension in photoExtensions) {
      if (lowerPath.endsWith(extension)) {
        return StatusStoryType.photo;
      }
    }

    const videoExtensions = <String>[
      '.mp4',
      '.mov',
      '.m4v',
      '.avi',
      '.mkv',
      '.webm',
      '.3gp',
    ];
    for (final extension in videoExtensions) {
      if (lowerPath.endsWith(extension)) {
        return StatusStoryType.video;
      }
    }

    return null;
  }

  void _showStatusSharedFeedback(StatusStoryType type) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            switch (type) {
              StatusStoryType.text => 'Text status shared to your updates.',
              StatusStoryType.photo => 'Photo shared to your updates.',
              StatusStoryType.video => 'Video shared to your updates.',
            },
          ),
        ),
      );
  }

  void _showStatusError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  Future<void> _openStoryViewer({required StatusStory story}) async {
    await openStatusStoryViewer(
      context,
      controller: widget.controller,
      story: story,
    );
  }

  Future<void> _openMyStatusManager() async {
    final status = widget.controller.myStatus;
    if (status == null || !status.hasSegments) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return _MyStatusManagerSheet(
          controller: widget.controller,
          onOpenSegment: (segmentIndex) async {
            Navigator.of(sheetContext).pop();
            final refreshedStatus = widget.controller.myStatus;
            if (!mounted ||
                refreshedStatus == null ||
                !refreshedStatus.hasSegments) {
              return;
            }
            await openStatusStoryViewer(
              context,
              controller: widget.controller,
              story: refreshedStatus,
              initialSegmentIndex: segmentIndex,
            );
          },
          onDeleteSegment: (segmentId) async {
            final didDelete = await widget.controller.deleteMyStatusSegment(
              segmentId,
            );
            if (!mounted) {
              return;
            }
            if (didDelete) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Status removed.')),
                );
              if (!(widget.controller.myStatus?.hasSegments ?? false) &&
                  sheetContext.mounted) {
                Navigator.of(sheetContext).pop();
              }
            } else if (widget.controller.errorMessage != null) {
              _showStatusError(widget.controller.errorMessage!);
            }
          },
          onClearAll: () async {
            final statusCount = widget.controller.myStatus?.totalSegments ?? 0;
            final shouldClear = await showDialog<bool>(
              context: context,
              builder: (dialogContext) {
                return AlertDialog(
                  title: const Text('Delete all statuses?'),
                  content: Text(
                    statusCount <= 1
                        ? 'This removes your last status update from My status.'
                        : 'This removes all $statusCount status updates from My status.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            Theme.of(dialogContext).colorScheme.error,
                        foregroundColor:
                            Theme.of(dialogContext).colorScheme.onError,
                      ),
                      child: const Text('Delete all'),
                    ),
                  ],
                );
              },
            );
            if (!mounted || shouldClear != true) {
              return;
            }

            final didClear = await widget.controller.clearMyStatuses();
            if (!mounted) {
              return;
            }
            if (didClear) {
              if (sheetContext.mounted) {
                Navigator.of(sheetContext).pop();
              }
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('All statuses deleted.')),
                );
            } else if (widget.controller.errorMessage != null) {
              _showStatusError(widget.controller.errorMessage!);
            }
          },
        );
      },
    );
  }
}

class _MyStatusCard extends StatelessWidget {
  const _MyStatusCard({
    required this.story,
    required this.onTap,
    required this.onManageTap,
    required this.onTextTap,
    required this.onMediaTap,
    required this.isBusy,
  });

  final StatusStory? story;
  final VoidCallback? onTap;
  final VoidCallback? onManageTap;
  final VoidCallback onTextTap;
  final VoidCallback onMediaTap;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = story;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('updates_my_status_card'),
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _kUpdatesRowHorizontalPadding,
                8,
                _kUpdatesRowHorizontalPadding,
                10,
              ),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (status != null && status.hasSegments)
                        StatusRingAvatar(
                          label: status.avatarLabel,
                          color: status.accentColor,
                          totalSegments: status.totalSegments,
                          seenSegments: status.seenSegments,
                          size: 66,
                        )
                      else
                        const AvatarBadge(
                          label: 'JD',
                          color: AppPalette.emerald,
                          size: 58,
                        ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Material(
                          color: theme.colorScheme.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            key: const Key('updates_my_status_media_button'),
                            customBorder: const CircleBorder(),
                            onTap: isBusy ? null : onMediaTap,
                            child: Container(
                              width: 28,
                              height: 28,
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
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.8,
                                          color: theme.colorScheme.onPrimary,
                                        ),
                                      )
                                    : Icon(
                                        Icons.add_rounded,
                                        size: 18,
                                        color: theme.colorScheme.onPrimary,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'My status',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _previewTextForStatus(status),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.72),
                            height: 1.28,
                          ),
                        ),
                        if (status != null && status.hasSegments) ...[
                          const SizedBox(height: 5),
                          Text(
                            status.relativeTimeLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onManageTap != null)
                        IconButton(
                          key: const Key('updates_my_status_manage_button'),
                          tooltip: 'Manage statuses',
                          visualDensity: VisualDensity.compact,
                          onPressed: isBusy ? null : onManageTap,
                          icon: const Icon(Icons.more_horiz_rounded),
                        ),
                      IconButton(
                        key: const Key('updates_my_status_text_button'),
                        tooltip: 'Write text status',
                        visualDensity: VisualDensity.compact,
                        onPressed: isBusy ? null : onTextTap,
                        icon: isBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              indent: _kUpdatesRowHorizontalPadding + 80,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
            ),
          ],
        ),
      ),
    );
  }

  static String _previewTextForStatus(StatusStory? status) {
    if (status == null || !status.hasSegments) {
      return 'Share a quick update';
    }

    final latestSegment = status.latestSegment;
    final latestType = latestSegment?.type ?? status.type;
    if (status.totalSegments > 1) {
      return '${status.totalSegments} updates';
    }

    return switch (latestType) {
      StatusStoryType.text => 'Text update',
      StatusStoryType.photo => 'Photo update',
      StatusStoryType.video => 'Video update',
    };
  }
}

class _MyStatusManagerSheet extends StatelessWidget {
  const _MyStatusManagerSheet({
    required this.controller,
    required this.onOpenSegment,
    required this.onDeleteSegment,
    required this.onClearAll,
  });

  final UpdatesController controller;
  final ValueChanged<int> onOpenSegment;
  final ValueChanged<String> onDeleteSegment;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final status = controller.myStatus;
        final segments = _segmentsForStatus(status);
        final height = MediaQuery.sizeOf(context).height * 0.72;

        return SizedBox(
          height: height.clamp(420.0, 640.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manage status',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (segments.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Open any status, review older uploads, or delete individual items.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.68),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (segments.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'No statuses left to manage.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.62),
                        ),
                      ),
                    ),
                  )
                else ...[
                  Expanded(
                    child: ListView.separated(
                      itemCount: segments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = segments[index];
                        return _MyStatusSegmentTile(
                          segment: item.segment,
                          segmentIndex: item.index,
                          isLatest: item.index == item.totalSegments - 1,
                          isBusy: controller.isComposingStatus,
                          onTap: () => onOpenSegment(item.index),
                          onDeleteTap: () => onDeleteSegment(item.segment.id),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('updates_my_status_clear_all_button'),
                      onPressed:
                          controller.isComposingStatus ? null : onClearAll,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text('Delete all (${segments.length})'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static List<_IndexedStatusSegment> _segmentsForStatus(StatusStory? status) {
    if (status == null || !status.hasSegments) {
      return const <_IndexedStatusSegment>[];
    }

    final rawSegments = status.segments.isNotEmpty
        ? status.segments
        : <StatusStorySegment>[
            StatusStorySegment(
              id: '${status.id}-legacy',
              type: status.type,
              previewText: status.previewText,
            ),
          ];

    final indexed = <_IndexedStatusSegment>[
      for (var index = rawSegments.length - 1; index >= 0; index--)
        _IndexedStatusSegment(
          index: index,
          totalSegments: rawSegments.length,
          segment: rawSegments[index],
        ),
    ];
    return indexed;
  }
}

class _IndexedStatusSegment {
  const _IndexedStatusSegment({
    required this.index,
    required this.totalSegments,
    required this.segment,
  });

  final int index;
  final int totalSegments;
  final StatusStorySegment segment;
}

class _MyStatusSegmentTile extends StatelessWidget {
  const _MyStatusSegmentTile({
    required this.segment,
    required this.segmentIndex,
    required this.isLatest,
    required this.isBusy,
    required this.onTap,
    required this.onDeleteTap,
  });

  final StatusStorySegment segment;
  final int segmentIndex;
  final bool isLatest;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onDeleteTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('updates_my_status_segment_$segmentIndex'),
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  _StatusSegmentPreview(segment: segment),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _titleForSegment(segment),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (isLatest)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Latest',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _subtitleForSegment(segment),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.72),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: Key('updates_delete_status_${segment.id}'),
                    tooltip: 'Delete status',
                    onPressed: isBusy ? null : onDeleteTap,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              indent: 76,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
            ),
          ],
        ),
      ),
    );
  }

  static String _titleForSegment(StatusStorySegment segment) {
    return switch (segment.type) {
      StatusStoryType.text => 'Text status',
      StatusStoryType.photo => 'Photo status',
      StatusStoryType.video => 'Video status',
    };
  }

  static String _subtitleForSegment(StatusStorySegment segment) {
    final previewText = segment.previewText.trim();
    if (previewText.isNotEmpty &&
        previewText.toLowerCase() != 'shared a new photo update' &&
        previewText.toLowerCase() != 'shared a new video update') {
      return previewText;
    }

    return switch (segment.type) {
      StatusStoryType.text => 'Tap to reopen this text update.',
      StatusStoryType.photo => 'Tap to view the uploaded photo.',
      StatusStoryType.video => 'Tap to view the uploaded video.',
    };
  }
}

class _StatusSegmentPreview extends StatelessWidget {
  const _StatusSegmentPreview({
    required this.segment,
  });

  final StatusStorySegment segment;

  @override
  Widget build(BuildContext context) {
    final mediaPath = segment.localMediaPath?.trim();
    final mediaFile =
        mediaPath == null || mediaPath.isEmpty ? null : File(mediaPath);
    if (segment.type == StatusStoryType.photo &&
        mediaFile != null &&
        mediaFile.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.file(
          mediaFile,
          width: 62,
          height: 74,
          fit: BoxFit.cover,
        ),
      );
    }

    if (segment.type == StatusStoryType.text) {
      return SizedBox(
        width: 62,
        height: 74,
        child: TextStatusCanvas(
          text: segment.previewText,
          style: segment.textStyle ?? const StatusTextStyle(),
          accentColor: AppPalette.emerald,
          borderRadius: BorderRadius.circular(18),
          showFrame: false,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        ),
      );
    }

    final theme = Theme.of(context);
    final icon = segment.type == StatusStoryType.video
        ? Icons.play_circle_outline_rounded
        : Icons.photo_library_outlined;
    final label = segment.type == StatusStoryType.video ? 'VIDEO' : 'PHOTO';
    return Container(
      width: 62,
      height: 74,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            AppPalette.deepOcean.withValues(alpha: 0.94),
            AppPalette.slate.withValues(alpha: 0.94),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StorySection extends StatelessWidget {
  const _StorySection({
    required this.title,
    required this.stories,
    required this.onStoryTap,
  });

  final String title;
  final List<StatusStory> stories;
  final ValueChanged<StatusStory> onStoryTap;

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _kUpdatesScreenHorizontalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _UpdatesSectionLabel(title: title),
              const SizedBox(height: 10),
            ],
          ),
        ),
        ...stories.map(
          (story) => _StatusStoryTile(
            story: story,
            onTap: () => onStoryTap(story),
          ),
        ),
      ],
    );
  }
}

class _StatusStoryTile extends StatelessWidget {
  const _StatusStoryTile({
    required this.story,
    required this.onTap,
  });

  final StatusStory story;
  final VoidCallback onTap;

  static String _subtitleForStory(StatusStory story) {
    final latestType = story.latestSegment?.type ?? story.type;
    if (story.totalSegments <= 1) {
      return switch (latestType) {
        StatusStoryType.text => 'Text update',
        StatusStoryType.photo => 'Photo update',
        StatusStoryType.video => 'Video update',
      };
    }

    final unseenCount = (story.totalSegments - story.clampedSeenSegments)
        .clamp(0, story.totalSegments);
    if (story.hasUnseenSegments && unseenCount > 0) {
      return unseenCount == story.totalSegments
          ? '${story.totalSegments} updates'
          : '$unseenCount new of ${story.totalSegments} updates';
    }
    return '${story.totalSegments} viewed updates';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unseenCount =
        (story.totalSegments - story.clampedSeenSegments).clamp(0, 99);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('updates_story_tile_${story.id}'),
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _kUpdatesRowHorizontalPadding,
                10,
                _kUpdatesRowHorizontalPadding,
                10,
              ),
              child: Row(
                children: [
                  StatusRingAvatar(
                    label: story.avatarLabel,
                    color: story.accentColor,
                    totalSegments: story.totalSegments,
                    seenSegments: story.seenSegments,
                    size: 58,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          story.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _subtitleForStory(story),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.72),
                            height: 1.28,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        story.relativeTimeLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.62),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      if (story.hasUnseenSegments)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: story.accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unseenCount > 0 ? '$unseenCount' : 'New',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: story.accentColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        )
                      else
                        Icon(
                          Icons.done_all_rounded,
                          size: 17,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.36),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              indent: _kUpdatesRowHorizontalPadding + 70,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineUpdatesMessageCard extends StatelessWidget {
  const _InlineUpdatesMessageCard({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const Key('updates_error_card'),
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
          const SizedBox(width: 8),
          TextButton(
            key: const Key('updates_retry_button'),
            onPressed: onRetry,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _UpdatesSectionLabel extends StatelessWidget {
  const _UpdatesSectionLabel({required this.title});

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
