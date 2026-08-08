import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/status_story.dart';
import '../../../core/permissions/location_permission_dialog.dart';
import '../../calls/application/calls_controller.dart';
import '../../calls/domain/call_contact.dart';
import '../../calls/domain/call_history_entry.dart';
import '../../calls/presentation/call_flow.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/liquid_glass.dart';
import '../../updates/application/updates_controller.dart';
import '../../updates/presentation/story_viewer_launcher.dart';
import '../../updates/presentation/widgets/status_ring_avatar.dart';
import '../application/chats_controller.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_message.dart';
import '../domain/chat_thread.dart';
import 'attachment_viewer_screen.dart';

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
                            totalSegments: story?.totalSegments ?? 1,
                            seenSegments: story?.clampedSeenSegments ?? 0,
                            size: 44,
                          )
                        : AvatarBadge(
                            label: thread.avatarLabel,
                            color: thread.accentColor,
                            size: 44,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
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
                if (widget.controller.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: _InlineConversationError(
                      message: widget.controller.errorMessage!,
                      onDismiss: widget.controller.clearError,
                    ),
                  ),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(
                        alpha:
                            theme.brightness == Brightness.dark ? 0.94 : 0.98,
                      ),
                    ),
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
                _ComposerBar(
                  composerBarKey: _composerBarKey,
                  controller: _composerController,
                  isBusy: composerInteractionsLocked,
                  canSendText: canSendText,
                  lockedMinHeight: _composerLockedMinHeight,
                  onEmojiTap: () {
                    final current = _composerController.text;
                    final nextValue = current.isEmpty ? '😊' : '$current 😊';
                    _composerController.value = TextEditingValue(
                      text: nextValue,
                      selection:
                          TextSelection.collapsed(offset: nextValue.length),
                    );
                    setState(() {});
                  },
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

  Future<void> _handleAttachmentTap(
    String threadId,
    ChatAttachmentType type,
  ) async {
    if (type == ChatAttachmentType.location) {
      await _shareCurrentLocation(threadId);
      return;
    }

    final trimmedCaption = _composerController.text.trim();
    final wasNearLatest = _isNearLatestMessage();
    final attachment = _buildDemoAttachment(
      threadId: threadId,
      type: type,
    );
    final localMessage = _buildLocalMessage(
      threadId: threadId,
      text: trimmedCaption,
      attachments: <ChatAttachment>[attachment],
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
      attachment: attachment,
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
    if (attachment.type == ChatAttachmentType.location &&
        attachment.hasCoordinates) {
      final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query='
        '${attachment.latitude},${attachment.longitude}',
      );
      final didLaunch = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!didLaunch && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('We could not open Maps for that location.'),
          ),
        );
      }
      return;
    }

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToLatestMessage(animated: animated);
    });
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
            attachment: failedMessage.attachments.first,
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

  ChatAttachment _buildDemoAttachment({
    required String threadId,
    required ChatAttachmentType type,
  }) {
    final messageSeed = DateTime.now().millisecondsSinceEpoch;
    return switch (type) {
      ChatAttachmentType.photo => ChatAttachment(
          id: '$threadId-photo-$messageSeed',
          type: ChatAttachmentType.photo,
          title: 'New gallery pick',
          details: 'High-resolution photo preview',
          tintColor: AppPalette.green,
          aspectRatio: 1.05,
        ),
      ChatAttachmentType.video => ChatAttachment(
          id: '$threadId-video-$messageSeed',
          type: ChatAttachmentType.video,
          title: 'Walkthrough clip',
          details: '0:18 preview video',
          tintColor: AppPalette.sky,
          aspectRatio: 0.7,
        ),
      ChatAttachmentType.file => ChatAttachment(
          id: '$threadId-file-$messageSeed',
          type: ChatAttachmentType.file,
          title: 'Release-Notes.pdf',
          details: '268 KB • shared from Files',
          tintColor: AppPalette.amber,
          aspectRatio: 1.3,
        ),
      ChatAttachmentType.location => ChatAttachment(
          id: '$threadId-location-$messageSeed',
          type: ChatAttachmentType.location,
          title: 'Shibuya Crossing',
          details: 'Pinned location • Tokyo meetup point',
          tintColor: AppPalette.rose,
          aspectRatio: 1.18,
        ),
      ChatAttachmentType.voiceNote => ChatAttachment(
          id: '$threadId-voice-$messageSeed',
          type: ChatAttachmentType.voiceNote,
          title: 'Voice note',
          details: '0:21 quick update',
          tintColor: AppPalette.purple,
          aspectRatio: 1.55,
        ),
    };
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

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.composerBarKey,
    required this.controller,
    required this.isBusy,
    required this.canSendText,
    required this.lockedMinHeight,
    required this.onEmojiTap,
    required this.onAttachmentTap,
    required this.onSendTap,
    required this.onChanged,
  });

  final GlobalKey composerBarKey;
  final TextEditingController controller;
  final bool isBusy;
  final bool canSendText;
  final double? lockedMinHeight;
  final VoidCallback onEmojiTap;
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

      FocusScope.of(context).unfocus();
      final selection = await showModalBottomSheet<ChatAttachmentType>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (sheetContext) => _AttachmentPickerSheet(
          onSelected: (type) => Navigator.of(sheetContext).pop(type),
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
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 44, minHeight: 44),
                prefixIcon: IconButton(
                  key: const Key('conversation_emoji_button'),
                  onPressed: isBusy ? null : onEmojiTap,
                  icon: const Icon(Icons.emoji_emotions_outlined),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            key: const Key('conversation_send_button'),
            onPressed: !isBusy && canSendText ? onSendTap : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            child: isBusy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.send_rounded),
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

