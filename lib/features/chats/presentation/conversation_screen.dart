import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/status_story.dart';
import '../../../core/permissions/location_permission_dialog.dart';
import '../../calls/application/calls_controller.dart';
import '../../calls/domain/call_contact.dart';
import '../../calls/domain/call_history_entry.dart';
import '../../calls/presentation/call_flow.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/floating_glass_popup.dart';
import '../../shared/widgets/liquid_glass.dart';
import '../../updates/application/updates_controller.dart';
import '../../updates/presentation/story_viewer_launcher.dart';
import '../../updates/presentation/widgets/status_media_source.dart';
import '../../updates/presentation/widgets/status_ring_avatar.dart';
import '../application/chats_controller.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_message.dart';
import '../domain/chat_thread.dart';
import '../domain/message_reaction.dart';
import 'attachment_viewer_screen.dart';
import 'contact_info_screen.dart';
import 'widgets/location_map_preview.dart';
import 'widgets/video_thumbnail_cache.dart';
import 'widgets/voice_note_bubble.dart';
import 'widgets/voice_note_recorder_sheet.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    required this.callsController,
    required this.controller,
    required this.updatesController,
    required this.threadId,
    super.key,
  });

  final CallsController callsController;
  final ChatsController controller;
  final UpdatesController updatesController;
  final String threadId;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  static const double _messageListBottomPadding = 12;
  static const Duration _sentMessageEntryDuration = Duration(milliseconds: 220);

  final GlobalKey _composerBarKey = GlobalKey();
  final ImagePicker _imagePicker = ImagePicker();
  late final TextEditingController _composerController;
  late final ScrollController _messageListController;
  double? _composerLockedMinHeight;
  String? _lastRenderedThreadId;
  String? _lastKnownLatestMessageId;
  double? _lastKnownBottomInset;
  String? _animatedMessageId;
  final List<ChatMessage> _localMessages = <ChatMessage>[];
  Timer? _composerUnlockTimer;
  Timer? _animatedMessageCleanupTimer;

  /// True whenever the message list should stay pinned to its true bottom
  /// -- set on open, on sending, and whenever an incoming message arrives
  /// while the reader was already at the bottom. Cleared the moment a real
  /// user drag scrolls them away from the bottom. While true,
  /// [_handleMessageListNotification] re-snaps to the bottom every time the
  /// list's content height actually changes (an async image/map/etc.
  /// finishing layout), which is the real signal for "the true bottom
  /// moved" -- unlike a guessed fixed-delay timer, this can't undershoot on
  /// a chat with many attachments or overshoot the wait on a slow one.
  bool _stickToBottom = true;

  /// The most recently observed [ScrollMetrics.maxScrollExtent], used to
  /// tell "content actually grew" apart from "pixels just isn't at the
  /// current max" (e.g. a deliberate scroll-up, or this state's own
  /// programmatic jump landing short of the final value) -- see
  /// [_handleMessageListNotification].
  double? _lastObservedMaxScrollExtent;

  @override
  void initState() {
    super.initState();
    _composerController = TextEditingController();
    _messageListController = ScrollController();
  }

  @override
  void dispose() {
    _composerUnlockTimer?.cancel();
    _animatedMessageCleanupTimer?.cancel();
    _composerController.dispose();
    _messageListController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId == widget.threadId) {
      return;
    }

    _localMessages.clear();
    _lastRenderedThreadId = null;
    _lastKnownLatestMessageId = null;
    _animatedMessageId = null;
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
        final thread = widget.controller.threadById(widget.threadId);
        final story = thread == null
            ? null
            : widget.updatesController.storyForParticipant(
                avatarLabel: thread.avatarLabel,
                name: thread.name,
              );
        final composerInteractionsLocked =
            widget.controller.isThreadBusy(thread?.id ?? widget.threadId);
        final canSendText = _composerController.text.trim().isNotEmpty &&
            !composerInteractionsLocked;

        if (thread == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Conversation')),
            body: Center(
              child: Text(
                'This conversation is no longer available.',
                style: theme.textTheme.titleMedium,
              ),
            ),
          );
        }

        if (_lastRenderedThreadId != thread.id) {
          _lastRenderedThreadId = thread.id;
          _lastKnownLatestMessageId = thread.latestMessage?.id;
          _scheduleScrollToLatestMessage(animated: false);
        } else {
          // A message landed in this already-open thread -- either our own
          // send confirming, or (the previously-missing case) the other
          // participant's message arriving over the live watchThreads()
          // stream. Follow it to the bottom only if the reader was already
          // near the latest message, same convention as _retryFailedMessage.
          final latestMessageId = thread.latestMessage?.id;
          if (latestMessageId != null &&
              latestMessageId != _lastKnownLatestMessageId) {
            final wasNearLatest = _isNearLatestMessage();
            _lastKnownLatestMessageId = latestMessageId;
            if (wasNearLatest) {
              _scheduleScrollToLatestMessage(animated: true);
            }
            if (thread.unreadCount > 0) {
              // The reader is already looking at this thread, so a message
              // landing live must not sit there as "unread" until they back
              // out and back in -- mark it read now instead of leaving the
              // chat list/tab badge to over-count something already seen.
              // Deferred: openThread() -> notifyListeners() synchronously,
              // and calling that mid-build would rebuild this same widget
              // while it's still building.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  widget.controller.openThread(thread.id);
                }
              });
            }
          }
        }

        // The keyboard showing/hiding resizes this Scaffold's body (default
        // resizeToAvoidBottomInset), which shrinks or grows the message
        // list's viewport without moving its scroll offset -- so the latest
        // message ends up stranded behind the keyboard on open, or leaves a
        // gap at the bottom on close. Re-pin to the latest message on every
        // inset change so it always sits just above the keyboard/composer.
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        if (_lastKnownBottomInset != null &&
            bottomInset != _lastKnownBottomInset) {
          _scheduleScrollToLatestMessage(animated: true);
        }
        _lastKnownBottomInset = bottomInset;

        final visibleMessages = _visibleMessagesForThread(thread);

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            // Fixed-height chrome (the toolbar) with a two-line title stack
            // -- clamp text scale so it can't outgrow that height at large
            // accessibility scale. See docs/ui_layout_guidelines.md rule 4.
            title: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: thread.hasStory && story != null
                        ? () => _openThreadStory(story)
                        : null,
                    child: thread.hasStory
                        ? StatusRingAvatar(
                            label: thread.avatarLabel,
                            color: thread.accentColor,
                            avatarUrl: thread.avatarUrl,
                            totalSegments: story?.totalSegments ?? 1,
                            seenSegments: story?.clampedSeenSegments ?? 0,
                            size: 44,
                          )
                        : AvatarBadge(
                            label: thread.avatarLabel,
                            color: thread.accentColor,
                            avatarUrl: thread.avatarUrl,
                            size: 44,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openContactInfo(thread.id),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            thread.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            thread.isGroup
                                ? 'Group chat • ${visibleMessages.length} messages'
                                : 'Secure chat preview',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              LiquidGlassIconButton(
                icon: Icons.call_outlined,
                tooltip: 'Audio call',
                size: 40,
                // The app bar is a fixed, non-overlapping toolbar here (not
                // a floating sliver over scrolling content), so there is no
                // real content behind it for a blur to reveal.
                blurred: false,
                onTap: () {
                  startCallFlow(
                    context,
                    controller: widget.callsController,
                    contact: _callContactForThread(thread),
                    type: CallType.audio,
                  );
                },
              ),
              const SizedBox(width: 8),
              LiquidGlassIconButton(
                icon: Icons.videocam_outlined,
                tooltip: 'Video call',
                size: 40,
                blurred: false,
                onTap: () {
                  startCallFlow(
                    context,
                    controller: widget.callsController,
                    contact: _callContactForThread(thread),
                    type: CallType.video,
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            // The composer's own surface color, not SafeArea's reserved gap,
            // should paint under the home indicator -- see _ComposerBar's
            // bottom padding, which adds the inset back for its content.
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    // Tapping empty space (background, between bubbles)
                    // dismisses the keyboard, matching WhatsApp -- message
                    // bubbles keep their own tap/long-press handling since
                    // they claim the gesture first; this only ever fires
                    // for taps nothing else already handled. Translucent,
                    // not opaque, so it doesn't block the ListView's own
                    // scroll/drag gesture recognition underneath it.
                    behavior: HitTestBehavior.translucent,
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(
                          alpha:
                              theme.brightness == Brightness.dark ? 0.94 : 0.98,
                        ),
                      ),
                      child: NotificationListener<Notification>(
                        onNotification: _handleMessageListNotification,
                        child: ListView.builder(
                        key: const Key('conversation_message_list'),
                        controller: _messageListController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          16,
                          16,
                          _messageListBottomPadding,
                        ),
                        itemCount: visibleMessages.length,
                        itemBuilder: (context, index) {
                        final message = visibleMessages[index];
                        final previous =
                            index == 0 ? null : visibleMessages[index - 1];
                        final shouldShowDayChip = previous == null ||
                            !_isSameDay(previous.sentAt, message.sentAt);

                        return Column(
                          children: [
                            if (shouldShowDayChip)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _DayDivider(
                                    label: _dayLabelFor(message.sentAt)),
                              ),
                            _AnimatedMessageEntry(
                              key: ValueKey(
                                  'conversation_message_${message.id}'),
                              animateOnMount: message.id == _animatedMessageId,
                              isMine: message.isFromCurrentUser,
                              child: _MessageBubble(
                                thread: thread,
                                message: message,
                                onRetryTap: message.isFromCurrentUser &&
                                        message.deliveryState ==
                                            MessageDeliveryState.failed &&
                                        _localMessages.any(
                                          (localMessage) =>
                                              localMessage.id == message.id,
                                        )
                                    ? () => _retryFailedMessage(
                                          thread.id,
                                          message,
                                        )
                                    : null,
                                onAttachmentTap: (attachment) {
                                  _handleAttachmentPreviewTap(
                                    attachment,
                                    threadName: thread.name,
                                  );
                                },
                                onReactionTap: (emoji) {
                                  widget.controller.toggleMessageReaction(
                                    threadId: thread.id,
                                    messageId: message.id,
                                    emoji: emoji,
                                  );
                                },
                              ),
                            ),
                            if (index != visibleMessages.length - 1)
                              const SizedBox(height: 12),
                          ],
                        );
                        },
                        ),
                      ),
                    ),
                  ),
                ),
                if (thread.isBlocked)
                  _BlockedContactBanner(name: thread.name)
                else
                  _ComposerBar(
                    composerBarKey: _composerBarKey,
                    controller: _composerController,
                    isBusy: composerInteractionsLocked,
                    canSendText: canSendText,
                    lockedMinHeight: _composerLockedMinHeight,
                    onAttachmentTap: (type) async {
                      _handleAttachmentTap(thread.id, type);
                    },
                    onSendTap: () async {
                      _handleSendTap(thread.id);
                    },
                    onChanged: (_) => setState(() {}),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openThreadStory(StatusStory story) {
    return openStatusStoryViewer(
      context,
      controller: widget.updatesController,
      story: story,
    );
  }

  Future<void> _openContactInfo(String threadId) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContactInfoScreen(
          controller: widget.controller,
          threadId: threadId,
        ),
      ),
    );
  }

  Future<void> _handleAttachmentTap(
    String threadId,
    ChatAttachmentType type,
  ) async {
    if (type == ChatAttachmentType.location) {
      await _shareCurrentLocation(threadId);
      return;
    }

    final attachments = await _resolveAttachmentsForTap(
      threadId: threadId,
      type: type,
    );
    if (!mounted || attachments == null || attachments.isEmpty) {
      return;
    }

    final trimmedCaption = _composerController.text.trim();
    final wasNearLatest = _isNearLatestMessage();
    final localMessage = _buildLocalMessage(
      threadId: threadId,
      text: trimmedCaption,
      attachments: attachments,
    );

    _lockComposerHeight();
    _upsertLocalMessage(localMessage);
    _markMessageForAnimation(localMessage.id);
    _composerController.clear();
    if (mounted) {
      setState(() {});
    }
    _scheduleScrollToLatestMessage(animated: !wasNearLatest);

    final didSend = await widget.controller.sendAttachmentMessage(
      threadId: threadId,
      attachments: attachments,
      caption: trimmedCaption.isEmpty ? null : trimmedCaption,
    );

    if (!mounted) {
      return;
    }

    if (!didSend) {
      _upsertLocalMessage(
        localMessage.copyWith(
          deliveryState: MessageDeliveryState.failed,
        ),
      );
      _releaseComposerReset();
    } else {
      _removeLocalMessage(localMessage.id);
      _scheduleScrollToLatestMessage(animated: false);
      _scheduleComposerReset(clearDraft: false);
    }
    setState(() {});
  }

  /// Unlike [_handleAttachmentTap]'s demo attachments, there's nothing to
  /// show optimistically here -- permission + a GPS fix both take a moment,
  /// so the composer's own busy state (driven by [ChatsController.isThreadBusy])
  /// is the only feedback until this resolves.
  Future<void> _shareCurrentLocation(String threadId) async {
    final trimmedCaption = _composerController.text.trim();
    final wasNearLatest = _isNearLatestMessage();

    final outcome = await widget.controller.sendCurrentLocation(
      threadId: threadId,
      caption: trimmedCaption.isEmpty ? null : trimmedCaption,
    );

    if (!mounted) {
      return;
    }

    switch (outcome) {
      case LocationShareOutcome.sent:
        _composerController.clear();
        _scheduleScrollToLatestMessage(animated: !wasNearLatest);
      case LocationShareOutcome.permissionDenied:
        await showLocationPermissionDeniedDialog(
          context,
          onOpenSettings: widget.controller.openLocationSettings,
          message: 'Allow location access to share your current location.',
        );
      case LocationShareOutcome.failed:
        await showLocationErrorDialog(
          context,
          widget.controller.locationFailureMessage ??
              'We could not share your location right now.',
        );
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleAttachmentPreviewTap(
    ChatAttachment attachment, {
    required String threadName,
  }) async {
    // Location attachments now open the same in-app full preview as every
    // other attachment type (a real map with a pin), rather than jumping
    // straight out to an external Maps app -- "Open in Maps" inside that
    // preview (see LocationMapCanvas) is the deliberate exit point.
    await showAttachmentPreview(
      context,
      attachment: attachment,
      threadName: threadName,
    );
  }

  Future<void> _handleSendTap(String threadId) async {
    final draft = _composerController.text;
    final trimmedDraft = draft.trim();
    final wasNearLatest = _isNearLatestMessage();

    if (trimmedDraft.isEmpty) {
      await widget.controller.sendTextMessage(
        threadId: threadId,
        text: draft,
      );
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final localMessage = _buildLocalMessage(
      threadId: threadId,
      text: trimmedDraft,
    );
    _composerUnlockTimer?.cancel();
    _upsertLocalMessage(localMessage);
    _markMessageForAnimation(localMessage.id);
    _composerController.clear();
    _composerLockedMinHeight = null;
    if (mounted) {
      setState(() {});
    }
    _scheduleScrollToLatestMessage(animated: !wasNearLatest);

    final didSend = await widget.controller.sendTextMessage(
      threadId: threadId,
      text: trimmedDraft,
    );

    if (!mounted) {
      return;
    }

    if (!didSend) {
      _upsertLocalMessage(
        localMessage.copyWith(
          deliveryState: MessageDeliveryState.failed,
        ),
      );
    } else {
      _removeLocalMessage(localMessage.id);
      _scheduleScrollToLatestMessage(animated: false);
    }
    setState(() {});
  }

  void _scheduleScrollToLatestMessage({bool animated = true}) {
    _stickToBottom = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToLatestMessage(animated: animated);
    });
  }

  /// Keeps the message list pinned to its true bottom while [_stickToBottom]
  /// is set. Listens for two distinct real signals rather than guessing
  /// with a timer:
  /// - [UserScrollNotification]: a real user drag. Stop pinning unless
  ///   they're still essentially at the bottom (e.g. an over-scroll
  ///   bounce), so a deliberate scroll-up to read history is never fought.
  /// - [ScrollMetricsNotification]: the list's content height actually
  ///   changed (an async image/map/etc. attachment finished laying out)
  ///   without any user scroll -- snap forward to the new true bottom. On
  ///   a thread with several attachments (a map, photos, documents, a
  ///   voice note) the layout can keep growing well past a single guessed
  ///   delay/tolerance, which is exactly what made the previous
  ///   timer-based catch-up undershoot on threads like that.
  bool _handleMessageListNotification(Notification notification) {
    if (notification is UserScrollNotification) {
      if (notification.direction != ScrollDirection.idle) {
        _stickToBottom = _isNearLatestMessage(tolerance: 40);
      }
      return false;
    }
    if (notification is ScrollMetricsNotification) {
      final metrics = notification.metrics;
      final previousMax = _lastObservedMaxScrollExtent;
      _lastObservedMaxScrollExtent = metrics.maxScrollExtent;

      // Only re-snap when content actually grew (an async image/map/etc.
      // finished laying out) while the reader was sitting right at the
      // previous bottom -- never just because pixels doesn't currently
      // equal the max, which is the normal state for a deliberate
      // scroll-up and must never be fought.
      final contentGrew =
          previousMax != null && metrics.maxScrollExtent > previousMax + 0.5;
      final wasAtPreviousBottom =
          previousMax != null && (metrics.pixels - previousMax).abs() <= 40;
      if (_stickToBottom && contentGrew && wasAtPreviousBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _messageListController.hasClients) {
            _messageListController.jumpTo(
              _messageListController.position.maxScrollExtent,
            );
          }
        });
      }
    }
    return false;
  }

  void _lockComposerHeight() {
    _composerUnlockTimer?.cancel();
    final height = _currentComposerHeight;
    if (height == null) {
      return;
    }
    _composerLockedMinHeight = height;
  }

  void _releaseComposerReset() {
    _composerUnlockTimer?.cancel();
    _composerLockedMinHeight = null;
  }

  void _scheduleComposerReset({
    required bool clearDraft,
    bool keepLatestVisible = false,
  }) {
    _composerUnlockTimer?.cancel();
    _composerUnlockTimer = Timer(_sentMessageEntryDuration, () {
      if (!mounted) {
        return;
      }
      setState(() {
        if (clearDraft) {
          _composerController.clear();
        }
        _composerLockedMinHeight = null;
      });
      if (keepLatestVisible) {
        _scheduleScrollToLatestMessage(animated: false);
      }
    });
  }

  void _markMessageForAnimation(String messageId) {
    _animatedMessageCleanupTimer?.cancel();
    _animatedMessageId = messageId;
    _animatedMessageCleanupTimer = Timer(
      _sentMessageEntryDuration + const Duration(milliseconds: 140),
      () {
        if (!mounted || _animatedMessageId != messageId) {
          return;
        }
        setState(() {
          _animatedMessageId = null;
        });
      },
    );
  }

  bool _isNearLatestMessage({double tolerance = 24}) {
    if (!_messageListController.hasClients) {
      return true;
    }
    final latestOffset = _messageListController.position.maxScrollExtent;
    return (_messageListController.offset - latestOffset).abs() <= tolerance;
  }

  double? get _currentComposerHeight {
    final renderObject = _composerBarKey.currentContext?.findRenderObject();
    final renderBox = renderObject is RenderBox ? renderObject : null;
    return renderBox?.size.height;
  }

  List<ChatMessage> _visibleMessagesForThread(ChatThread thread) {
    if (_localMessages.isEmpty) {
      return thread.messages;
    }

    final localMessages = _localMessages.where(
      (message) => !_messageHasPersisted(thread, message),
    );

    return List<ChatMessage>.unmodifiable([
      ...thread.messages,
      ...localMessages,
    ]);
  }

  bool _messageHasPersisted(ChatThread thread, ChatMessage localMessage) {
    if (localMessage.deliveryState != MessageDeliveryState.sending ||
        widget.controller.isThreadBusy(thread.id)) {
      return false;
    }

    final latestRealMessage = thread.latestMessage;
    if (latestRealMessage == null || !latestRealMessage.isFromCurrentUser) {
      return false;
    }

    return latestRealMessage.sentAt.isAfter(
          localMessage.sentAt.subtract(const Duration(seconds: 1)),
        ) &&
        latestRealMessage.text.trim() == localMessage.text.trim() &&
        _sameAttachments(
          latestRealMessage.attachments,
          localMessage.attachments,
        );
  }

  bool _sameAttachments(
    List<ChatAttachment> left,
    List<ChatAttachment> right,
  ) {
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index++) {
      final leftAttachment = left[index];
      final rightAttachment = right[index];
      if (leftAttachment.type != rightAttachment.type ||
          leftAttachment.title != rightAttachment.title ||
          leftAttachment.details != rightAttachment.details) {
        return false;
      }
    }
    return true;
  }

  void _upsertLocalMessage(ChatMessage message) {
    final existingIndex = _localMessages.indexWhere(
      (entry) => entry.id == message.id,
    );
    if (existingIndex == -1) {
      _localMessages.add(message);
      return;
    }

    _localMessages[existingIndex] = message;
  }

  void _removeLocalMessage(String messageId) {
    _localMessages.removeWhere((entry) => entry.id == messageId);
  }

  Future<void> _retryFailedMessage(
    String threadId,
    ChatMessage failedMessage,
  ) async {
    if (widget.controller.isThreadBusy(threadId)) {
      return;
    }

    final sendingMessage = failedMessage.copyWith(
      deliveryState: MessageDeliveryState.sending,
      sentAt: DateTime.now(),
    );
    final wasNearLatest = _isNearLatestMessage();
    widget.controller.clearError();
    _upsertLocalMessage(sendingMessage);
    if (mounted) {
      setState(() {});
    }
    _scheduleScrollToLatestMessage(animated: !wasNearLatest);

    final didSend = failedMessage.hasAttachments
        ? await widget.controller.sendAttachmentMessage(
            threadId: threadId,
            attachments: failedMessage.attachments,
            caption: failedMessage.hasText ? failedMessage.text : null,
          )
        : await widget.controller.sendTextMessage(
            threadId: threadId,
            text: failedMessage.text,
          );

    if (!mounted) {
      return;
    }

    if (didSend) {
      _removeLocalMessage(failedMessage.id);
      _scheduleScrollToLatestMessage(animated: false);
    } else {
      _upsertLocalMessage(
        sendingMessage.copyWith(
          deliveryState: MessageDeliveryState.failed,
        ),
      );
    }
    setState(() {});
  }

  void _scrollToLatestMessage({required bool animated}) {
    if (!mounted || !_messageListController.hasClients) {
      return;
    }

    final targetOffset = _messageListController.position.maxScrollExtent;
    final distance = (_messageListController.offset - targetOffset).abs();
    final shouldAnimate = animated &&
        distance > 24 &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

    if (!shouldAnimate || distance < 2) {
      _messageListController.jumpTo(targetOffset);
      return;
    }

    _messageListController.animateTo(
      targetOffset,
      duration: Duration(milliseconds: distance > 180 ? 220 : 180),
      curve: Curves.easeOutCubic,
    );
  }

  CallContact _callContactForThread(ChatThread thread) {
    return CallContact(
      id: thread.id,
      name: thread.name,
      avatarLabel: thread.avatarLabel,
      accentColor: thread.accentColor,
      isGroup: thread.isGroup,
      uid: thread.participantUid,
    );
  }

  /// Resolves what to actually send for an attachment-sheet tap: photo/video
  /// pick real device media, file opens the document picker, location
  /// shares a real device fix, and voice note opens a real recording sheet
  /// (see [showVoiceNoteRecorderSheet]). Every type uploads to Firebase
  /// Storage on send (see FirestoreChatRepository). Returns null if the
  /// user cancelled.
  Future<List<ChatAttachment>?> _resolveAttachmentsForTap({
    required String threadId,
    required ChatAttachmentType type,
  }) async {
    if (type == ChatAttachmentType.photo) {
      final pickedFiles = await _imagePicker.pickMultiImage();
      if (!mounted || pickedFiles.isEmpty) {
        return null;
      }
      final messageSeed = DateTime.now().millisecondsSinceEpoch;
      return [
        for (var index = 0; index < pickedFiles.length; index++)
          ChatAttachment(
            id: '$threadId-photo-$messageSeed-$index',
            type: ChatAttachmentType.photo,
            title: 'Photo',
            details: '',
            tintColor: AppPalette.green,
            localMediaPath: pickedFiles[index].path,
          ),
      ];
    }

    if (type == ChatAttachmentType.video) {
      final pickedFile =
          await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (!mounted || pickedFile == null) {
        return null;
      }
      return [
        ChatAttachment(
          id: '$threadId-video-${DateTime.now().millisecondsSinceEpoch}',
          type: ChatAttachmentType.video,
          title: 'Video',
          details: '',
          tintColor: AppPalette.sky,
          localMediaPath: pickedFile.path,
        ),
      ];
    }

    if (type == ChatAttachmentType.file) {
      final result = await FilePicker.pickFiles();
      if (!mounted || result == null || result.files.isEmpty) {
        return null;
      }
      final picked = result.files.single;
      final path = picked.path;
      if (path == null) {
        return null;
      }
      return [
        ChatAttachment(
          id: '$threadId-file-${DateTime.now().millisecondsSinceEpoch}',
          type: ChatAttachmentType.file,
          title: picked.name,
          details: '${_formatFileSize(picked.size)} • shared from Files',
          tintColor: AppPalette.amber,
          localMediaPath: path,
        ),
      ];
    }

    final recorded = await showVoiceNoteRecorderSheet(context, threadId: threadId);
    if (!mounted || recorded == null) {
      return null;
    }
    return [recorded];
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  ChatMessage _buildLocalMessage({
    required String threadId,
    required String text,
    List<ChatAttachment> attachments = const <ChatAttachment>[],
  }) {
    return ChatMessage(
      id: '$threadId-local-${DateTime.now().microsecondsSinceEpoch}',
      senderName: 'You',
      sentAt: DateTime.now(),
      isFromCurrentUser: true,
      text: text,
      attachments: List<ChatAttachment>.unmodifiable(attachments),
      deliveryState: MessageDeliveryState.sending,
    );
  }
}

