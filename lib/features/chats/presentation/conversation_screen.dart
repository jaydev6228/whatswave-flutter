import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/status_story.dart';
import '../../../core/permissions/location_permission_dialog.dart';
import '../../calls/application/calls_controller.dart';
import '../../calls/domain/call_contact.dart';
import '../../calls/domain/call_history_entry.dart';
import '../../calls/presentation/call_flow.dart';
import '../../communities/application/communities_controller.dart';
import '../../shared/widgets/thread_avatar.dart';
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
import '../domain/message_reply_preview.dart';
import '../domain/story_reply_context.dart';
import 'attachment_viewer_screen.dart';
import 'contact_info_screen.dart';
import 'forward_message_screen.dart';
import 'media_send_preview_screen.dart';
import 'widgets/emoji_reaction_picker_screen.dart';
import 'widgets/location_map_preview.dart';
import 'widgets/video_thumbnail_source.dart';
import 'widgets/voice_note_bubble.dart';
import 'widgets/voice_note_recorder_sheet.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    required this.callsController,
    required this.controller,
    required this.updatesController,
    required this.communitiesController,
    required this.threadId,
    super.key,
  });

  final CallsController callsController;
  final ChatsController controller;
  final UpdatesController updatesController;
  final CommunitiesController communitiesController;
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

  /// A GlobalKey per message, keyed by id and never removed once created --
  /// lets a reply's quote card (see [_jumpToMessage]) scroll to an
  /// arbitrary earlier message via [Scrollable.ensureVisible] instead of
  /// only ever being able to jump to the list's bottom.
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};

  String? _highlightedMessageId;
  Timer? _highlightClearTimer;

  /// Set by [MessageAction.reply] -- a snapshot of the message being
  /// replied to, shown as a dismissible bar above the composer while it's
  /// set, and attached to the next message sent.
  MessageReplyPreview? _pendingReply;
  late final FocusNode _composerFocusNode;

  /// Non-empty while in multi-select mode (entered via [MessageAction.select]
  /// or long-pressing an already-selected bubble) -- the app bar swaps to a
  /// "N selected" bulk-action toolbar and tapping any bubble toggles its
  /// membership instead of the bubble's normal tap behavior.
  final Set<String> _selectedMessageIds = <String>{};
  bool get _isSelecting => _selectedMessageIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _composerController = TextEditingController();
    _messageListController = ScrollController();
    _composerFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _composerUnlockTimer?.cancel();
    _animatedMessageCleanupTimer?.cancel();
    _highlightClearTimer?.cancel();
    _composerController.dispose();
    _messageListController.dispose();
    _composerFocusNode.dispose();
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
            leading: _isSelecting
                ? IconButton(
                    key: const Key('conversation_selection_close_button'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _exitSelection,
                  )
                : null,
            // Fixed-height chrome (the toolbar) with a two-line title stack
            // -- clamp text scale so it can't outgrow that height at large
            // accessibility scale. See docs/ui_layout_guidelines.md rule 4.
            title: _isSelecting
                ? Text('${_selectedMessageIds.length} selected')
                : MediaQuery.withClampedTextScaling(
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
                              : ThreadAvatar(
                                  thread: thread,
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
            actions: _isSelecting
                ? [
                    if (_selectedMessagesInOrder(visibleMessages).length == 1 &&
                        _selectedMessagesInOrder(visibleMessages)
                            .single
                            .hasText)
                      IconButton(
                        key: const Key('conversation_selection_copy_button'),
                        icon: const Icon(Icons.content_copy_rounded),
                        onPressed: () => _copySelectedMessage(visibleMessages),
                      ),
                    IconButton(
                      key: const Key('conversation_selection_forward_button'),
                      icon: const Icon(Icons.forward_rounded),
                      onPressed: () =>
                          _forwardSelectedMessages(thread, visibleMessages),
                    ),
                    IconButton(
                      key: const Key('conversation_selection_star_button'),
                      icon: const Icon(Icons.star_border_rounded),
                      onPressed: () => _starSelectedMessages(visibleMessages),
                    ),
                    IconButton(
                      key: const Key('conversation_selection_delete_button'),
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => _deleteSelectedMessages(visibleMessages),
                    ),
                    const SizedBox(width: 4),
                  ]
                : [
                    LiquidGlassIconButton(
                      icon: Icons.call_outlined,
                      tooltip: 'Audio call',
                      // The tap target still clamps up to the 48dp minimum
                      // (see LiquidGlassIconButton), but the drawn glass
                      // circle is now visibly smaller than the 44pt header
                      // avatar instead of matching/exceeding it, so the
                      // avatar reads as the header's primary element.
                      size: 44,
                      visualSize: 34,
                      // The app bar is a fixed, non-overlapping toolbar here
                      // (not a floating sliver over scrolling content), so
                      // there is no real content behind it for a blur to
                      // reveal.
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
                    const SizedBox(width: 4),
                    LiquidGlassIconButton(
                      icon: Icons.videocam_outlined,
                      tooltip: 'Video call',
                      size: 44,
                      visualSize: 34,
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

                            return KeyedSubtree(
                              key: _messageKeys.putIfAbsent(
                                message.id,
                                GlobalKey.new,
                              ),
                              child: Column(
                                children: [
                                  if (shouldShowDayChip)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 14),
                                      child: _DayDivider(
                                          label: _dayLabelFor(message.sentAt)),
                                    ),
                                  _AnimatedMessageEntry(
                                    key: ValueKey(
                                        'conversation_message_${message.id}'),
                                    animateOnMount:
                                        message.id == _animatedMessageId,
                                    isMine: message.isFromCurrentUser,
                                    child: _MessageBubble(
                                      thread: thread,
                                      message: message,
                                      isHighlighted:
                                          message.id == _highlightedMessageId,
                                      onRetryTap: message.isFromCurrentUser &&
                                              message.deliveryState ==
                                                  MessageDeliveryState.failed &&
                                              _localMessages.any(
                                                (localMessage) =>
                                                    localMessage.id ==
                                                    message.id,
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
                                      onAction: (action) =>
                                          _handleMessageAction(
                                        action,
                                        thread: thread,
                                        message: message,
                                      ),
                                      isStoryReplyAvailable:
                                          _isStoryReplyAvailable(message),
                                      onStoryReplyCardTap:
                                          message.hasStoryReplyContext
                                              ? () => _openStoryReplyCard(
                                                    message.storyReplyContext!,
                                                  )
                                              : null,
                                      onReplyPreviewTap: _jumpToMessage,
                                      isSelectionMode: _isSelecting,
                                      isSelected: _selectedMessageIds
                                          .contains(message.id),
                                      onToggleSelection: () =>
                                          _toggleMessageSelection(message.id),
                                    ),
                                  ),
                                  if (index != visibleMessages.length - 1)
                                    // A reacted message's badge hangs 20px below
                                    // its own bubble (see the Positioned(bottom:
                                    // -20) above) -- needs real clearance from the
                                    // next bubble instead of touching it.
                                    SizedBox(
                                        height: message.hasReactions ? 30 : 12),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                if (thread.isBlocked)
                  _BlockedContactBanner(name: thread.name)
                else ...[
                  if (_pendingReply != null)
                    _ReplyPreviewBar(
                      replyPreview: _pendingReply!,
                      onCancel: _cancelReply,
                    ),
                  _ComposerBar(
                    composerBarKey: _composerBarKey,
                    controller: _composerController,
                    focusNode: _composerFocusNode,
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
      chatsController: widget.controller,
    );
  }

  bool _isStoryReplyAvailable(ChatMessage message) {
    final replyContext = message.storyReplyContext;
    if (replyContext == null) {
      return false;
    }
    return widget.updatesController
            .storyForOwnerUid(replyContext.storyOwnerUid) !=
        null;
  }

  Future<void> _openStoryReplyCard(StoryReplyContext replyContext) async {
    final story =
        widget.updatesController.storyForOwnerUid(replyContext.storyOwnerUid);
    if (story == null) {
      return;
    }
    await openStatusStoryViewer(
      context,
      controller: widget.updatesController,
      story: story,
      chatsController: widget.controller,
    );
  }

  void _jumpToMessage(String messageId) {
    final key = _messageKeys[messageId];
    final targetContext = key?.currentContext;
    if (targetContext == null) {
      return;
    }
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    _highlightClearTimer?.cancel();
    setState(() => _highlightedMessageId = messageId);
    _highlightClearTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  Future<void> _openContactInfo(String threadId) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContactInfoScreen(
          controller: widget.controller,
          communitiesController: widget.communitiesController,
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

    var pickedAttachments = await _resolveAttachmentsForTap(
      threadId: threadId,
      type: type,
    );
    if (!mounted || pickedAttachments == null || pickedAttachments.isEmpty) {
      return;
    }

    var caption = _composerController.text.trim();

    // Photo/video get a WhatsApp-style review step first -- caption, rotate,
    // and color-pencil markup -- instead of sending the instant they're
    // picked. Other attachment types (file/location/voice note) still send
    // immediately; none of them have a meaningful visual preview/edit step.
    if (type == ChatAttachmentType.photo || type == ChatAttachmentType.video) {
      final draft = await Navigator.of(context).push<MediaSendDraft>(
        MaterialPageRoute<MediaSendDraft>(
          builder: (_) => MediaSendPreviewScreen(
            attachments: pickedAttachments!,
            initialCaption: caption.isEmpty ? null : caption,
          ),
          fullscreenDialog: true,
        ),
      );
      if (!mounted || draft == null) {
        // Cancelled from the preview screen -- nothing was sent.
        return;
      }
      pickedAttachments = draft.attachments;
      caption = draft.caption?.trim() ?? '';
    }

    final attachments = pickedAttachments;
    final trimmedCaption = caption;
    final wasNearLatest = _isNearLatestMessage();
    final replyPreview = _pendingReply;
    final localMessage = _buildLocalMessage(
      threadId: threadId,
      text: trimmedCaption,
      attachments: attachments,
      replyPreview: replyPreview,
    );

    _lockComposerHeight();
    _upsertLocalMessage(localMessage);
    _markMessageForAnimation(localMessage.id);
    _composerController.clear();
    _pendingReply = null;
    if (mounted) {
      setState(() {});
    }
    _scheduleScrollToLatestMessage(animated: !wasNearLatest);

    final didSend = await widget.controller.sendAttachmentMessage(
      threadId: threadId,
      attachments: attachments,
      caption: trimmedCaption.isEmpty ? null : trimmedCaption,
      replyPreview: replyPreview,
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

    final replyPreview = _pendingReply;
    final localMessage = _buildLocalMessage(
      threadId: threadId,
      text: trimmedDraft,
      replyPreview: replyPreview,
    );
    _composerUnlockTimer?.cancel();
    _upsertLocalMessage(localMessage);
    _markMessageForAnimation(localMessage.id);
    _composerController.clear();
    _composerLockedMinHeight = null;
    _pendingReply = null;
    if (mounted) {
      setState(() {});
    }
    _scheduleScrollToLatestMessage(animated: !wasNearLatest);

    final didSend = await widget.controller.sendTextMessage(
      threadId: threadId,
      text: trimmedDraft,
      replyPreview: replyPreview,
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

  Future<void> _handleMessageAction(
    MessageAction action, {
    required ChatThread thread,
    required ChatMessage message,
  }) async {
    switch (action) {
      case MessageAction.reply:
        _startReplyingTo(message);
      case MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Copied to clipboard')),
          );
        }
      case MessageAction.forward:
        await _forwardMessage(thread, message);
      case MessageAction.star:
        await widget.controller.toggleMessageStar(
          threadId: thread.id,
          messageId: message.id,
        );
      case MessageAction.edit:
        await _editMessage(thread, message);
      case MessageAction.select:
        _startSelecting(message.id);
      case MessageAction.deleteForMe:
        await _confirmDeleteMessage(thread, message, forEveryone: false);
      case MessageAction.deleteForEveryone:
        await _confirmDeleteMessage(thread, message, forEveryone: true);
      case MessageAction.save:
        await _saveMessageMedia(message);
    }
  }

  void _startReplyingTo(ChatMessage message) {
    setState(() {
      _pendingReply = MessageReplyPreview(
        messageId: message.id,
        senderName: message.senderName,
        previewText: message.hasText
            ? message.text
            : message.hasAttachments
                ? message.attachments.first.compactLabel
                : '',
      );
    });
    FocusScope.of(context).requestFocus(_composerFocusNode);
  }

  void _cancelReply() {
    setState(() => _pendingReply = null);
  }

  void _startSelecting(String messageId) {
    setState(() => _selectedMessageIds.add(messageId));
  }

  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (!_selectedMessageIds.remove(messageId)) {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  void _exitSelection() {
    setState(_selectedMessageIds.clear);
  }

  List<ChatMessage> _selectedMessagesInOrder(
      List<ChatMessage> visibleMessages) {
    return visibleMessages
        .where((message) => _selectedMessageIds.contains(message.id))
        .toList(growable: false);
  }

  Future<void> _forwardSelectedMessages(
    ChatThread thread,
    List<ChatMessage> visibleMessages,
  ) async {
    final selected = _selectedMessagesInOrder(visibleMessages);
    if (selected.isEmpty) {
      return;
    }
    final targetThreadIds = await pickForwardTarget(
      context,
      controller: widget.controller,
      excludeThreadId: thread.id,
    );
    if (targetThreadIds == null || targetThreadIds.isEmpty || !mounted) {
      return;
    }

    var successCount = 0;
    for (final targetThreadId in targetThreadIds) {
      for (final message in selected) {
        final didSend = message.hasAttachments
            ? await widget.controller.sendAttachmentMessage(
                threadId: targetThreadId,
                attachments: message.attachments,
                caption: message.hasText ? message.text : null,
              )
            : await widget.controller.sendTextMessage(
                threadId: targetThreadId,
                text: message.text,
              );
        if (didSend) {
          successCount++;
        }
      }
    }
    if (!mounted) {
      return;
    }
    _exitSelection();

    final totalSends = targetThreadIds.length * selected.length;
    final summary = successCount == totalSends
        ? (targetThreadIds.length == 1 && selected.length == 1
            ? 'Message forwarded'
            : 'Forwarded to ${targetThreadIds.length} chat${targetThreadIds.length == 1 ? '' : 's'}')
        : 'Forwarded $successCount of $totalSends messages';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary)),
    );
  }

  Future<void> _starSelectedMessages(List<ChatMessage> visibleMessages) async {
    final thread = widget.controller.threadById(widget.threadId);
    if (thread == null) {
      return;
    }
    final selected = _selectedMessagesInOrder(visibleMessages);
    if (selected.isEmpty) {
      return;
    }
    // If every selected message is already starred, the action unstars
    // them all; otherwise it stars whichever aren't starred yet -- matches
    // WhatsApp's own bulk-star behavior rather than blindly toggling each
    // one (which would flip an already-starred message back off).
    final shouldStar = selected.any((message) => !message.isStarred);
    for (final message in selected) {
      if (message.isStarred != shouldStar) {
        await widget.controller.toggleMessageStar(
          threadId: thread.id,
          messageId: message.id,
        );
      }
    }
    if (mounted) {
      _exitSelection();
    }
  }

  Future<void> _copySelectedMessage(List<ChatMessage> visibleMessages) async {
    final selected = _selectedMessagesInOrder(visibleMessages);
    if (selected.length != 1) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: selected.single.text));
    if (!mounted) {
      return;
    }
    _exitSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  Future<void> _deleteSelectedMessages(
      List<ChatMessage> visibleMessages) async {
    final thread = widget.controller.threadById(widget.threadId);
    if (thread == null) {
      return;
    }
    final selected = _selectedMessagesInOrder(visibleMessages);
    if (selected.isEmpty) {
      return;
    }
    final allMine = selected.every((message) => message.isFromCurrentUser);
    final count = selected.length;

    final forEveryone = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            count == 1 ? 'Delete message?' : 'Delete $count messages?',
          ),
          content: Text(
            allMine
                ? 'Choose who this should be deleted for.'
                : "These will be deleted for you -- they'll stay in this "
                    'chat for everyone else.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            if (allMine)
              TextButton(
                key: const Key('confirm_bulk_delete_everyone_button'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete for everyone'),
              ),
            FilledButton(
              key: const Key('confirm_bulk_delete_me_button'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Delete for me'),
            ),
          ],
        );
      },
    );

    if (forEveryone == null || !mounted) {
      return;
    }
    for (final message in selected) {
      await widget.controller.deleteMessage(
        threadId: thread.id,
        messageId: message.id,
        forEveryone: forEveryone,
      );
    }
    if (mounted) {
      _exitSelection();
    }
  }

  Future<void> _forwardMessage(ChatThread thread, ChatMessage message) async {
    final targetThreadIds = await pickForwardTarget(
      context,
      controller: widget.controller,
      excludeThreadId: thread.id,
    );
    if (targetThreadIds == null || targetThreadIds.isEmpty || !mounted) {
      return;
    }

    var successCount = 0;
    for (final targetThreadId in targetThreadIds) {
      final didSend = message.hasAttachments
          ? await widget.controller.sendAttachmentMessage(
              threadId: targetThreadId,
              attachments: message.attachments,
              caption: message.hasText ? message.text : null,
            )
          : await widget.controller.sendTextMessage(
              threadId: targetThreadId,
              text: message.text,
            );
      if (didSend) {
        successCount++;
      }
    }
    if (!mounted) {
      return;
    }

    final total = targetThreadIds.length;
    final summary = successCount == total
        ? (total == 1 ? 'Message forwarded' : 'Forwarded to $total chats')
        : 'Forwarded to $successCount of $total chats';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary)),
    );
  }

  Future<void> _editMessage(ChatThread thread, ChatMessage message) async {
    // A TextEditingController created here and disposed the moment
    // showDialog's Future resolves races the dialog's own closing
    // animation -- the Future completes as soon as Navigator.pop() is
    // called, not once the TextField has actually unmounted, and disposing
    // out from under a still-mounted, still-focused field corrupts focus
    // state badly enough to break later widget builds (see the identical
    // fix for the custom-emoji sheet elsewhere in this file). TextFormField
    // sidesteps this entirely -- initialValue seeds it without a caller-
    // owned controller, and onChanged reads the value into a local instead.
    var currentText = message.text;
    final newText = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit message'),
          content: TextFormField(
            key: const Key('edit_message_field'),
            initialValue: message.text,
            autofocus: true,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (value) => currentText = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm_edit_message_button'),
              onPressed: () => Navigator.of(dialogContext).pop(currentText),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    final trimmed = newText?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == message.text.trim()) {
      return;
    }
    if (!mounted) {
      return;
    }
    await widget.controller.editMessage(
      threadId: thread.id,
      messageId: message.id,
      text: trimmed,
    );
  }

  Future<void> _confirmDeleteMessage(
    ChatThread thread,
    ChatMessage message, {
    required bool forEveryone,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(forEveryone ? 'Delete for everyone?' : 'Delete message?'),
          content: Text(
            forEveryone
                ? 'This message will be deleted for everyone in this chat. '
                    "This can't be undone."
                : 'This message will be removed from your view only -- '
                    "${thread.name} will still see it. This can't be undone.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: Key(
                'confirm_delete_message_${forEveryone ? 'everyone' : 'me'}_button',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) {
      await widget.controller.deleteMessage(
        threadId: thread.id,
        messageId: message.id,
        forEveryone: forEveryone,
      );
    }
  }

  /// [Gal.putImage]/[Gal.putVideo] need a real local file path -- a chat
  /// attachment's own [ChatAttachment.localMediaPath] is that already for
  /// the sender (pre-upload), but for anyone else it's since become a
  /// Storage download URL, so the file is downloaded to a temp path first.
  Future<void> _saveMessageMedia(ChatMessage message) async {
    final attachment = message.attachments.cast<ChatAttachment?>().firstWhere(
          (candidate) =>
              (candidate?.type == ChatAttachmentType.photo ||
                  candidate?.type == ChatAttachmentType.video) &&
              statusMediaSourceExists(candidate?.localMediaPath ?? ''),
          orElse: () => null,
        );
    final source = attachment?.localMediaPath;
    if (attachment == null || source == null) {
      return;
    }

    File? tempFile;
    try {
      final hasAccess = await Gal.hasAccess() || await Gal.requestAccess();
      if (!hasAccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Allow photo library access in Settings to save media.',
              ),
            ),
          );
        }
        return;
      }

      var localPath = source;
      if (isRemoteStatusMediaPath(source)) {
        final response = await http.get(Uri.parse(source));
        final tempDir = await getTemporaryDirectory();
        final extension = source.contains('.')
            ? source.substring(source.lastIndexOf('.'))
            : (attachment.type == ChatAttachmentType.video ? '.mp4' : '.jpg');
        tempFile = File(
          '${tempDir.path}/whatswave-save-${DateTime.now().microsecondsSinceEpoch}$extension',
        );
        await tempFile.writeAsBytes(response.bodyBytes);
        localPath = tempFile.path;
      }

      if (attachment.type == ChatAttachmentType.video) {
        await Gal.putVideo(localPath);
      } else {
        await Gal.putImage(localPath);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to your gallery')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('We could not save that right now.')),
        );
      }
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        unawaited(tempFile.delete());
      }
    }
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
    final currentUid = fb_auth.FirebaseAuth.instance.currentUser?.uid ?? '';
    return CallContact(
      id: thread.id,
      name: thread.name,
      avatarLabel: thread.avatarLabel,
      accentColor: thread.accentColor,
      isGroup: thread.isGroup,
      uid: thread.participantUid,
      memberUids: thread.isGroup
          ? thread.otherMemberUids(currentUid)
          : null,
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
      final result = await FilePicker.platform.pickFiles();
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

    final recorded =
        await showVoiceNoteRecorderSheet(context, threadId: threadId);
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
    MessageReplyPreview? replyPreview,
  }) {
    return ChatMessage(
      id: '$threadId-local-${DateTime.now().microsecondsSinceEpoch}',
      senderName: 'You',
      sentAt: DateTime.now(),
      isFromCurrentUser: true,
      text: text,
      attachments: List<ChatAttachment>.unmodifiable(attachments),
      deliveryState: MessageDeliveryState.sending,
      replyPreview: replyPreview,
    );
  }
}

