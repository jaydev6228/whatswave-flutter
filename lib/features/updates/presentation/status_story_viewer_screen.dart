import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/status_story.dart';
import '../../../core/models/story_viewer.dart';
import '../../chats/application/chats_controller.dart';
import '../../chats/domain/story_reply_context.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/error_dialog.dart';
import 'widgets/status_media_decoration_overlay.dart';
import 'widgets/status_media_source.dart';
import 'widgets/status_story_media_surface.dart';
import 'widgets/text_status_canvas.dart';
import 'widgets/status_ring_avatar.dart';

class StatusStoryDeleteResult {
  const StatusStoryDeleteResult({
    required this.didDelete,
    this.updatedStory,
    this.errorMessage,
  });

  final bool didDelete;
  final StatusStory? updatedStory;
  final String? errorMessage;
}

class StatusStoryViewerScreen extends StatefulWidget {
  const StatusStoryViewerScreen({
    required this.story,
    required this.onStoryViewed,
    this.segmentDurationOverride,
    this.initialSegmentIndex,
    this.onDeleteSegment,
    this.chatsController,
    this.onFetchViewers,
    this.onWatchViewers,
    this.onFetchLikedByMe,
    this.onSetStoryLiked,
    super.key,
  });

  final StatusStory story;
  final ValueChanged<StatusStory> onStoryViewed;
  final Duration? segmentDurationOverride;
  final int? initialSegmentIndex;
  final Future<StatusStoryDeleteResult> Function(
    StatusStory story,
    StatusStorySegment segment,
  )? onDeleteSegment;

  /// Lets the viewer type a reply to someone else's story -- sent as a
  /// real direct message to them, the same as WhatsApp's own status
  /// reply. Null (the default) hides the reply bar entirely -- only call
  /// sites with a ChatsController in scope pass one; viewing your own
  /// story never shows a reply bar regardless.
  final ChatsController? chatsController;

  /// Fetches who has viewed this story -- only ever passed for a story you
  /// own (see story_viewer_launcher.dart), which is also when the "N
  /// views" label becomes tappable. Null hides that affordance entirely.
  final Future<List<StoryViewer>> Function(StatusStory story)? onFetchViewers;

  /// Live viewer updates for your own story -- likes and new views appear
  /// without closing and reopening. Null falls back to [onFetchViewers].
  final Stream<List<StoryViewer>>? Function()? onWatchViewers;

  /// Loads whether you've already hearted this story (someone else's only).
  final Future<bool> Function(StatusStory story)? onFetchLikedByMe;

  /// Sets or clears your heart quick-react on someone else's story.
  final Future<bool> Function(StatusStory story, bool liked)? onSetStoryLiked;

  @override
  State<StatusStoryViewerScreen> createState() =>
      _StatusStoryViewerScreenState();
}

enum _StoryTapDirection { left, right }