/// Replaces [_ComposerBar] for a blocked contact -- matches its surface
/// color and bottom-safe-area padding exactly (see the composer's own
/// comment on why) so swapping between the two never shows a color seam
/// under the home indicator.
class _BlockedContactBanner extends StatelessWidget {
  const _BlockedContactBanner({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.block_rounded,
            size: 20,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You blocked $name',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.composerBarKey,
    required this.controller,
    required this.isBusy,
    required this.canSendText,
    required this.lockedMinHeight,
    required this.onAttachmentTap,
    required this.onSendTap,
    required this.onChanged,
  });

  final GlobalKey composerBarKey;
  final TextEditingController controller;
  final bool isBusy;
  final bool canSendText;
  final double? lockedMinHeight;
  final ValueChanged<ChatAttachmentType> onAttachmentTap;
  final VoidCallback onSendTap;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Future<void> openAttachmentSheet() async {
      if (isBusy) {
        return;
      }

      // Deliberately not calling FocusScope.unfocus() here -- dismissing
      // the keyboard first meant this popup's position was measured and
      // locked in on the same frame the dismiss animation *started*, while
      // the composer was still at its keyboard-open height. The popup then
      // stayed frozen there as the composer dropped to its resting
      // position underneath it over the next ~250ms, which is exactly the
      // "popup stuck in place while the keyboard closes" gap. Anchoring to
      // wherever the composer currently and stably is -- keyboard open or
      // not -- avoids racing that animation entirely.
      final renderBox =
          composerBarKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached) {
        return;
      }
      final composerTopLeft = renderBox.localToGlobal(Offset.zero);