/// The dismissible "Replying to ..." bar shown above the composer while
/// [MessageAction.reply] is active -- WhatsApp's own quote-reply staging
/// area.
class _ReplyPreviewBar extends StatelessWidget {
  const _ReplyPreviewBar({
    required this.replyPreview,
    required this.onCancel,
  });

  final MessageReplyPreview replyPreview;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      color: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.3 : 0.5,
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  replyPreview.senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  replyPreview.previewText.isEmpty
                      ? 'Media'
                      : replyPreview.previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('conversation_cancel_reply_button'),
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onCancel,
          ),
        ],
      ),
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
    this.focusNode,
  });

  final GlobalKey composerBarKey;
  final TextEditingController controller;
  final bool isBusy;
  final bool canSendText;
  final double? lockedMinHeight;
  final ValueChanged<ChatAttachmentType> onAttachmentTap;
  final VoidCallback onSendTap;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

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
              focusNode: focusNode,
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
            borderColor:
                theme.colorScheme.outlineVariant.withValues(alpha: 0.34),
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
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
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

/// Actions available from a message's long-press menu (see
/// _MessageBubble._showReactionTray, which shows this alongside the
/// reaction tray) -- WhatsApp's own delete/forward/copy/edit/save set.
enum MessageAction {
  reply,
  copy,
  forward,
  star,
  edit,
  deleteForMe,
  deleteForEveryone,
  save,
  select,
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.thread,
    required this.message,
    required this.onAttachmentTap,
    required this.onReactionTap,
    required this.onAction,
    this.onRetryTap,
    this.isStoryReplyAvailable = false,
    this.onStoryReplyCardTap,
    this.isHighlighted = false,
    this.onReplyPreviewTap,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onToggleSelection,
  });

  final ChatThread thread;
  final ChatMessage message;

  /// True once any message in the thread is selected -- see
  /// ConversationScreen._isSelecting. Suppresses the long-press reaction
  /// tray and makes a plain tap toggle this bubble's own selection instead.
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelection;

  /// Tapping this message's own quoted "replying to ..." card (see
  /// [ChatMessage.replyPreview]) jumps back to the original message it
  /// quotes -- null hides that affordance (the conversation screen only
  /// ever passes it once _messageKeys/_jumpToMessage exist to serve it).
  final ValueChanged<String>? onReplyPreviewTap;

  /// Briefly true right after in-conversation search jumps to this message
  /// -- see ConversationScreen._jumpToMessage -- so the reader can spot
  /// which bubble the search landed on.
  final bool isHighlighted;
  final ValueChanged<ChatAttachment> onAttachmentTap;
  final ValueChanged<String> onReactionTap;
  final ValueChanged<MessageAction> onAction;
  final VoidCallback? onRetryTap;

  /// Whether [ChatMessage.storyReplyContext]'s story is still live -- the
  /// parent computes this (it needs UpdatesController, which this widget
  /// deliberately doesn't depend on) so the card can render its "no longer
  /// available" placeholder instead of a broken link to expired content.
  /// Meaningless when the message has no story reply context at all.
  final bool isStoryReplyAvailable;
  final VoidCallback? onStoryReplyCardTap;

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

    final bubble = Align(
      alignment: alignment,
      // A Builder here (rather than reading `context` from this outer
      // `build`) matters: this method's own `context` resolves through
      // `Align` first, whose render box stretches to the full row width --
      // using it for `_showReactionTray`'s position math would size the
      // tray/badge off the whole row instead of the actual bubble.
      child: Builder(
        builder: (bubbleContext) {
          return GestureDetector(
            onTap: isSelectionMode ? onToggleSelection : null,
            onLongPress: isSelectionMode
                ? null
                : () => _showReactionTray(bubbleContext, isMine: isMine),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      color: isHighlighted
                          ? Color.alphaBlend(
                              theme.colorScheme.primary.withValues(alpha: 0.22),
                              bubbleColor,
                            )
                          : bubbleColor,
                      border: Border.all(
                        width: isHighlighted ? 2 : 1,
                        color: isHighlighted
                            ? theme.colorScheme.primary
                            : isFailed
                                ? theme.colorScheme.error
                                    .withValues(alpha: 0.22)
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
                        if (message.isDeleted)
                          Text(
                            'This message was deleted',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: contentColor.withValues(alpha: 0.6),
                              fontStyle: FontStyle.italic,
                              height: 1.36,
                            ),
                          )
                        else ...[
                          if (message.hasReplyPreview) ...[
                            _ReplyPreviewQuoteCard(
                              replyPreview: message.replyPreview!,
                              accentColor: thread.accentColor,
                              onTap: onReplyPreviewTap == null
                                  ? null
                                  : () => onReplyPreviewTap!(
                                        message.replyPreview!.messageId,
                                      ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (message.hasStoryReplyContext) ...[
                            _StoryReplyCard(
                              replyContext: message.storyReplyContext!,
                              isAvailable: isStoryReplyAvailable,
                              onTap: onStoryReplyCardTap,
                            ),
                            const SizedBox(height: 8),
                          ],
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
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (message.isEdited && !message.isDeleted) ...[
                              Text(
                                'Edited',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: contentColor.withValues(alpha: 0.6),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (message.isStarred && !message.isDeleted) ...[
                              Icon(
                                Icons.star_rounded,
                                size: 13,
                                color: contentColor.withValues(alpha: 0.75),
                              ),
                              const SizedBox(width: 4),
                            ],
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
                    // -20 rather than -12 -- most of the badge now hangs in
                    // the gutter below the bubble instead of overlapping its
                    // bottom-most content row, so a short/narrow bubble
                    // (where the right-aligned timestamp ends up close to
                    // the bubble's own left edge too) doesn't get its
                    // timestamp text partly covered by the badge above it.
                    bottom: -20,
                    // Always the bubble's own left corner, regardless of
                    // isMine -- the timestamp/ticks row above always sits at
                    // the bubble's right edge (Row's mainAxisAlignment.end
                    // is a fixed LTR "end", not sender-relative), so the
                    // left corner is the one side that never overlaps it.
                    // For isMine (right-aligned) bubbles this also hangs the
                    // badge toward screen center rather than out past the
                    // bubble into the narrow gutter by the screen edge,
                    // which is what made it look like it spilled out of the
                    // message frame entirely.
                    left: -6,
                    child: _ReactionBadge(reactions: message.reactions),
                  ),
              ],
            ),
          );
        },
      ),
    );

    if (!isSelectionMode) {
      return bubble;
    }

    // In selection mode, a leading checkbox circle sits to the left of
    // every bubble regardless of isMine (matching WhatsApp) -- Expanded
    // keeps the bubble's own Align filling the remaining row width
    // exactly like it filled the whole row before this wrapper existed.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            key: Key('message_selection_checkbox_${message.id}'),
            onTap: onToggleSelection,
            child: Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 22,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.38),
            ),
          ),
        ),
        Expanded(child: bubble),
      ],
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
    // 6 quick-reaction emoji plus the trailing "+" (custom emoji), 44pt
    // each (see _ReactionTray's tap targets), plus LiquidGlassSurface's
    // own 8pt horizontal padding on each side.
    const trayWidth = 324.0;
    const trayMargin = 10.0;
    const actionRowHeight = 44.0;
    const actionMenuGap = 8.0;
    final actions = _availableActions();
    final actionMenuHeight =
        actions.isEmpty ? 0.0 : actions.length * actionRowHeight;
    final blockHeight =
        trayHeight + (actions.isEmpty ? 0.0 : actionMenuGap + actionMenuHeight);

    final showAbove = bubbleTopLeft.dy - blockHeight - trayMargin >
        mediaQuery.padding.top + 8;
    final rawBlockTop = showAbove
        ? bubbleTopLeft.dy - blockHeight - trayMargin
        : bubbleTopLeft.dy + bubbleSize.height + trayMargin;
    // With the action menu attached, the combined block can be taller than
    // the reaction tray alone was -- for a message near the bottom of the
    // screen (few actions still fit above it, but "show below" then runs
    // the block past the bottom edge), clamp it back on-screen instead of
    // letting it render partly unreachable.
    final minBlockTop = mediaQuery.padding.top + 8;
    final maxBlockTop = screenSize.height - blockHeight - trayMargin;
    final blockTop = maxBlockTop < minBlockTop
        ? minBlockTop
        : rawBlockTop.clamp(minBlockTop, maxBlockTop);
    final rawTrayLeft = isMine
        ? bubbleTopLeft.dx + bubbleSize.width - trayWidth
        : bubbleTopLeft.dx;
    final trayLeft =
        rawTrayLeft.clamp(12.0, screenSize.width - trayWidth - 12.0);

    var pickCustomEmoji = false;
    MessageAction? selectedAction;
    final selectedEmoji = await showFloatingGlassPopup<String>(
      bubbleContext,
      barrierLabel: 'Message actions',
      scaleAlignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      positionedChildBuilder: (overlayContext, close) => Positioned(
        left: trayLeft,
        top: blockTop,
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            _ReactionTray(
              onSelected: close,
              onCustomEmoji: () {
                pickCustomEmoji = true;
                close();
              },
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: actionMenuGap),
              _MessageActionMenu(
                width: trayWidth,
                actions: actions,
                isStarred: message.isStarred,
                onSelected: (action) {
                  selectedAction = action;
                  close();
                },
              ),
            ],
          ],
        ),
      ),
    );

    if (selectedEmoji != null) {
      onReactionTap(selectedEmoji);
      return;
    }
    if (pickCustomEmoji && bubbleContext.mounted) {
      final customEmoji = await _showCustomEmojiSheet(bubbleContext);
      if (customEmoji != null) {
        onReactionTap(customEmoji);
      }
      return;
    }
    if (selectedAction != null) {
      onAction(selectedAction!);
    }
  }

  bool get _hasSavableMedia => message.attachments.any(
        (attachment) =>
            (attachment.type == ChatAttachmentType.photo ||
                attachment.type == ChatAttachmentType.video) &&
            statusMediaSourceExists(attachment.localMediaPath ?? ''),
      );

  List<MessageAction> _availableActions() {
    final isMine = message.isFromCurrentUser;
    return [
      if (!message.isDeleted) MessageAction.reply,
      if (message.hasText && !message.isDeleted) MessageAction.copy,
      if (!message.isDeleted) MessageAction.forward,
      if (!message.isDeleted) MessageAction.star,
      if (isMine && message.hasText && !message.isDeleted) MessageAction.edit,
      if (_hasSavableMedia) MessageAction.save,
      if (!message.isDeleted) MessageAction.select,
      MessageAction.deleteForMe,
      if (isMine && !message.isDeleted) MessageAction.deleteForEveryone,
    ];
  }

  /// The 6 quick-react emoji cover WhatsApp's own defaults, but not every
  /// reaction someone wants -- this opens a full emoji keyboard (search,
  /// recent, categories, grid) instead of relying on the OS keyboard's own
  /// emoji panel.
  Future<String?> _showCustomEmojiSheet(BuildContext context) {
    return EmojiReactionPickerSheet.show(context);
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

/// A small quoted card above a reply's own text -- WhatsApp's own
/// quote-reply. Tapping it jumps back to the original message (see
/// ConversationScreen._jumpToMessage); [onTap] is null once that lookup
/// has nothing live to scroll to (the GlobalKey map only ever holds
/// currently-rendered messages).
class _ReplyPreviewQuoteCard extends StatelessWidget {
  const _ReplyPreviewQuoteCard({
    required this.replyPreview,
    required this.accentColor,
    required this.onTap,
  });

  final MessageReplyPreview replyPreview;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('reply_preview_quote_card'),
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: accentColor, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                replyPreview.senderName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                replyPreview.previewText.isEmpty
                    ? 'Media'
                    : replyPreview.previewText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small tappable card above a story reply's own text -- WhatsApp's
/// "replied to your status" quote. Shows a thumbnail (photo/video segment)
/// or a colored snippet (text segment) plus a caption line when the story
/// is still live ([isAvailable]); otherwise an empty, non-tappable
/// placeholder, since the referenced story has expired or been deleted.
class _StoryReplyCard extends StatelessWidget {
  const _StoryReplyCard({
    required this.replyContext,
    required this.isAvailable,
    required this.onTap,
  });

  final StoryReplyContext replyContext;
  final bool isAvailable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurfaceMuted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Opacity(
      opacity: isAvailable ? 1 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('story_reply_card'),
          onTap: isAvailable ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 36,
                    height: 48,
                    child: _buildThumbnail(theme),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isAvailable
                            ? 'Replied to ${replyContext.storyOwnerName}\'s status'
                            : 'Original status no longer available',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isAvailable ? null : onSurfaceMuted,
                        ),
                      ),
                      if (isAvailable &&
                          (replyContext.previewText?.trim().isNotEmpty ??
                              false))
                        Text(
                          replyContext.previewText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: onSurfaceMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(ThemeData theme) {
    if (!isAvailable) {
      return ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 16,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      );
    }

    final mediaUrl = replyContext.mediaUrl;
    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      return Image.network(
        mediaUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.broken_image_outlined,
            size: 16,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Color(replyContext.accentColorArgb ?? 0xFF3A3A3A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Text(
            replyContext.previewText ?? '',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 7),
          ),
        ),
      ),
    );
  }
}