class _AttachmentPickerSheet extends StatelessWidget {
  const _AttachmentPickerSheet({required this.onSelected});

  final ValueChanged<ChatAttachmentType> onSelected;

  @override
  Widget build(BuildContext context) {
    final isCompactHeight = MediaQuery.sizeOf(context).height <= 700;
    final horizontalPadding = isCompactHeight ? 18.0 : 20.0;
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

    return Padding(
      key: const Key('conversation_attachment_sheet'),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        isCompactHeight ? 12 : 18,
        horizontalPadding,
        isCompactHeight ? 20 : 28,
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: isCompactHeight ? 20 : 26,
        runSpacing: 18,
        children: [
          for (final option in options)
            _AttachmentGridTile(
              actionKey: option.actionKey,
              icon: option.icon,
              color: option.color,
              tooltip: option.label,
              isCompact: isCompactHeight,
              onTap: () => onSelected(option.type),
            ),
        ],
      ),
    );
  }
}

class _AttachmentGridTile extends StatelessWidget {
  const _AttachmentGridTile({
    required this.actionKey,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.isCompact,
    required this.onTap,
  });

  final Key actionKey;
  final IconData icon;
  final Color color;
  final String tooltip;
  final bool isCompact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = isCompact ? 52.0 : 58.0;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.14),
        shape: const CircleBorder(),
        child: InkWell(
          key: actionKey,
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: color, size: isCompact ? 24 : 26),
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

class _InlineConversationError extends StatelessWidget {
  const _InlineConversationError({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.14),
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
            onPressed: onDismiss,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
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
    this.onRetryTap,
  });

  final ChatThread thread;
  final ChatMessage message;
  final ValueChanged<ChatAttachment> onAttachmentTap;
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          decoration: BoxDecoration(
            color: bubbleColor,
            border: Border.all(
              color: isFailed
                  ? theme.colorScheme.error.withValues(alpha: 0.22)
                  : isMine
                      ? theme.colorScheme.primary.withValues(alpha: 0.14)
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
              if (message.hasAttachments)
                ...message.attachments.map(
                  (attachment) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AttachmentPreviewCard(
                      attachment: attachment,
                      onTap: () => onAttachmentTap(attachment),
                    ),
                  ),
                ),
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
                        MessageDeliveryState.failed => theme.colorScheme.error,
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
                      key: Key('conversation_retry_button_${message.id}'),
                      onPressed: onRetryTap,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                backgroundColor: attachment.tintColor.withValues(alpha: 0.16),
                child: Icon(
                  _iconForType(attachment.type),
                  color: attachment.tintColor,
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
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.68),
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

  IconData _iconForType(ChatAttachmentType type) {
    return switch (type) {
      ChatAttachmentType.photo => Icons.photo_outlined,
      ChatAttachmentType.video => Icons.videocam_outlined,
      ChatAttachmentType.file => Icons.insert_drive_file_outlined,
      ChatAttachmentType.location => Icons.location_on_outlined,
      ChatAttachmentType.voiceNote => Icons.graphic_eq_rounded,
    };
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