      const popupWidth = 216.0;
      // 5 rows + 4 hairline dividers -- an estimate (matching the reaction
      // tray's approach), not a measured layout. Positioning from the
      // composer's own top (localToGlobal space) rather than subtracting
      // from MediaQuery.size.height avoids a coordinate-space mismatch
      // when the keyboard is open (view insets shrink MediaQuery.size but
      // not the RenderBox's global offset space).
      const popupHeight = 240.0;
      const popupMargin = 12.0;
      final popupTop = composerTopLeft.dy - popupHeight - popupMargin;

      final selection = await showFloatingGlassPopup<ChatAttachmentType>(
        context,
        barrierLabel: 'Attach',
        scaleAlignment: Alignment.bottomLeft,
        positionedChildBuilder: (overlayContext, close) => Positioned(
          left: 12,
          top: popupTop,
          child: _AttachmentPickerPopup(
            width: popupWidth,
            onSelected: close,
          ),
        ),
      );

      if (selection != null) {
        onAttachmentTap(selection);
      }
    }

    return AnimatedContainer(
      key: composerBarKey,
      duration: _ConversationScreenState._sentMessageEntryDuration,
      curve: Curves.easeOutCubic,
      constraints: lockedMinHeight == null
          ? null
          : BoxConstraints(minHeight: lockedMinHeight!),
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _ComposerIconButton(
            actionKey: const Key('conversation_attachment_menu_button'),
            tooltip: 'Add attachment',
            enabled: !isBusy,
            onTap: openAttachmentSheet,
            icon: Icons.add_rounded,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const Key('conversation_composer_field'),
              controller: controller,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: 'Message',
                isDense: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.22 : 0.4,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          LiquidGlassIconButton(
            actionKey: const Key('conversation_send_button'),
            icon: Icons.send_rounded,
            size: 48,
            blurred: false,
            selected: canSendText,
            iconColor: canSendText
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.34),
            borderColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.34),
            onTap: !isBusy && canSendText ? onSendTap : null,
            child: isBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.icon,
    required this.tooltip,
    required this.actionKey,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Key actionKey;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LiquidGlassIconButton(
      icon: icon,
      tooltip: tooltip,
      actionKey: actionKey,
      size: 44,
      iconSize: 20,
      // Sits on the composer's own opaque surface, not over scrolling
      // content, so no real blur is possible here.
      blurred: false,
      color: enabled
          ? theme.colorScheme.surface
          : theme.colorScheme.surface.withValues(alpha: 0.82),
      borderColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.34),
      iconColor: enabled
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurface.withValues(alpha: 0.34),
      onTap: enabled ? onTap : null,
    );
  }
}