/// The floating glass reaction picker shown on long-press, in the style of
/// iMessage's Tapback tray -- a horizontal row of quick-react emojis
/// pinned near the bubble rather than WhatsApp's flatter below-bubble row.
class _ReactionTray extends StatelessWidget {
  const _ReactionTray({required this.onSelected, required this.onCustomEmoji});

  final ValueChanged<String> onSelected;

  /// Opens a way to react with any emoji, not just the 6 quick ones below
  /// (see _MessageBubble._showCustomEmojiSheet).
  final VoidCallback onCustomEmoji;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              key: const Key('reaction_option_custom'),
              customBorder: const CircleBorder(),
              onTap: onCustomEmoji,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Icon(
                    Icons.add_rounded,
                    size: 22,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The vertical list of text actions (copy/forward/edit/delete/save) shown
/// below the reaction tray on a message long-press -- WhatsApp's own
/// context menu, in the same floating-glass language as the tray above it.
class _MessageActionMenu extends StatelessWidget {
  const _MessageActionMenu({
    required this.width,
    required this.actions,
    required this.isStarred,
    required this.onSelected,
  });

  final double width;
  final List<MessageAction> actions;

  /// Whether the message this menu is for is already starred -- the
  /// [MessageAction.star] row's icon/label flips between "Star"/"Unstar"
  /// based on this, so it isn't part of the static [_presentation] map.
  final bool isStarred;
  final ValueChanged<MessageAction> onSelected;

  static const Map<MessageAction, (IconData, String)> _presentation = {
    MessageAction.reply: (Icons.reply_rounded, 'Reply'),
    MessageAction.copy: (Icons.content_copy_rounded, 'Copy'),
    MessageAction.forward: (Icons.forward_rounded, 'Forward'),
    MessageAction.edit: (Icons.edit_outlined, 'Edit'),
    MessageAction.save: (Icons.download_rounded, 'Save'),
    MessageAction.select: (Icons.check_circle_outline_rounded, 'Select'),
    MessageAction.deleteForMe: (Icons.delete_outline_rounded, 'Delete for me'),
    MessageAction.deleteForEveryone: (
      Icons.delete_forever_rounded,
      'Delete for everyone',
    ),
  };

  (IconData, String) _presentationFor(MessageAction action) {
    if (action == MessageAction.star) {
      return isStarred
          ? (Icons.star_rounded, 'Unstar')
          : (Icons.star_border_rounded, 'Star');
    }
    return _presentation[action]!;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: LiquidGlassSurface(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions) _buildActionRow(context, action),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, MessageAction action) {
    final theme = Theme.of(context);
    final (icon, label) = _presentationFor(action);
    return Material(
      key: Key('message_action_${action.name}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelected(action),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: _isDestructive(action)
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface.withValues(alpha: 0.78),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _isDestructive(action)
                          ? theme.colorScheme.error
                          : null,
                      fontWeight: FontWeight.w600,
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

  bool _isDestructive(MessageAction action) =>
      action == MessageAction.deleteForMe ||
      action == MessageAction.deleteForEveryone;
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
    final isDark = theme.brightness == Brightness.dark;
    final distinctEmojis = reactions.values.toSet().toList(growable: false);

    // A fully opaque pill (not the earlier translucent glass, which read as
    // background-less/disconnected) so the badge stays legible over any
    // bubble color. Matches the page background rather than the bubble --
    // like iMessage's tapback bubble, it should read as floating in front
    // of the chat, not tinted by whatever bubble it's overlapping.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.36 : 0.14),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in distinctEmojis)
              // Sized to match the emoji picker sheet's own grid glyphs
              // (EmojiViewConfig.emojiSizeMax: 30 in
              // emoji_reaction_picker_screen.dart) so a reaction looks the
              // same size here as it did when picked.
              Text(emoji, style: const TextStyle(fontSize: 20)),
            if (reactions.length > 1) ...[
              const SizedBox(width: 4),
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
/// video shows a real thumbnail via [videoThumbnailFor], generated
/// on-device (get_video_thumbnail -- a maintained fork of the original
/// video_thumbnail package, whose Android build depends on the long-dead
/// jcenter() Maven repo and fails to compile on any current Android
/// Gradle setup). Falls back to a tinted swatch with a type icon when
/// there's no local media to show, or thumbnail generation fails.
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
    final isPhoto = attachment.type == ChatAttachmentType.photo ||
        attachment.isImageDocument;
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
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        return child;
                      }
                      return _loadingPlaceholder();
                    },
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

  /// Shown while a network (Storage-hosted) photo attachment is still
  /// fetching -- the tinted swatch [_placeholder] uses, but with a spinner
  /// instead of the type icon, so a genuinely-loading tile reads
  /// differently from a genuinely-missing one.
  Widget _loadingPlaceholder() {
    return ColoredBox(
      color: attachment.tintColor.withValues(alpha: 0.18),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: attachment.tintColor,
          ),
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