class _StatusStoryViewerScreenState extends State<StatusStoryViewerScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _tapNavigationThreshold = Duration(milliseconds: 170);

  late final AnimationController _segmentProgressController;
  late int _currentSegmentIndex;
  late int _reportedSeenSegments;
  bool _isClosing = false;
  bool _isTransitioning = false;
  bool _isPausedByHold = false;
  int? _activePointer;
  DateTime? _activePointerDownAt;
  _StoryTapDirection? _pendingTapDirection;
  VideoPlayerController? _videoController;
  Future<void>? _videoInitialization;
  String? _activeVideoPath;
  VideoPlayerController? _musicController;
  String? _activeMusicAssetPath;
  bool _isDeletingSegment = false;
  bool _isMuted = false;
  late StatusStory _storyData;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  bool _isSendingReply = false;

  /// Whether you've hearted this story -- loaded from Firestore on open
  /// and toggled optimistically on tap (see [_toggleHeart]).
  bool _hasHearted = false;
  bool _isTogglingHeart = false;
  StreamSubscription<List<StoryViewer>>? _viewersSubscription;

  /// Loaded once for your own story so each segment can show its own view
  /// count (WhatsApp counts views per status item, not for the whole ring).
  List<StoryViewer>? _cachedViewers;

  StatusStory get _story => _storyData;
  int get _segmentCount => math.max(_story.totalSegments, 1);
  StatusStorySegment? get _currentSegment =>
      _story.segmentAt(_currentSegmentIndex);
  StatusStoryType get _currentSegmentType =>
      _currentSegment?.type ?? _story.type;
  double get _segmentProgress => _segmentProgressController.value;

  bool get _currentSegmentHasMusic =>
      _currentSegment?.musicTrack?.previewAssetPath?.trim().isNotEmpty == true;

  /// Whether the current segment has anything audible to mute -- either its
  /// own video audio track, or an overlaid music track (never both: a video
  /// with music has its own audio silenced in favor of the music, matching
  /// _configureVideoPlayback's existing volume logic below).
  bool get _hasAudibleAudio =>
      _currentSegmentHasMusic ||
      (_currentSegmentType == StatusStoryType.video &&
          _currentSegment?.hasLocalMedia == true);

  String get _currentSegmentTimeLabel {
    final segment = _currentSegment;
    if (segment?.postedAt != null) {
      return segment!.relativeTimeLabel;
    }
    return _story.relativeTimeLabel;
  }

  int get _currentSegmentViewerCount {
    final requiredSeen = _currentSegmentIndex + 1;
    final cachedViewers = _cachedViewers;
    if (cachedViewers != null) {
      return cachedViewers
          .where((viewer) => viewer.seenSegments >= requiredSeen)
          .length;
    }
    // Before the viewer list resolves, only trust the preloaded count on
    // the latest segment -- older items start at 0 until we know better.
    if (_currentSegmentIndex >= _story.totalSegments - 1) {
      return _story.viewerCount;
    }
    return 0;
  }

  List<StoryViewer> _viewersForSegment(int segmentIndex) {
    final requiredSeen = segmentIndex + 1;
    final cachedViewers = _cachedViewers;
    if (cachedViewers == null) {
      return const <StoryViewer>[];
    }
    return cachedViewers
        .where((viewer) => viewer.seenSegments >= requiredSeen)
        .toList(growable: false);
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    final hasMusic = _currentSegmentHasMusic;
    if (!hasMusic &&
        _videoController != null &&
        _videoController!.value.isInitialized) {
      unawaited(_videoController!.setVolume(_isMuted ? 0 : 1));
    }
    if (_musicController != null && _musicController!.value.isInitialized) {
      unawaited(_musicController!.setVolume(_isMuted ? 0 : 1));
    }
  }

  @override
  void initState() {
    super.initState();
    _storyData = widget.story;
    _currentSegmentIndex = _initialSegmentIndexFor(
      _story,
      initialSegmentIndex: widget.initialSegmentIndex,
    );
    _reportedSeenSegments = _story.clampedSeenSegments;
    _segmentProgressController = AnimationController(
      vsync: this,
      duration: _segmentDurationFor(
        type: _currentSegmentType,
        segment: _currentSegment,
      ),
    )
      ..addListener(_handleProgressTick)
      ..addStatusListener(_handleProgressStatusChange);
    _startCurrentSegmentPlayback();
    // Typing a reply should pause the story the same way a long-press hold
    // does -- otherwise the segment advances (or the story closes) out from
    // under someone mid-reply.
    _replyFocusNode.addListener(() {
      if (_replyFocusNode.hasFocus) {
        _pausePlaybackForHold();
      } else {
        _resumePlaybackFromHold();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _reportCurrentSegmentViewed();
    });

    if (_story.isMine) {
      final watchViewers = widget.onWatchViewers?.call();
      if (watchViewers != null) {
        _viewersSubscription = watchViewers.listen(
          (viewers) {
            if (!mounted) {
              return;
            }
            setState(() => _cachedViewers = viewers);
          },
          onError: (_) {
            // Fall back to the one-shot fetch below.
          },
        );
      } else if (widget.onFetchViewers != null) {
        unawaited(_loadViewers());
      }
    } else if (widget.onFetchLikedByMe != null) {
      unawaited(_loadLikedByMe());
    }
  }

  Future<void> _loadLikedByMe() async {
    final onFetchLikedByMe = widget.onFetchLikedByMe;
    if (onFetchLikedByMe == null) {
      return;
    }
    try {
      final liked = await onFetchLikedByMe(_story);
      if (!mounted) {
        return;
      }
      setState(() => _hasHearted = liked);
    } catch (_) {
      // Heart stays outline if the read fails.
    }
  }

  Future<void> _loadViewers() async {
    final onFetchViewers = widget.onFetchViewers;
    if (onFetchViewers == null) {
      return;
    }
    try {
      final viewers = await onFetchViewers(_story);
      if (!mounted) {
        return;
      }
      setState(() => _cachedViewers = viewers);
    } catch (_) {
      // View count falls back to the preloaded story.viewerCount on the
      // latest segment; the sheet still loads on demand below.
    }
  }

  @override
  void dispose() {
    unawaited(_viewersSubscription?.cancel());
    _clearGestureTracking();
    _segmentProgressController
      ..removeListener(_handleProgressTick)
      ..removeStatusListener(_handleProgressStatusChange)
      ..dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    unawaited(_disposeVideoController());
    unawaited(_disposeMusicController());
    super.dispose();
  }

  void _handleProgressTick() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _handleProgressStatusChange(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _advanceToNextSegment();
    }
  }

  int _initialSegmentIndexFor(
    StatusStory story, {
    int? initialSegmentIndex,
  }) {
    if (story.totalSegments <= 0) {
      return 0;
    }
    if (initialSegmentIndex != null) {
      return initialSegmentIndex.clamp(0, story.totalSegments - 1);
    }
    if (story.isMine) {
      return 0;
    }
    if (!story.hasUnseenSegments) {
      return 0;
    }
    return math.min(
      math.max(story.seenSegments, 0),
      story.totalSegments - 1,
    );
  }

  Duration _segmentDurationFor({
    required StatusStoryType type,
    StatusStorySegment? segment,
  }) {
    if (widget.segmentDurationOverride != null) {
      return widget.segmentDurationOverride!;
    }

    final persistedDurationMillis = segment?.durationMillis;
    if (persistedDurationMillis != null && persistedDurationMillis > 0) {
      return Duration(milliseconds: persistedDurationMillis);
    }

    return switch (type) {
      StatusStoryType.text => const Duration(seconds: 5),
      StatusStoryType.photo => const Duration(seconds: 5),
      StatusStoryType.video => const Duration(seconds: 10),
    };
  }

  Future<void> _configureSegmentPlayback({
    required bool restartProgress,
  }) async {
    final segment = _currentSegment;
    final segmentType = _currentSegmentType;
    final musicPlaybackFuture = _configureMusicPlayback();
    final mediaPath = segment?.localMediaPath?.trim();
    if (segmentType != StatusStoryType.video ||
        mediaPath == null ||
        mediaPath.isEmpty) {
      await _disposeVideoController();
      if (restartProgress) {
        _restartSegmentPlayback(
          type: segmentType,
          segment: segment,
        );
      }
      await musicPlaybackFuture;
      return;
    }

    if (!statusMediaSourceExists(mediaPath)) {
      await _disposeVideoController();
      if (restartProgress) {
        _restartSegmentPlayback(
          type: segmentType,
          segment: segment,
        );
      }
      await musicPlaybackFuture;
      return;
    }

    if (_activeVideoPath == mediaPath &&
        _videoController != null &&
        _videoController!.value.isInitialized) {
      if (!_isPausedByHold) {
        await _videoController!.play();
      }
      if (restartProgress) {
        _restartSegmentPlayback(
          type: segmentType,
          segment: segment,
        );
      }
      return;
    }

    await _disposeVideoController();

    final controller = buildStatusMediaVideoController(mediaPath);
    final initialization = controller.initialize();
    _videoController = controller;
    _videoInitialization = initialization;
    _activeVideoPath = mediaPath;
    if (mounted) {
      setState(() {});
    }

    try {
      await initialization;
      if (!mounted || _videoController != controller) {
        await controller.dispose();
        return;
      }

      await controller.setLooping(true);
      final musicAssetPath = segment?.musicTrack?.previewAssetPath?.trim();
      final hasMusic = musicAssetPath != null && musicAssetPath.isNotEmpty;
      await controller.setVolume(!hasMusic && !_isMuted ? 1 : 0);
      if (!_isPausedByHold) {
        await controller.play();
      }
      if (widget.segmentDurationOverride == null &&
          (segment?.durationMillis == null || segment!.durationMillis! <= 0) &&
          controller.value.duration > Duration.zero) {
        _segmentProgressController.duration = controller.value.duration;
      }
    } catch (_) {
      if (_videoController == controller) {
        await controller.dispose();
        _videoController = null;
        _videoInitialization = null;
        _activeVideoPath = null;
      }
    }

    if (!mounted) {
      return;
    }

    if (restartProgress) {
      _restartSegmentPlayback(
        type: segmentType,
        segment: segment,
      );
    }
    await musicPlaybackFuture;
    setState(() {});
  }

  Future<void> _configureMusicPlayback() async {
    final assetPath = _currentSegment?.musicTrack?.previewAssetPath?.trim();
    if (assetPath == null || assetPath.isEmpty) {
      await _disposeMusicController();
      return;
    }

    if (_activeMusicAssetPath == assetPath &&
        _musicController != null &&
        _musicController!.value.isInitialized) {
      if (!_isPausedByHold) {
        await _musicController!.play();
      }
      return;
    }

    await _disposeMusicController();

    final controller = VideoPlayerController.asset(assetPath);
    _musicController = controller;
    _activeMusicAssetPath = assetPath;

    try {
      await controller.initialize();
      if (!mounted || _musicController != controller) {
        await controller.dispose();
        return;
      }

      await controller.setLooping(true);
      await controller.setVolume(_isMuted ? 0 : 1);
      if (!_isPausedByHold) {
        await controller.play();
      }
    } catch (_) {
      if (_musicController == controller) {
        await controller.dispose();
        _musicController = null;
        _activeMusicAssetPath = null;
      }
    }
  }

  void _startCurrentSegmentPlayback() {
    final segment = _currentSegment;
    final hasMusic =
        segment?.musicTrack?.previewAssetPath?.trim().isNotEmpty == true;
    final isLocalVideoSegment = _currentSegmentType == StatusStoryType.video &&
        segment?.hasLocalMedia == true;

    if (!isLocalVideoSegment && !hasMusic) {
      unawaited(_disposeVideoController());
      _restartSegmentPlayback(
        type: _currentSegmentType,
        segment: segment,
      );
      return;
    }

    unawaited(_configureSegmentPlayback(restartProgress: true));
  }

  void _restartSegmentPlayback({
    required StatusStoryType type,
    StatusStorySegment? segment,
  }) {
    _segmentProgressController.duration =
        _segmentDurationFor(type: type, segment: segment);
    if (_isPausedByHold) {
      _segmentProgressController.value = 0;
    } else {
      _segmentProgressController.forward(from: 0);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _pausePlaybackForHold() {
    if (_isPausedByHold || _isClosing) {
      return;
    }

    _isPausedByHold = true;
    _segmentProgressController.stop();
    unawaited(_videoController?.pause());
    unawaited(_musicController?.pause());
  }

  void _resumePlaybackFromHold() {
    if (!_isPausedByHold || _isClosing) {
      return;
    }

    _isPausedByHold = false;
    _segmentProgressController.forward();
    if (_currentSegmentType == StatusStoryType.video &&
        _videoController != null &&
        _videoController!.value.isInitialized) {
      unawaited(_videoController!.play());
    }
    if (_musicController != null && _musicController!.value.isInitialized) {
      unawaited(_musicController!.play());
    }
  }

  void _resumePlaybackIfNeeded({
    required bool shouldResume,
  }) {
    if (!shouldResume || _isClosing) {
      return;
    }

    _segmentProgressController.forward();
    if (_currentSegmentType == StatusStoryType.video &&
        _videoController != null &&
        _videoController!.value.isInitialized) {
      unawaited(_videoController!.play());
    }
    if (_musicController != null && _musicController!.value.isInitialized) {
      unawaited(_musicController!.play());
    }
  }

  void _handleZonePointerDown(
    _StoryTapDirection direction,
    PointerDownEvent event,
  ) {
    if (_isClosing || _activePointer != null) {
      return;
    }

    // While replying, a tap on the story itself should only dismiss the
    // keyboard -- not also navigate to the previous/next segment out from
    // under whatever the person was typing.
    if (_replyFocusNode.hasFocus) {
      _replyFocusNode.unfocus();
      return;
    }

    _activePointer = event.pointer;
    _activePointerDownAt = DateTime.now();
    _pendingTapDirection = direction;
    _pausePlaybackForHold();
  }

  void _handleZonePointerUp(
    _StoryTapDirection direction,
    PointerUpEvent event,
  ) {
    if (_activePointer != event.pointer) {
      return;
    }

    final pointerDownAt = _activePointerDownAt;
    final pressDuration = pointerDownAt == null
        ? _tapNavigationThreshold
        : DateTime.now().difference(pointerDownAt);
    final shouldNavigate = pressDuration < _tapNavigationThreshold &&
        _pendingTapDirection == direction;
    _clearGestureTracking();

    if (shouldNavigate) {
      _cancelHoldPauseWithoutResume();
      switch (direction) {
        case _StoryTapDirection.left:
          unawaited(_returnToPreviousSegment());
          break;
        case _StoryTapDirection.right:
          unawaited(_advanceToNextSegment());
          break;
      }
      return;
    }

    _resumePlaybackFromHold();
  }

  void _handleZonePointerCancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) {
      return;
    }

    _clearGestureTracking();
    if (_isPausedByHold) {
      _resumePlaybackFromHold();
    }
  }

  void _cancelHoldPauseWithoutResume() {
    if (!_isPausedByHold) {
      return;
    }

    _isPausedByHold = false;
  }

  void _clearGestureTracking() {
    _activePointer = null;
    _activePointerDownAt = null;
    _pendingTapDirection = null;
  }

  void _reportCurrentSegmentViewed() {
    if (_story.totalSegments <= 0) {
      return;
    }

    final seenSegments =
        math.min(_currentSegmentIndex + 1, _story.totalSegments);
    if (seenSegments <= _reportedSeenSegments) {
      return;
    }

    _reportedSeenSegments = seenSegments;
    widget.onStoryViewed(_story.copyWith(seenSegments: seenSegments));
  }

  /// Sends [text] as a real direct message to the story's owner -- the
  /// same as WhatsApp's own status reply. Starts or reuses the 1:1 thread
  /// with them first, and attaches a [StoryReplyContext] snapshot of the
  /// segment being viewed so the chat message renders a small tappable
  /// story-thumbnail card. The heart quick-react is a separate, lighter
  /// path -- see [_toggleHeart] -- that never sends a message.
  Future<void> _sendReply(String text) async {
    final chatsController = widget.chatsController;
    final trimmed = text.trim();
    if (chatsController == null ||
        trimmed.isEmpty ||
        _isSendingReply ||
        _story.isMine) {
      return;
    }

    setState(() => _isSendingReply = true);
    final threadId = await chatsController.startThreadWith(
      participantUid: _story.id,
      participantName: _story.name,
      avatarLabel: _story.avatarLabel,
      accentColor: _story.accentColor,
    );
    final didSend = threadId != null &&
        await chatsController.sendTextMessage(
          threadId: threadId,
          text: trimmed,
          storyReplyContext: StoryReplyContext(
            storyOwnerUid: _story.id,
            storyOwnerName: _story.name,
            segmentType: _currentSegmentType,
            previewText: _currentSegment?.previewText,
            mediaUrl: _currentSegment?.localMediaPath,
            accentColorArgb: _story.accentColor.toARGB32(),
          ),
        );

    if (!mounted) {
      return;
    }
    setState(() => _isSendingReply = false);
    if (didSend) {
      _replyController.clear();
      _replyFocusNode.unfocus();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          didSend
              ? 'Reply sent to ${_story.name}'
              : chatsController.errorMessage ??
                  'We could not send that reply right now.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Toggles the heart quick-react -- persisted in Firestore so the filled
  /// state survives closing and reopening the story, and reflected on the
  /// owner's "Viewed by" list (live via [onWatchViewers] when supported).
  Future<void> _toggleHeart() async {
    final onSetStoryLiked = widget.onSetStoryLiked;
    if (onSetStoryLiked == null ||
        _story.isMine ||
        _isTogglingHeart) {
      return;
    }

    final nextLiked = !_hasHearted;
    setState(() {
      _hasHearted = nextLiked;
      _isTogglingHeart = true;
    });
    final didSucceed = await onSetStoryLiked(_story, nextLiked);
    if (!mounted) {
      return;
    }
    setState(() => _isTogglingHeart = false);
    if (didSucceed) {
      return;
    }
    setState(() => _hasHearted = !nextLiked);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextLiked
              ? 'We could not like that status right now.'
              : 'We could not remove that reaction right now.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteCurrentSegmentWithConfirmation() async {
    final onDeleteSegment = widget.onDeleteSegment;
    final segment = _currentSegment;
    if (onDeleteSegment == null ||
        segment == null ||
        _isDeletingSegment ||
        _isClosing) {
      return;
    }

    final shouldResumeAfterDialog = !_isPausedByHold;
    _segmentProgressController.stop();
    await _videoController?.pause();
    await _musicController?.pause();
    if (!mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final isLastSegment = _story.totalSegments <= 1;
        final segmentLabel = switch (segment.type) {
          StatusStoryType.text => 'text status',
          StatusStoryType.photo => 'photo status',
          StatusStoryType.video => 'video status',
        };

        return AlertDialog(
          title: Text(
            isLastSegment ? 'Delete status?' : 'Delete this status item?',
          ),
          content: Text(
            isLastSegment
                ? 'This will remove your last $segmentLabel from My status.'
                : 'This removes only the current $segmentLabel. Your other status items stay available.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (confirmed != true) {
      _resumePlaybackIfNeeded(shouldResume: shouldResumeAfterDialog);
      return;
    }

    setState(() {
      _isDeletingSegment = true;
    });

    final result = await onDeleteSegment(_story, segment);
    if (!mounted) {
      return;
    }

    setState(() {
      _isDeletingSegment = false;
    });

    if (!result.didDelete) {
      final errorMessage =
          result.errorMessage ?? 'We could not delete that status right now.';
      await showErrorDialog(context, errorMessage);
      if (!mounted) {
        return;
      }
      _resumePlaybackIfNeeded(shouldResume: shouldResumeAfterDialog);
      return;
    }

    final updatedStory = result.updatedStory;
    if (updatedStory == null || !updatedStory.hasSegments) {
      await _closeViewer();
      return;
    }

    setState(() {
      _storyData = updatedStory;
      _currentSegmentIndex = math.min(
        _currentSegmentIndex,
        updatedStory.totalSegments - 1,
      );
      _reportedSeenSegments = updatedStory.clampedSeenSegments;
    });
    _startCurrentSegmentPlayback();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _reportCurrentSegmentViewed();
    });
  }

  Future<void> _showViewersSheet() async {
    final onFetchViewers = widget.onFetchViewers;
    if (onFetchViewers == null || _isClosing) {
      return;
    }

    final shouldResumeAfterSheet = !_isPausedByHold;
    _pausePlaybackForHold();
    if (!mounted) {
      return;
    }

    // Viewers are prefetched in initState, but tap can beat that future --
    // wait here so the sheet opens once at its final height instead of
    // growing from a spinner (which reads as a jerk after the slide-up).
    if (_cachedViewers == null) {
      await _loadViewers();
    }
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (_) => _StoryViewersSheet(
        viewers: _viewersForSegment(_currentSegmentIndex),
      ),
    );

    if (!mounted) {
      return;
    }
    _resumePlaybackIfNeeded(shouldResume: shouldResumeAfterSheet);
  }

  Future<void> _advanceToNextSegment() async {
    if (_isTransitioning || _isClosing || !mounted) {
      return;
    }

    _isTransitioning = true;
    try {
      if (_currentSegmentIndex < _segmentCount - 1) {
        setState(() {
          _currentSegmentIndex += 1;
        });
        _reportCurrentSegmentViewed();
        _startCurrentSegmentPlayback();
        return;
      }

      await _closeViewer();
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> _returnToPreviousSegment() async {
    if (_isTransitioning || _isClosing || !mounted) {
      return;
    }

    _isTransitioning = true;
    try {
      if (_currentSegmentIndex > 0) {
        setState(() {
          _currentSegmentIndex -= 1;
        });
        _startCurrentSegmentPlayback();
        return;
      }

      _startCurrentSegmentPlayback();
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> _closeViewer() async {
    if (_isClosing || !mounted) {
      return;
    }

    _isClosing = true;
    _clearGestureTracking();
    _isPausedByHold = false;
    _segmentProgressController.stop();
    await _videoController?.pause();
    await _musicController?.pause();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).maybePop();
  }

  Future<void> _disposeVideoController() async {
    final controller = _videoController;
    _videoController = null;
    _videoInitialization = null;
    _activeVideoPath = null;
    if (controller != null) {
      await controller.dispose();
    }
  }

  Future<void> _disposeMusicController() async {
    final controller = _musicController;
    _musicController = null;
    _activeMusicAssetPath = null;
    if (controller != null) {
      await controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = _story;
    final theme = Theme.of(context);

    return Scaffold(
      key: const Key('updates_story_viewer'),
      backgroundColor: AppPalette.deepOcean,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              story.accentColor.withValues(alpha: 0.86),
              AppPalette.deepOcean,
              AppPalette.deepOcean.withValues(alpha: 0.94),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _StoryViewerCard(
                  key: ValueKey(
                    '${story.id}-segment-$_currentSegmentIndex-${_currentSegment?.localMediaPath ?? _currentSegmentType.name}',
                  ),
                  story: story,
                  segment: _currentSegment,
                  currentSegmentIndex: _currentSegmentIndex,
                  totalSegments: _segmentCount,
                  videoController: _videoController,
                  videoInitialization: _videoInitialization,
                ),
              ),
            ),
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: Listener(
                      key: const Key(
                        'updates_story_viewer_left_zone',
                      ),
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) => _handleZonePointerDown(
                          _StoryTapDirection.left, event),
                      onPointerUp: (event) =>
                          _handleZonePointerUp(_StoryTapDirection.left, event),
                      onPointerCancel: _handleZonePointerCancel,
                    ),
                  ),
                  Expanded(
                    child: Listener(
                      key: const Key(
                        'updates_story_viewer_right_zone',
                      ),
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) => _handleZonePointerDown(
                        _StoryTapDirection.right,
                        event,
                      ),
                      onPointerUp: (event) =>
                          _handleZonePointerUp(_StoryTapDirection.right, event),
                      onPointerCancel: _handleZonePointerCancel,
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  children: [
                    _StoryProgressBar(
                      totalSegments: _segmentCount,
                      currentSegmentIndex: _currentSegmentIndex,
                      activeProgress: _segmentProgress,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        story.isMine
                            ? AvatarBadge(
                                label: story.avatarLabel,
                                color: story.accentColor,
                                size: 38,
                              )
                            : StatusRingAvatar(
                                label: story.avatarLabel,
                                color: story.accentColor,
                                totalSegments: story.totalSegments,
                                seenSegments: story.seenSegments,
                                size: 38,
                              ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                story.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: story.isMine &&
                                        widget.onFetchViewers != null
                                    ? _showViewersSheet
                                    : null,
                                child: Text(
                                  story.isMine
                                      ? '${_currentSegmentTimeLabel} • $_currentSegmentViewerCount '
                                          '${_currentSegmentViewerCount == 1 ? 'view' : 'views'}'
                                      : _currentSegmentTimeLabel,
                                  key: story.isMine
                                      ? const Key('updates_story_viewer_count')
                                      : null,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    decoration: story.isMine &&
                                            widget.onFetchViewers != null
                                        ? TextDecoration.underline
                                        : null,
                                    decorationColor:
                                        Colors.white.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_hasAudibleAudio) ...[
                          _StoryIconButton(
                            key: const Key('updates_story_mute_button'),
                            tooltip: _isMuted ? 'Unmute' : 'Mute',
                            onPressed: _toggleMute,
                            child: Icon(
                              _isMuted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (story.isMine && widget.onDeleteSegment != null)
                          _StoryIconButton(
                            key: const Key('updates_story_delete_button'),
                            tooltip: 'Delete current status',
                            onPressed: _isDeletingSegment
                                ? null
                                : _deleteCurrentSegmentWithConfirmation,
                            child: _isDeletingSegment
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                          ),
                        const SizedBox(width: 6),
                        _StoryIconButton(
                          tooltip: 'Close',
                          onPressed: _closeViewer,
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (!story.isMine && widget.chatsController != null)
                      _StoryReplyBar(
                        recipientName: story.name,
                        accentColor: story.accentColor,
                        controller: _replyController,
                        focusNode: _replyFocusNode,
                        isSending: _isSendingReply,
                        hasHearted: _hasHearted,
                        onSendText: _sendReply,
                        onHeartTap: _toggleHeart,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryViewerCard extends StatelessWidget {
  const _StoryViewerCard({
    required this.story,
    required this.currentSegmentIndex,
    required this.totalSegments,
    this.segment,
    this.videoController,
    this.videoInitialization,
    super.key,
  });

  final StatusStory story;
  final StatusStorySegment? segment;
  final int currentSegmentIndex;
  final int totalSegments;
  final VideoPlayerController? videoController;
  final Future<void>? videoInitialization;

  @override
  Widget build(BuildContext context) {
    final activeSegment = segment;
    if ((activeSegment?.type ?? story.type) == StatusStoryType.text) {
      return _TextStoryCard(
        story: story,
        segment: activeSegment,
      );
    }
    if (activeSegment?.hasLocalMedia == true) {
      return _LocalMediaStoryCard(
        story: story,
        segment: activeSegment!,
        currentSegmentIndex: currentSegmentIndex,
        totalSegments: totalSegments,
        videoController: videoController,
        videoInitialization: videoInitialization,
      );
    }

    return _FallbackStoryCard(
      story: story,
      currentSegmentIndex: currentSegmentIndex,
      totalSegments: totalSegments,
    );
  }
}

class _TextStoryCard extends StatelessWidget {
  const _TextStoryCard({
    required this.story,
    required this.segment,
  });

  final StatusStory story;
  final StatusStorySegment? segment;

  @override
  Widget build(BuildContext context) {
    final activeSegment = segment;
    return TextStatusCanvas(
      key: const Key('updates_story_text_card'),
      text: activeSegment?.previewText ?? story.previewText,
      style: activeSegment?.textStyle ?? const StatusTextStyle(),
      accentColor: story.accentColor,
      borderRadius: BorderRadius.zero,
    );
  }
}

class _LocalMediaStoryCard extends StatelessWidget {
  const _LocalMediaStoryCard({
    required this.story,
    required this.segment,
    required this.currentSegmentIndex,
    required this.totalSegments,
    this.videoController,
    this.videoInitialization,
  });

  final StatusStory story;
  final StatusStorySegment segment;
  final int currentSegmentIndex;
  final int totalSegments;
  final VideoPlayerController? videoController;
  final Future<void>? videoInitialization;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: const Key('updates_story_viewer_media_surface'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          StatusStoryMediaSurface(
            type: segment.type,
            localMediaPath: segment.localMediaPath ?? '',
            mediaTransform: segment.mediaTransform,
            videoController: videoController,
            videoInitialization: videoInitialization,
            unavailableMessage: 'This local media is no longer available.',
          ),
          SafeArea(
            child: StatusMediaDecorationOverlay(
              segment: segment,
              accentColor: story.accentColor,
              padding: kStatusMediaOverlayCanvasPadding,
              showBackdrop: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackStoryCard extends StatelessWidget {
  const _FallbackStoryCard({
    required this.story,
    required this.currentSegmentIndex,
    required this.totalSegments,
  });

  final StatusStory story;
  final int currentSegmentIndex;
  final int totalSegments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intensity =
        totalSegments <= 1 ? 1.0 : (currentSegmentIndex + 1) / totalSegments;
    final previewLine = _previewLineForSegment(story, currentSegmentIndex);
    final typeLabel = _typeLabelFor(story.type);
    final segmentLabel = totalSegments <= 1
        ? typeLabel
        : '${currentSegmentIndex + 1} / $totalSegments';

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.06 + (0.02 * intensity)),
            story.accentColor.withValues(alpha: 0.12 + (0.08 * intensity)),
            AppPalette.deepOcean.withValues(alpha: 0.56 + (0.08 * intensity)),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 56, 24, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconForType(story.type),
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    segmentLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              previewLine,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.94),
                height: 1.02,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              story.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconForType(StatusStoryType type) {
    return switch (type) {
      StatusStoryType.text => Icons.text_fields_rounded,
      StatusStoryType.photo => Icons.photo_library_outlined,
      StatusStoryType.video => Icons.videocam_outlined,
    };
  }

  static String _typeLabelFor(
    StatusStoryType type,
  ) {
    return switch (type) {
      StatusStoryType.text => 'Text',
      StatusStoryType.photo => 'Photo',
      StatusStoryType.video => 'Video',
    };
  }

  static String _previewLineForSegment(
    StatusStory story,
    int currentSegmentIndex,
  ) {
    final candidate =
        story.segmentAt(currentSegmentIndex)?.previewText.trim() ??
            story.previewText.trim();
    if (candidate.isNotEmpty &&
        candidate.toLowerCase() != 'shared a new photo update' &&
        candidate.toLowerCase() != 'shared a new video update') {
      return candidate;
    }

    return switch (story.type) {
      StatusStoryType.text => story.isMine ? 'Your text status' : 'Text update',
      StatusStoryType.photo => 'Photo update',
      StatusStoryType.video => 'Video clip',
    };
  }
}

/// A WhatsApp-style bottom reply bar for someone else's story -- a text
/// field that sends a real direct message to them, plus a heart
/// quick-react (a lightweight, message-free like -- see
/// [_StatusStoryViewerScreenState._toggleHeart]).
class _StoryReplyBar extends StatelessWidget {
  const _StoryReplyBar({
    required this.recipientName,
    required this.accentColor,
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.hasHearted,
    required this.onSendText,
    required this.onHeartTap,
  });

  final String recipientName;

  /// The story's own accent color -- used to fill the heart icon once
  /// hearted, so the "liked" state reads as a color suited to this
  /// particular story rather than a single fixed color for every story.
  final Color accentColor;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;

  /// Whether this story has already been hearted -- swaps the heart button
  /// from outline to filled, loaded from Firestore when the story opens.
  final bool hasHearted;
  final ValueChanged<String> onSendText;
  final VoidCallback onHeartTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: TextField(
                key: const Key('updates_story_reply_field'),
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                onSubmitted: isSending ? null : onSendText,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Reply to $recipientName…',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.22),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // A single trailing action slot -- the heart quick-react by
          // default, swapping to a send button once the field actually has
          // focus or unsent text (matching the main chat composer's own
          // send button, which only ever appears there, not floating
          // beside an idle field). Listens to both the field's own text and
          // its focus so either alone is enough to swap.
          ListenableBuilder(
            listenable: Listenable.merge([controller, focusNode]),
            builder: (context, _) {
              final hasText = controller.text.trim().isNotEmpty;
              final showSend = focusNode.hasFocus || hasText;
              if (!showSend) {
                return _StoryReplyActionButton(
                  actionKey: const Key('updates_story_heart_react_button'),
                  tooltip: hasHearted ? 'Unlike' : 'Send a heart',
                  // Independent of isSending -- liking doesn't send a chat
                  // message, so it's never blocked by a reply in flight.
                  // A second tap while hasHearted is already true is a
                  // no-op anyway (see _toggleHeart's own guard).
                  onPressed: onHeartTap,
                  child: Icon(
                    hasHearted
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: hasHearted ? accentColor : Colors.white,
                    size: 22,
                  ),
                );
              }
              final canSend = hasText && !isSending;
              return _StoryReplyActionButton(
                actionKey: const Key('updates_story_reply_send_button'),
                tooltip: 'Send',
                onPressed: canSend ? () => onSendText(controller.text) : null,
                child: isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        Icons.send_rounded,
                        color:
                            Colors.white.withValues(alpha: canSend ? 1 : 0.4),
                        size: 20,
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A 44x44 tap target for the reply bar's own action buttons (heart, send)
/// -- distinct from [_StoryIconButton]'s 32x32 (that one's an established
/// pattern already used by the top row's mute/delete/close; this one is new
/// chrome, so it follows docs/ui_layout_guidelines.md rule 7 properly).
class _StoryReplyActionButton extends StatelessWidget {
  const _StoryReplyActionButton({
    required this.child,
    required this.onPressed,
    this.tooltip,
    this.actionKey,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.black.withValues(alpha: 0.22),
      shape: const CircleBorder(),
      child: InkWell(
        key: actionKey,
        onTap: onPressed,
        customBorder: const CircleBorder(),
        canRequestFocus: false,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: child),
        ),
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) {
      return button;
    }
    return Tooltip(message: tooltip, child: button);
  }
}

/// "Viewed by" bottom sheet for your own story -- WhatsApp shows exactly
/// who viewed a status you posted, not just a bare count.
class _StoryViewersSheet extends StatelessWidget {
  const _StoryViewersSheet({required this.viewers});

  final List<StoryViewer> viewers;

  static const Color _sheetFill = Color(0xBF000000);
  static const Color _handleFill = Color(0x59FFFFFF);
  static const Color _primaryText = Colors.white;
  static const Color _secondaryText = Color(0xB3FFFFFF);
  static const Color _emptyText = Color(0x8FFFFFFF);

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: Container(
        key: const Key('story_viewers_sheet'),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        color: _sheetFill,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _handleFill,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Viewed by',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _primaryText,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ),
            if (viewers.isEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 28 + bottomInset),
                child: const Text(
                  'No views yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _emptyText,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + bottomInset),
                  itemCount: viewers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (context, index) {
                    return _StoryViewerRow(viewer: viewers[index]);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StoryViewerRow extends StatelessWidget {
  const _StoryViewerRow({required this.viewer});

  final StoryViewer viewer;

  @override
  Widget build(BuildContext context) {
    final viewedAtLabel =
        viewer.viewedAt == null ? null : _relativeViewLabel(viewer.viewedAt!);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          AvatarBadge(
            label: viewer.avatarLabel,
            color: viewer.accentColor,
            avatarUrl: viewer.avatarUrl,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              viewer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _StoryViewersSheet._primaryText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
          if (viewer.liked) ...[
            Icon(
              Icons.favorite_rounded,
              size: 18,
              color: viewer.accentColor.withValues(alpha: 0.95),
            ),
            if (viewedAtLabel != null) const SizedBox(width: 8),
          ],
          if (viewedAtLabel != null)
            Text(
              viewedAtLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _StoryViewersSheet._secondaryText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.1,
              ),
            ),
        ],
      ),
    );
  }
}

String _relativeViewLabel(DateTime dateTime) {
  final elapsed = DateTime.now().difference(dateTime);
  if (elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
  return '${elapsed.inDays}d ago';
}

class _StoryIconButton extends StatelessWidget {
  const _StoryIconButton({
    required this.child,
    required this.onPressed,
    this.tooltip,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.black.withValues(alpha: 0.22),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(child: child),
        ),
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) {
      return button;
    }

    return Tooltip(
      message: tooltip,
      child: button,
    );
  }
}

class _StoryProgressBar extends StatelessWidget {
  const _StoryProgressBar({
    required this.totalSegments,
    required this.currentSegmentIndex,
    required this.activeProgress,
  });

  final int totalSegments;
  final int currentSegmentIndex;
  final double activeProgress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(
        totalSegments,
        (index) {
          final progress = (index < currentSegmentIndex
                  ? 1.0
                  : index == currentSegmentIndex
                      ? activeProgress
                      : 0.0)
              .clamp(0.0, 1.0)
              .toDouble();
          final trackColor = Colors.white.withValues(
            alpha: index == currentSegmentIndex ? 0.3 : 0.18,
          );

          return Expanded(
            child: Padding(
              padding:
                  EdgeInsets.only(right: index == totalSegments - 1 ? 0 : 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 4,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fillWidth = constraints.maxWidth * progress;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                            key: Key('updates_story_progress_track_$index'),
                            decoration: BoxDecoration(
                              color: trackColor,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              key: Key('updates_story_progress_fill_$index'),
                              width: fillWidth,
                              height: constraints.maxHeight,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