/// A compact floating glass menu (UIMenu-style), anchored just above the
/// composer's attachment button -- replaces the previous full-width
/// [showModalBottomSheet], which looked sparse and padded with only 5
/// options in it.
class _AttachmentPickerPopup extends StatelessWidget {
  const _AttachmentPickerPopup({required this.width, required this.onSelected});

  final double width;
  final ValueChanged<ChatAttachmentType> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = <_AttachmentActionData>[
      _AttachmentActionData(
        actionKey: const Key('conversation_photo_button'),
        icon: Icons.photo_library_outlined,
        color: AppPalette.green,
        label: 'Photo',
        type: ChatAttachmentType.photo,
      ),
      _AttachmentActionData(
        actionKey: const Key('conversation_video_button'),
        icon: Icons.videocam_outlined,
        color: AppPalette.sky,
        label: 'Video',
        type: ChatAttachmentType.video,
      ),
      _AttachmentActionData(
        actionKey: const Key('conversation_file_button'),
        icon: Icons.attach_file_rounded,
        color: AppPalette.amber,
        label: 'Document',
        type: ChatAttachmentType.file,
      ),
      _AttachmentActionData(
        actionKey: const Key('conversation_location_button'),
        icon: Icons.location_on_outlined,
        color: AppPalette.rose,
        label: 'Location',
        type: ChatAttachmentType.location,
      ),
      _AttachmentActionData(
        actionKey: const Key('conversation_voice_button'),
        icon: Icons.mic_none_rounded,
        color: AppPalette.purple,
        label: 'Voice',
        type: ChatAttachmentType.voiceNote,
      ),
    ];

    return LiquidGlassSurface(
      key: const Key('conversation_attachment_sheet'),
      borderRadius: BorderRadius.circular(16),
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 52,
                  color: theme.colorScheme.outlineVariant
                      .withValues(alpha: 0.24),
                ),
              _AttachmentPopupRow(
                actionKey: options[i].actionKey,
                icon: options[i].icon,
                color: options[i].color,
                label: options[i].label,
                onTap: () => onSelected(options[i].type),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttachmentPopupRow extends StatelessWidget {
  const _AttachmentPopupRow({
    required this.actionKey,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final Key actionKey;
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: actionKey,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 14),
              Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentActionData {
  const _AttachmentActionData({
    required this.actionKey,
    required this.icon,
    required this.color,
    required this.label,
    required this.type,
  });

  final Key actionKey;
  final IconData icon;
  final Color color;
  final String label;
  final ChatAttachmentType type;
}

class _AnimatedMessageEntry extends StatefulWidget {
  const _AnimatedMessageEntry({
    required this.animateOnMount,
    required this.isMine,
    required this.child,
    super.key,
  });

  final bool animateOnMount;
  final bool isMine;
  final Widget child;

  @override
  State<_AnimatedMessageEntry> createState() => _AnimatedMessageEntryState();
}

class _AnimatedMessageEntryState extends State<_AnimatedMessageEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _ConversationScreenState._sentMessageEntryDuration,
      value: widget.animateOnMount ? 0 : 1,
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.18, 1, curve: Curves.easeOut),
    );
    _offset = Tween<Offset>(
      begin: Offset(widget.isMine ? 0.02 : -0.02, 0.03),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _scale = Tween<double>(
      begin: 0.985,
      end: 1,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    if (widget.animateOnMount) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedMessageEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.animateOnMount && widget.animateOnMount) {
      _controller
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: ScaleTransition(
          scale: _scale,
          alignment:
              widget.isMine ? Alignment.bottomRight : Alignment.bottomLeft,
          child: widget.child,
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.thread,
    required this.message,
    required this.onAttachmentTap,
    required this.onReactionTap,
    this.onRetryTap,
  });

  final ChatThread thread;
  final ChatMessage message;
  final ValueChanged<ChatAttachment> onAttachmentTap;
  final ValueChanged<String> onReactionTap;
  final VoidCallback? onRetryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMine = message.isFromCurrentUser;
    final isFailed = message.deliveryState == MessageDeliveryState.failed;
    final baseBubbleColor = isMine
        ? theme.colorScheme.primaryContainer.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.52 : 0.9,
          )
        : theme.colorScheme.surfaceContainerLow;
    final bubbleColor = isMine
        ? isFailed
            ? theme.colorScheme.errorContainer
            : baseBubbleColor
        : baseBubbleColor;
    final contentColor = isMine
        ? isFailed
            ? theme.colorScheme.onErrorContainer
            : theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: alignment,
      // A Builder here (rather than reading `context` from this outer
      // `build`) matters: this method's own `context` resolves through
      // `Align` first, whose render box stretches to the full row width --
      // using it for `_showReactionTray`'s position math would size the
      // tray/badge off the whole row instead of the actual bubble.
      child: Builder(
        builder: (bubbleContext) {
          return GestureDetector(
            onLongPress: () => _showReactionTray(bubbleContext, isMine: isMine),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Container(
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      border: Border.all(
                        color: isFailed
                            ? theme.colorScheme.error.withValues(alpha: 0.22)
                            : isMine
                                ? theme.colorScheme.primary
                                    .withValues(alpha: 0.14)
                                : theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.18),
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isMine ? 20 : 6),
                        bottomRight: Radius.circular(isMine ? 6 : 20),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (thread.isGroup && !isMine)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              message.senderName,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: thread.accentColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        if (message.hasAttachments) ...[
                          _buildAttachmentsContent(context),
                          const SizedBox(height: 10),
                        ],
                        if (message.hasText)
                          Text(
                            message.text,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: contentColor,
                              height: 1.36,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _timeLabelFor(message.sentAt),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: contentColor.withValues(alpha: 0.75),
                              ),
                            ),
                            if (isMine) ...[
                              const SizedBox(width: 6),
                              Icon(
                                _deliveryIcon(message.deliveryState),
                                size: 16,
                                color: switch (message.deliveryState) {
                                  MessageDeliveryState.read => AppPalette.green,
                                  MessageDeliveryState.failed =>
                                    theme.colorScheme.error,
                                  _ => contentColor.withValues(alpha: 0.78),
                                },
                              ),
                            ],
                          ],
                        ),
                        if (isMine && isFailed) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 16,
                                color: theme.colorScheme.error,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Not sent',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                key: Key(
                                    'conversation_retry_button_${message.id}'),
                                onPressed: onRetryTap,
                                style: TextButton.styleFrom(
                                  foregroundColor: theme.colorScheme.error,
                                  minimumSize: Size.zero,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (message.hasReactions)
                  Positioned(
                    bottom: -12,
                    right: isMine ? 8 : null,
                    left: isMine ? null : 8,
                    child: _ReactionBadge(reactions: message.reactions),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showReactionTray(
    BuildContext bubbleContext, {
    required bool isMine,
  }) async {
    final renderBox = bubbleContext.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) {
      return;
    }
    final bubbleTopLeft = renderBox.localToGlobal(Offset.zero);
    final bubbleSize = renderBox.size;
    final mediaQuery = MediaQuery.of(bubbleContext);
    final screenSize = mediaQuery.size;

    const trayHeight = 56.0;
    // 6 emoji options at 44pt each (see _ReactionTray's tap targets) plus
    // LiquidGlassSurface's own 8pt horizontal padding on each side.
    const trayWidth = 280.0;
    const trayMargin = 10.0;
    final showAbove =
        bubbleTopLeft.dy - trayHeight - trayMargin > mediaQuery.padding.top + 8;
    final trayTop = showAbove
        ? bubbleTopLeft.dy - trayHeight - trayMargin
        : bubbleTopLeft.dy + bubbleSize.height + trayMargin;
    final rawTrayLeft = isMine
        ? bubbleTopLeft.dx + bubbleSize.width - trayWidth
        : bubbleTopLeft.dx;
    final trayLeft =
        rawTrayLeft.clamp(12.0, screenSize.width - trayWidth - 12.0);

    final selectedEmoji = await showFloatingGlassPopup<String>(
      bubbleContext,
      barrierLabel: 'Reactions',
      scaleAlignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      positionedChildBuilder: (overlayContext, close) => Positioned(
        left: trayLeft,
        top: trayTop,
        child: _ReactionTray(
          onSelected: close,
        ),
      ),
    );

    if (selectedEmoji != null) {
      onReactionTap(selectedEmoji);
    }
  }

  /// Photo/video attachments render full-bleed (a grid when more than one
  /// photo was sent together); a single location attachment with a real fix
  /// renders a real map snippet with a pin; file/voice-note attachments (and
  /// anything without real coordinates/media) keep the icon+title+details
  /// row -- see docs on [_AttachmentPreviewCard], [_MediaAttachmentTile],
  /// and [LocationMapSnippet].
  Widget _buildAttachmentsContent(BuildContext context) {
    final attachments = message.attachments;
    final isMediaGroup = attachments.every(
      (attachment) =>
          attachment.type == ChatAttachmentType.photo ||
          attachment.type == ChatAttachmentType.video ||
          attachment.isImageDocument,
    );

    if (isMediaGroup && attachments.length > 1) {
      return _AttachmentPhotoGrid(
        attachments: attachments,
        onAttachmentTap: onAttachmentTap,
      );
    }

    if (isMediaGroup && attachments.length == 1) {
      final attachment = attachments.single;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: _MediaAttachmentTile(
          attachment: attachment,
          onTap: () => onAttachmentTap(attachment),
        ),
      );
    }

    if (attachments.length == 1 &&
        attachments.single.type == ChatAttachmentType.location &&
        attachments.single.hasCoordinates) {
      final attachment = attachments.single;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('attachment_preview_${attachment.id}'),
              onTap: () => onAttachmentTap(attachment),
              child: LocationMapSnippet(
                latitude: attachment.latitude!,
                longitude: attachment.longitude!,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final attachment in attachments)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _buildAttachmentRow(attachment),
          ),
      ],
    );
  }

  /// A real voice note (a real recorded file, not a placeholder) renders as
  /// an inline playable bubble instead of a tap-through row -- everything
  /// else keeps [_AttachmentPreviewCard]'s icon+title+details row.
  Widget _buildAttachmentRow(ChatAttachment attachment) {
    final localPath = attachment.localMediaPath;
    if (attachment.type == ChatAttachmentType.voiceNote &&
        localPath != null &&
        statusMediaSourceExists(localPath)) {
      return VoiceNoteBubble(
        key: Key('voice_note_${attachment.id}'),
        localMediaPath: localPath,
        fallbackLabel: attachment.details,
        accentColor: attachment.tintColor,
      );
    }
    return _AttachmentPreviewCard(
      attachment: attachment,
      onTap: () => onAttachmentTap(attachment),
    );
  }

  IconData _deliveryIcon(MessageDeliveryState state) {
    return switch (state) {
      MessageDeliveryState.sending => Icons.schedule_rounded,
      MessageDeliveryState.sent => Icons.check_rounded,
      MessageDeliveryState.delivered => Icons.done_all_rounded,
      MessageDeliveryState.read => Icons.done_all_rounded,
      MessageDeliveryState.failed => Icons.error_outline_rounded,
    };
  }
}

/// The floating glass reaction picker shown on long-press, in the style of
/// iMessage's Tapback tray -- a horizontal row of quick-react emojis
/// pinned near the bubble rather than WhatsApp's flatter below-bubble row.
class _ReactionTray extends StatelessWidget {
  const _ReactionTray({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final emoji in kQuickReactionEmojis)
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                key: Key('reaction_option_$emoji'),
                customBorder: const CircleBorder(),
                onTap: () => onSelected(emoji),
                // Minimum 44x44pt tap target (docs/ui_layout_guidelines.md
                // rule 7) -- the previous Padding(6) around a 24px glyph
                // gave each of these six tightly-packed circles only ~36px,
                // easy for a real finger to miss even though it looked
                // tappable, unlike a widget test's exact-center tap.
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The small badge overlapping a bubble's bottom corner once it has at
/// least one reaction -- shows every distinct emoji used (deduped; several
/// people reacting with the same emoji still shows it once).
class _ReactionBadge extends StatelessWidget {
  const _ReactionBadge({required this.reactions});

  final Map<String, String> reactions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distinctEmojis = reactions.values.toSet().toList(growable: false);

    return LiquidGlassSurface(
      blurred: false,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final emoji in distinctEmojis)
            Text(emoji, style: const TextStyle(fontSize: 13)),
          if (reactions.length > 1) ...[
            const SizedBox(width: 3),
            Text(
              '${reactions.length}',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A 2-column grid of full-bleed photo tiles for a message that bundles
/// several photos together (e.g. picked via a multi-select gallery pick),
/// matching how WhatsApp/iMessage group multiple photos into one bubble
/// instead of stacking separate bubbles.
class _AttachmentPhotoGrid extends StatelessWidget {
  const _AttachmentPhotoGrid({
    required this.attachments,
    required this.onAttachmentTap,
  });

  final List<ChatAttachment> attachments;
  final ValueChanged<ChatAttachment> onAttachmentTap;

  @override
  Widget build(BuildContext context) {
    const spacing = 4.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final attachment in attachments)
              SizedBox(
                width: tileWidth,
                child: _MediaAttachmentTile(
                  attachment: attachment,
                  aspectRatio: 1,
                  onTap: () => onAttachmentTap(attachment),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A single full-bleed photo or video tile -- no title/subtitle text, the
/// media itself fills the bubble (matching the reference WhatsApp/iMessage
/// bubble style). Real photos render via [imageProviderForStatusMediaPath];
/// video shows a real first-frame thumbnail via [videoThumbnailFor], with a
/// play affordance overlaid on top. Falls back to a tinted swatch with a
/// type icon when there's no local media to show yet (a demo attachment,
/// media missing on this device/other participant's device, or while the
/// video thumbnail is still generating).
class _MediaAttachmentTile extends StatelessWidget {
  const _MediaAttachmentTile({
    required this.attachment,
    required this.onTap,
    this.aspectRatio,
  });

  final ChatAttachment attachment;
  final VoidCallback onTap;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final localPath = attachment.localMediaPath;
    final isPhoto =
        attachment.type == ChatAttachmentType.photo || attachment.isImageDocument;
    final hasRealPhoto =
        isPhoto && localPath != null && statusMediaSourceExists(localPath);
    final hasRealVideo = attachment.type == ChatAttachmentType.video &&
        localPath != null &&
        statusMediaSourceExists(localPath);
    final resolvedAspectRatio =
        (aspectRatio ?? attachment.aspectRatio).clamp(0.7, 1.5);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('attachment_preview_${attachment.id}'),
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: resolvedAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasRealPhoto)
                  Image(
                    image: imageProviderForStatusMediaPath(localPath)!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  )
                else if (hasRealVideo)
                  FutureBuilder<Uint8List?>(
                    future: videoThumbnailFor(localPath),
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      if (bytes == null) {
                        return _placeholder();
                      }
                      return Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      );
                    },
                  )
                else
                  _placeholder(),
                if (attachment.type == ChatAttachmentType.video)
                  Center(
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 26,
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

  Widget _placeholder() {
    return ColoredBox(
      color: attachment.tintColor.withValues(alpha: 0.18),
      child: Center(
        child: Icon(
          attachment.type == ChatAttachmentType.video
              ? Icons.videocam_outlined
              : Icons.photo_outlined,
          color: attachment.tintColor,
          size: 32,
        ),
      ),
    );
  }
}

class _AttachmentPreviewCard extends StatelessWidget {
  const _AttachmentPreviewCard({
    required this.attachment,
    required this.onTap,
  });

  final ChatAttachment attachment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(16);
    final (icon, iconColor) = _iconAndColor(attachment);

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        key: Key('attachment_preview_${attachment.id}'),
        onTap: onTap,
        borderRadius: borderRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: iconColor.withValues(alpha: 0.16),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      attachment.details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.68),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                attachment.type == ChatAttachmentType.location
                    ? Icons.north_east_rounded
                    : Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color) _iconAndColor(ChatAttachment attachment) {
    if (attachment.type == ChatAttachmentType.file) {
      return documentKindVisual(attachment.documentKind, attachment.tintColor);
    }
    final icon = switch (attachment.type) {
      ChatAttachmentType.photo => Icons.photo_outlined,
      ChatAttachmentType.video => Icons.videocam_outlined,
      ChatAttachmentType.location => Icons.location_on_outlined,
      ChatAttachmentType.voiceNote => Icons.graphic_eq_rounded,
      ChatAttachmentType.file => Icons.insert_drive_file_outlined,
    };
    return (icon, attachment.tintColor);
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.34 : 0.72,
        ),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.18),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _dayLabelFor(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final difference = today.difference(target).inDays;

  if (difference == 0) {
    return 'Today';
  }
  if (difference == 1) {
    return 'Yesterday';
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

String _timeLabelFor(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}
