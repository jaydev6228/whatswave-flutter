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
import 'document_send_preview_screen.dart';
import 'location_send_preview_screen.dart';
import 'media_send_preview_screen.dart';
import 'widgets/emoji_reaction_picker_screen.dart';
import 'widgets/lazy_heavy_attachment.dart';
import 'widgets/location_map_preview.dart';
import 'widgets/video_thumbnail_source.dart';
import 'widgets/voice_note_bubble.dart';
import 'widgets/composer_voice_button.dart';

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
  static const Duration _ownSendScrollSuppression = Duration(milliseconds: 700);
  static const Duration _outboundEchoMatchWindow = Duration(minutes: 2);

  final GlobalKey _composerBarKey = GlobalKey();
  final ImagePicker _imagePicker = ImagePicker();
  late final TextEditingController _composerController;
  late final ScrollController _messageListController;
  double? _composerLockedMinHeight;
  String? _lastRenderedThreadId;
  String? _lastKnownLatestMessageId;
  double? _lastKnownBottomInset;
  String? _animatedMessageId;
  bool _skipNextMessageEntryAnimation = false;
  bool _suppressAutoScrollForOwnSend = false;
  String? _activeOutboundLocalId;
  final Map<String, String> _stableListKeysByMessageId = <String, String>{};
  final List<ChatMessage> _localMessages = <ChatMessage>[];
  Timer? _composerUnlockTimer;
  Timer? _animatedMessageCleanupTimer;
  Timer? _ownSendScrollSuppressionTimer;
  DateTime? _suppressBottomSnapUntil;

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
  bool _bottomSnapScheduled = false;

  /// A GlobalKey per message, keyed by id and never removed once created --
  /// lets a reply's quote card (see [_jumpToMessage]) scroll to an
  /// arbitrary earlier message via [Scrollable.ensureVisible] instead of
  /// only ever being able to jump to the list's bottom.
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};

  final ValueNotifier<String?> _highlightedMessageIdNotifier =
      ValueNotifier<String?>(null);
  Timer? _highlightClearTimer;

  /// Set by [MessageAction.reply] -- a snapshot of the message being
  /// replied to, shown as a dismissible bar above the composer while it's
  /// set, and attached to the next message sent.
  MessageReplyPreview? _pendingReply;

  /// Set by [MessageAction.edit] -- the message currently being edited. While
  /// non-null the composer is prefilled with its text, an "Editing message"
  /// bar sits above the composer, and the send button saves the edit instead
  /// of posting a new message (WhatsApp-style inline edit).
  ChatMessage? _editingMessage;
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
    widget.controller.addListener(_reconcileOutboundSendWithController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.ensureThreadMessagesLoaded(widget.threadId);
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_reconcileOutboundSendWithController);
    _composerUnlockTimer?.cancel();
    _animatedMessageCleanupTimer?.cancel();
    _ownSendScrollSuppressionTimer?.cancel();
    _highlightClearTimer?.cancel();
    _highlightedMessageIdNotifier.dispose();
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
    _activeOutboundLocalId = null;
    _stableListKeysByMessageId.clear();
    _ownSendScrollSuppressionTimer?.cancel();
    _suppressBottomSnapUntil = null;
  }

  ChatThread? _threadForMessageList() {
    return widget.controller.threadById(widget.threadId);
  }

  bool get _hasOutboundSending => _localMessages.any(
        (message) => message.deliveryState == MessageDeliveryState.sending,
      );

  String _messageListKeyFor(ChatMessage message) {
    return _stableListKeysByMessageId[message.id] ?? message.id;
  }

  void _beginOutboundSend({
    required String threadId,
    required ChatMessage localMessage,
  }) {
    _activeOutboundLocalId = localMessage.id;
    _stableListKeysByMessageId[localMessage.id] = localMessage.id;
    _upsertLocalMessage(localMessage);
    _extendOwnSendScrollSuppression();
  }

  /// When the controller publishes persisted echoes, finalize every in-flight
  /// optimistic bubble *before* [ListenableBuilder] rebuilds.
  void _reconcileOutboundSendWithController() {
    if (!mounted) {
      return;
    }

    final liveThread = widget.controller.threadById(widget.threadId);
    if (liveThread == null) {
      return;
    }

    for (final localMessage in _localMessages.toList(growable: false)) {
      if (localMessage.deliveryState != MessageDeliveryState.sending) {
        continue;
      }
      if (_findPersistedMatch(liveThread, localMessage) == null) {
        continue;
      }
      _finalizeOutgoingSend(thread: liveThread, localMessage: localMessage);
    }
  }

  void _endOutboundSend() {
    _activeOutboundLocalId = null;
  }

  bool get _shouldSuppressBottomSnap {
    if (_hasOutboundSending) {
      return true;
    }
    final until = _suppressBottomSnapUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void _extendOwnSendScrollSuppression() {
    _suppressAutoScrollForOwnSend = true;
    _suppressBottomSnapUntil = DateTime.now().add(_ownSendScrollSuppression);
    _ownSendScrollSuppressionTimer?.cancel();
    _ownSendScrollSuppressionTimer = Timer(_ownSendScrollSuppression, () {
      if (!mounted) {
        return;
      }
      _suppressAutoScrollForOwnSend = false;
      _suppressBottomSnapUntil = null;
    });
  }

  /// Pins the reader to the bottom without forcing a scroll jump when they're
  /// already sitting on the latest message (offset ~0 in the reverse:true
  /// list) -- e.g. an own send lands at offset 0 anyway, so no jump is needed.
  void _scrollToLatestIfNeeded({required bool wasNearLatest}) {
    _stickToBottom = true;
    if (!wasNearLatest) {
      _scheduleScrollToLatestMessage(animated: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _ConversationAppBarHost(state: this),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final thread = _threadForMessageList();
                if (thread == null) {
                  return Center(
                    child: Text(
                      'This conversation is no longer available.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  );
                }
                return _buildMessageListPane(context, thread);
              },
            ),
          ),
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final thread = widget.controller.threadById(widget.threadId);
              if (thread == null || thread.isBlocked) {
                if (thread != null) {
                  return _BlockedContactBanner(name: thread.name);
                }
                return const SizedBox.shrink();
              }
              return _buildComposerPane(context, thread);
            },
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildConversationAppBar(
    BuildContext context,
    ChatThread? thread,
  ) {
    final theme = Theme.of(context);

    if (thread == null) {
      return AppBar(title: const Text('Conversation'));
    }

    final story = widget.updatesController.storyForParticipant(
      avatarLabel: thread.avatarLabel,
      name: thread.name,
    );
    final showStory = widget.controller.shouldShowStoryForThread(thread);
    final visibleMessages = _visibleMessagesForThread(thread);

    return AppBar(
      titleSpacing: 0,
      leading: _isSelecting
          ? IconButton(
              key: const Key('conversation_selection_close_button'),
              icon: const Icon(Icons.close_rounded),
              onPressed: _exitSelection,
            )
          : null,
      title: _isSelecting
          ? Text('${_selectedMessageIds.length} selected')
          : MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: showStory && story != null
                        ? () => _openThreadStory(story)
                        : null,
                    child: showStory
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
                  _selectedMessagesInOrder(visibleMessages).single.hasText)
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
                size: 44,
                visualSize: 34,
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
    );
  }

  Widget _buildMessageListPane(BuildContext context, ChatThread thread) {
    _syncThreadScrollBehavior(context, thread);

    final theme = Theme.of(context);
    final visibleMessages = _visibleMessagesForThread(thread);
    final displayMessages = _displayMessagesForList(visibleMessages);
    final showOlderLoader =
        widget.controller.isLoadingOlderMessages(thread.id);

    return SafeArea(
      bottom: false,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.94 : 0.98,
            ),
          ),
          child: NotificationListener<Notification>(
            onNotification: _handleMessageListNotification,
            child: ListView.builder(
              key: const Key('conversation_message_list'),
              controller: _messageListController,
              // Bottom-anchored (WhatsApp-style): newest-first content with
              // reverse:true, so scroll offset 0 is the newest message at the
              // bottom. Opening lands there with no jump (no flicker), and
              // older pages prepend without moving the view -- see
              // _displayMessagesForList and the scroll helpers, all keyed off
              // offset 0 being the latest.
              reverse: true,
              addRepaintBoundaries: true,
              findChildIndexCallback: (Key key) {
                if (key is! ValueKey<String>) {
                  return null;
                }
                final rawId = key.value;
                const prefix = 'conversation_message_';
                if (!rawId.startsWith(prefix)) {
                  return null;
                }
                final messageId = rawId.substring(prefix.length);
                return displayMessages.indexWhere(
                  (message) => _messageListKeyFor(message) == messageId,
                );
              },
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                _messageListBottomPadding,
              ),
              itemCount: displayMessages.length + (showOlderLoader ? 1 : 0),
              itemBuilder: (context, index) {
                // reverse:true -> the extra trailing index is the visual top,
                // where older history is being paged in.
                if (index == displayMessages.length) {
                  return const _OlderMessagesLoader();
                }
                final message = displayMessages[index];
                // reverse:true / newest-first: the older neighbour is the next
                // index. Show a day chip above the first message of each day.
                final olderMessage = index + 1 < displayMessages.length
                    ? displayMessages[index + 1]
                    : null;
                final shouldShowDayChip = olderMessage == null ||
                    !_isSameDay(message.sentAt, olderMessage.sentAt);
                final bubble = _MessageBubble(
                  thread: thread,
                  message: message,
                  highlightMessageIdNotifier: _highlightedMessageIdNotifier,
                  onRetryTap: message.isFromCurrentUser &&
                          message.deliveryState ==
                              MessageDeliveryState.failed &&
                          _localMessages.any(
                            (localMessage) => localMessage.id == message.id,
                          )
                      ? () => _retryFailedMessage(thread.id, message)
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
                  onAction: (action) => _handleMessageAction(
                    action,
                    thread: thread,
                    message: message,
                  ),
                  isStoryReplyAvailable: _isStoryReplyAvailable(message),
                  onStoryReplyCardTap: message.hasStoryReplyContext
                      ? () => _openStoryReplyCard(message.storyReplyContext!)
                      : null,
                  onReplyPreviewTap: _jumpToMessage,
                  isSelectionMode: _isSelecting,
                  isSelected: _selectedMessageIds.contains(message.id),
                  onToggleSelection: () => _toggleMessageSelection(message.id),
                );
                final listKey = _messageListKeyFor(message);
                final shouldAnimateEntry = listKey == _animatedMessageId ||
                    message.id == _animatedMessageId;
                final messageBody = shouldAnimateEntry
                    ? _AnimatedMessageEntry(
                        key: ValueKey('conversation_message_$listKey'),
                        animateOnMount: !_skipNextMessageEntryAnimation,
                        isMine: message.isFromCurrentUser,
                        child: bubble,
                      )
                    : KeyedSubtree(
                        key: ValueKey('conversation_message_$listKey'),
                        child: bubble,
                      );

                // WhatsApp-style swipe-right-to-reply, disabled while
                // selecting or on a tombstoned message.
                final swipeableBody = message.isDeleted || _isSelecting
                    ? messageBody
                    : _SwipeToReply(
                        key: ValueKey('swipe_reply_$listKey'),
                        onReply: () => _startReplyingTo(message),
                        child: messageBody,
                      );

                return RepaintBoundary(
                  child: _KeepAliveMessageItem(
                    child: KeyedSubtree(
                      key: _messageKeys.putIfAbsent(
                        message.id,
                        GlobalKey.new,
                      ),
                      child: Column(
                        children: [
                          if (shouldShowDayChip)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _DayDivider(
                                label: _dayLabelFor(message.sentAt),
                              ),
                            ),
                          swipeableBody,
                          // Trailing gap below each bubble. reverse:true means
                          // index 0 is the newest (screen bottom); skip its
                          // trailing spacer since the list's own bottom padding
                          // handles the gap above the composer.
                          if (index != 0)
                            SizedBox(height: message.hasReactions ? 30 : 10),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposerPane(BuildContext context, ChatThread thread) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_editingMessage != null)
          _EditingBar(
            message: _editingMessage!,
            onCancel: _cancelEditing,
          )
        else if (_pendingReply != null)
          _ReplyPreviewBar(
            replyPreview: _pendingReply!,
            onCancel: _cancelReply,
          ),
        _ComposerBar(
          composerBarKey: _composerBarKey,
          threadId: thread.id,
          controller: _composerController,
          focusNode: _composerFocusNode,
          isBusy: widget.controller.isThreadBusy(thread.id),
          lockedMinHeight: _composerLockedMinHeight,
          onAttachmentTap: (type) async {
            _handleAttachmentTap(thread.id, type);
          },
          onSendTap: () async {
            _handleSendTap(thread.id);
          },
          onVoiceRecorded: (attachment) async {
            await _sendOutboundAttachments(
              threadId: thread.id,
              attachments: [attachment],
            );
          },
        ),
      ],
    );
  }

  void _syncThreadScrollBehavior(BuildContext context, ChatThread thread) {
    if (_lastRenderedThreadId != thread.id) {
      _lastRenderedThreadId = thread.id;
      _lastKnownLatestMessageId = thread.latestMessage?.id;
      // reverse:true opens at offset 0 (the newest message) with no jump, so
      // no explicit scroll is needed here.
      _stickToBottom = true;
    } else {
      final latestMessageId = thread.latestMessage?.id;
      if (latestMessageId != null &&
          latestMessageId != _lastKnownLatestMessageId) {
        _lastKnownLatestMessageId = latestMessageId;
        if (!_suppressAutoScrollForOwnSend) {
          final wasNearLatest = _isNearLatestMessage();
          if (wasNearLatest) {
            _scheduleScrollToLatestMessage(animated: true);
          }
        }
        if (thread.unreadCount > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.controller.openThread(thread.id);
            }
          });
        }
      }
    }

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    if (_lastKnownBottomInset != null &&
        bottomInset != _lastKnownBottomInset &&
        !_suppressAutoScrollForOwnSend &&
        !_hasOutboundSending) {
      _scheduleScrollToLatestMessage(animated: true);
    }
    _lastKnownBottomInset = bottomInset;
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

  Future<void> _jumpToMessage(String messageId) async {
    // The quoted target may have scrolled out of the currently-loaded window
    // (no data for it yet) or simply be far enough away that ListView.builder
    // hasn't laid it out (data present, but no render object/context yet --
    // reverse:true lazily builds only near the current scroll position plus a
    // small cache extent). Page data in first, then walk the scroll position
    // toward the target so its widget actually builds, before scrolling to it.
    final threadId = _lastRenderedThreadId;
    if (_messageKeys[messageId]?.currentContext == null && threadId != null) {
      // No-ops quickly if the message is already in the loaded window.
      final loaded =
          await widget.controller.ensureMessageLoaded(threadId, messageId);
      if (!mounted || !loaded) {
        return;
      }
      // Let the paged-in data actually rebuild the list before we try to
      // locate/scroll to it.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) {
        return;
      }
      await _scrollUntilMessageBuilt(threadId, messageId);
      if (!mounted) {
        return;
      }
    }

    final targetContext = _messageKeys[messageId]?.currentContext;
    if (targetContext == null || !targetContext.mounted) {
      return;
    }
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    _highlightClearTimer?.cancel();
    _highlightedMessageIdNotifier.value = messageId;
    _highlightClearTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        _highlightedMessageIdNotifier.value = null;
      }
    });
  }

  /// The same newest-first ordering the list itself renders, computed fresh
  /// from the controller's current thread state -- used to locate a jump
  /// target's index without waiting for a full widget rebuild cycle.
  List<ChatMessage>? _currentDisplayMessages(String threadId) {
    final thread = widget.controller.threadById(threadId);
    if (thread == null) {
      return null;
    }
    return _displayMessagesForList(_visibleMessagesForThread(thread));
  }

  /// Jumps the scroll position toward [messageId] so ListView.builder lays
  /// out its widget (and [_messageKeys] gets a real context), even though the
  /// message is already loaded into the thread's data. Estimates an offset
  /// from the target's proportional index against the list's (extrapolated)
  /// total scroll extent, then widens outward in both directions in case the
  /// estimate is off -- item heights vary (text vs. voice notes vs. images),
  /// so the estimate is approximate, not exact.
  Future<void> _scrollUntilMessageBuilt(
    String threadId,
    String messageId,
  ) async {
    const maxRounds = 3;
    for (var round = 0; round < maxRounds; round++) {
      if (_messageKeys[messageId]?.currentContext != null) {
        return;
      }
      if (!_messageListController.hasClients) {
        return;
      }

      final displayMessages = _currentDisplayMessages(threadId);
      if (displayMessages == null) {
        return;
      }
      final targetIndex =
          displayMessages.indexWhere((message) => message.id == messageId);
      if (targetIndex < 0) {
        // Not in the loaded window after all (shouldn't happen -- the caller
        // already confirmed it's loaded -- but bail out rather than looping).
        return;
      }

      final metrics = _messageListController.position;
      final maxExtent = metrics.maxScrollExtent;
      if (maxExtent <= 0 || displayMessages.length <= 1) {
        return;
      }

      final estimatedOffset =
          (targetIndex / (displayMessages.length - 1)) * maxExtent;
      final viewportExtent = metrics.viewportDimension > 0
          ? metrics.viewportDimension
          : 700.0;

      // Try the estimate, then widen outward (further/nearer in the list) in
      // case item-height variance threw the estimate off.
      final candidateOffsets = <double>[
        estimatedOffset,
        estimatedOffset + viewportExtent,
        estimatedOffset - viewportExtent,
        estimatedOffset + viewportExtent * 2,
        estimatedOffset - viewportExtent * 2,
      ];

      for (final candidate in candidateOffsets) {
        if (_messageKeys[messageId]?.currentContext != null) {
          return;
        }
        if (!_messageListController.hasClients) {
          return;
        }
        _messageListController.jumpTo(candidate.clamp(0.0, maxExtent));
        // Two frames: one for the jump's layout pass, one for any follow-up
        // relayout it triggers (e.g. newly-built children reporting size).
        await WidgetsBinding.instance.endOfFrame;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) {
          return;
        }
      }
    }
  }

  Future<void> _openContactInfo(String threadId) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContactInfoScreen(
          controller: widget.controller,
          communitiesController: widget.communitiesController,
          callsController: widget.callsController,
          updatesController: widget.updatesController,
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
      final draft = await Navigator.of(context).push<LocationSendDraft>(
        MaterialPageRoute<LocationSendDraft>(
          builder: (_) => LocationSendPreviewScreen(
            threadId: threadId,
            locationService: widget.controller.locationService,
          ),
          fullscreenDialog: true,
        ),
      );
      if (!mounted || draft == null) {
        return;
      }
      await _sendOutboundAttachments(
        threadId: threadId,
        attachments: [draft.attachment],
        caption: draft.caption,
      );
      return;
    }

    if (type == ChatAttachmentType.voiceNote) {
      return;
    }

    var pickedAttachments = await _resolveAttachmentsForTap(
      threadId: threadId,
      type: type,
    );
    if (!mounted || pickedAttachments == null || pickedAttachments.isEmpty) {
      return;
    }

    var caption = '';

    if (type == ChatAttachmentType.photo || type == ChatAttachmentType.video) {
      final composerCaption = _composerController.text.trim();
      final draft = await Navigator.of(context).push<MediaSendDraft>(
        MaterialPageRoute<MediaSendDraft>(
          builder: (_) => MediaSendPreviewScreen(
            attachments: pickedAttachments!,
            initialCaption: composerCaption.isEmpty ? null : composerCaption,
          ),
          fullscreenDialog: true,
        ),
      );
      if (!mounted || draft == null) {
        return;
      }
      pickedAttachments = draft.attachments;
      caption = draft.caption?.trim() ?? '';
    } else if (type == ChatAttachmentType.file) {
      final draft = await Navigator.of(context).push<DocumentSendDraft>(
        MaterialPageRoute<DocumentSendDraft>(
          builder: (_) => DocumentSendPreviewScreen(
            attachment: pickedAttachments!.single,
          ),
          fullscreenDialog: true,
        ),
      );
      if (!mounted || draft == null) {
        return;
      }
      pickedAttachments = [draft.attachment];
      caption = draft.caption?.trim() ?? '';
    }

    await _sendOutboundAttachments(
      threadId: threadId,
      attachments: pickedAttachments,
      caption: caption.isEmpty ? null : caption,
      clearComposerAfterSend:
          type == ChatAttachmentType.photo || type == ChatAttachmentType.video,
    );
  }

  Future<void> _sendOutboundAttachments({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
    bool clearComposerAfterSend = false,
  }) async {
    final trimmedCaption = caption?.trim() ?? '';
    final wasNearLatest = _isNearLatestMessage();
    final replyPreview = _pendingReply;
    final localMessage = _buildLocalMessage(
      threadId: threadId,
      text: trimmedCaption,
      attachments: attachments,
      replyPreview: replyPreview,
    );

    _lockComposerHeight();
    _beginOutboundSend(threadId: threadId, localMessage: localMessage);
    _markMessageForAnimation(localMessage.id);
    if (clearComposerAfterSend) {
      _composerController.clear();
    }
    _pendingReply = null;
    if (mounted) {
      setState(() {});
    }
    _scrollToLatestIfNeeded(wasNearLatest: wasNearLatest);

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
      _endOutboundSend();
      _upsertLocalMessage(
        localMessage.copyWith(
          deliveryState: MessageDeliveryState.failed,
        ),
      );
      _releaseComposerReset();
    } else {
      final thread = widget.controller.threadById(threadId);
      if (thread != null) {
        _finalizeOutgoingSend(thread: thread, localMessage: localMessage);
      } else {
        _endOutboundSend();
        _removeLocalMessage(localMessage.id);
      }
      _scheduleComposerReset(clearDraft: false);
    }
    setState(() {});
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
    // While editing, the composer's send/save button commits the edit rather
    // than posting a new message.
    if (_editingMessage != null) {
      await _saveEdit(threadId);
      return;
    }

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
    _beginOutboundSend(threadId: threadId, localMessage: localMessage);
    _markMessageForAnimation(localMessage.id);
    _composerController.clear();
    _composerLockedMinHeight = null;
    _pendingReply = null;
    if (mounted) {
      setState(() {});
    }
    _scrollToLatestIfNeeded(wasNearLatest: wasNearLatest);

    final didSend = await widget.controller.sendTextMessage(
      threadId: threadId,
      text: trimmedDraft,
      replyPreview: replyPreview,
    );

    if (!mounted) {
      return;
    }

    if (!didSend) {
      _endOutboundSend();
      _upsertLocalMessage(
        localMessage.copyWith(
          deliveryState: MessageDeliveryState.failed,
        ),
      );
    } else {
      final thread = widget.controller.threadById(threadId);
      if (thread != null) {
        _finalizeOutgoingSend(thread: thread, localMessage: localMessage);
      } else {
        _endOutboundSend();
        _removeLocalMessage(localMessage.id);
      }
    }
    setState(() {});
  }

  void _finalizeOutgoingSend({
    required ChatThread thread,
    required ChatMessage localMessage,
  }) {
    final freshThread = widget.controller.threadById(thread.id) ?? thread;
    final persisted = _findPersistedMatch(freshThread, localMessage);
    final alreadyFinalized =
        !_localMessages.any((entry) => entry.id == localMessage.id);

    _lastKnownLatestMessageId = freshThread.latestMessage?.id;
    if (_activeOutboundLocalId == localMessage.id) {
      _activeOutboundLocalId = null;
    }
    _extendOwnSendScrollSuppression();

    if (!alreadyFinalized) {
      _removeLocalMessage(localMessage.id);
    }

    if (persisted != null) {
      _stableListKeysByMessageId[persisted.id] = localMessage.id;
      _markMessageForAnimation(localMessage.id, animate: false);
    }
  }

  ChatMessage? _findPersistedMatch(
    ChatThread thread,
    ChatMessage localMessage,
  ) {
    for (final message in thread.messages.reversed) {
      if (_messageMatchesLocal(message, localMessage)) {
        return message;
      }
    }
    return null;
  }

  bool _messageMatchesLocal(ChatMessage persisted, ChatMessage localMessage) {
    if (!persisted.isFromCurrentUser || !localMessage.isFromCurrentUser) {
      return false;
    }

    // Never treat an older same-text bubble as the echo for a new send.
    if (persisted.sentAt.isBefore(
      localMessage.sentAt.subtract(_outboundEchoMatchWindow),
    )) {
      return false;
    }

    if (localMessage.hasText || persisted.hasText) {
      if (persisted.text.trim() != localMessage.text.trim()) {
        return false;
      }
    }

    if (localMessage.hasAttachments) {
      if (persisted.attachments.length != localMessage.attachments.length) {
        return false;
      }
      for (var index = 0; index < localMessage.attachments.length; index++) {
        if (localMessage.attachments[index].type !=
            persisted.attachments[index].type) {
          return false;
        }
      }
      return true;
    }

    return localMessage.hasText && persisted.hasText;
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
    // Page older history in as the reader approaches the top of the loaded
    // window. reverse:true means the oldest message sits near maxScrollExtent,
    // so "near the top" is a small remaining distance to that extent. Prepended
    // pages land at the far (top) end and don't shift the current view.
    if (notification is ScrollNotification) {
      _maybeLoadOlderMessages(notification.metrics);
    }
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

      if (_hasOutboundSending || _shouldSuppressBottomSnap) {
        return false;
      }

      // Only re-snap when content actually grew (an async image/map/etc.
      // finished laying out) while the reader was sitting right at the
      // previous bottom -- never just because pixels doesn't currently equal
      // the max, which is the normal state for a deliberate scroll-up and must
      // never be fought. reverse:true: "at the bottom" means pixels near 0.
      final contentGrew =
          previousMax != null && metrics.maxScrollExtent > previousMax + 0.5;
      final wasAtPreviousBottom = metrics.pixels.abs() <= 40;
      if (_stickToBottom && contentGrew && wasAtPreviousBottom) {
        _scheduleBottomSnap();
      }
    }
    return false;
  }

  /// Distance (px) from the top (oldest) edge at which to start paging older
  /// messages, so the next window is usually ready before the reader reaches
  /// it. reverse:true: the top edge is [ScrollMetrics.maxScrollExtent].
  static const double _loadOlderTriggerExtent = 400;

  void _maybeLoadOlderMessages(ScrollMetrics metrics) {
    final threadId = _lastRenderedThreadId;
    if (threadId == null ||
        !widget.controller.hasMoreOlderMessages(threadId) ||
        widget.controller.isLoadingOlderMessages(threadId)) {
      return;
    }
    if (metrics.maxScrollExtent - metrics.pixels <= _loadOlderTriggerExtent) {
      // Fire-and-forget; the controller no-ops re-entrant calls and notifies
      // when the prepended page lands.
      widget.controller.loadOlderMessages(threadId);
    }
  }

  void _scheduleBottomSnap() {
    if (_bottomSnapScheduled) {
      return;
    }
    _bottomSnapScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bottomSnapScheduled = false;
      if (!mounted || !_stickToBottom || !_messageListController.hasClients) {
        return;
      }
      if (_messageListController.offset.abs() <= 0.5) {
        return;
      }
      _messageListController.jumpTo(0);
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

  void _markMessageForAnimation(String messageId, {bool animate = true}) {
    _animatedMessageCleanupTimer?.cancel();
    _animatedMessageId = messageId;
    _skipNextMessageEntryAnimation = !animate;
    _animatedMessageCleanupTimer = Timer(
      _sentMessageEntryDuration + const Duration(milliseconds: 140),
      () {
        if (!mounted || _animatedMessageId != messageId) {
          return;
        }
        setState(() {
          _animatedMessageId = null;
          _skipNextMessageEntryAnimation = false;
        });
      },
    );
  }

  bool _isNearLatestMessage({double tolerance = 24}) {
    if (!_messageListController.hasClients) {
      return true;
    }
    // reverse:true: the newest message is at offset 0, so "near the latest"
    // means near offset 0.
    return _messageListController.offset.abs() <= tolerance;
  }

  /// Newest-first order for the reverse:true [ListView.builder] so scroll
  /// offset 0 sits on the latest message at the bottom without a jump on open.
  List<ChatMessage> _displayMessagesForList(List<ChatMessage> messages) {
    if (messages.length <= 1) {
      return messages;
    }
    return messages.reversed.toList(growable: false);
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

    // Hide at most one server echo per in-flight local send. Never hide
    // older same-text bubbles -- that was dropping visible history when
    // users spammed similar test messages after a media attachment.
    final hiddenEchoIds = <String>{};
    for (final localMessage in _localMessages) {
      if (localMessage.deliveryState != MessageDeliveryState.sending) {
        continue;
      }
      final echo = _findPersistedMatch(thread, localMessage);
      if (echo != null) {
        hiddenEchoIds.add(echo.id);
      }
    }

    final serverMessages = thread.messages.where(
      (message) => !hiddenEchoIds.contains(message.id),
    );

    return List<ChatMessage>.unmodifiable([
      ...serverMessages,
      ..._localMessages,
    ]);
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
    _beginOutboundSend(threadId: threadId, localMessage: sendingMessage);
    if (mounted) {
      setState(() {});
    }
    _scrollToLatestIfNeeded(wasNearLatest: wasNearLatest);

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
      final thread = widget.controller.threadById(threadId);
      if (thread != null) {
        _finalizeOutgoingSend(thread: thread, localMessage: failedMessage);
      } else {
        _endOutboundSend();
        _removeLocalMessage(failedMessage.id);
      }
    } else {
      _endOutboundSend();
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
        _startEditingMessage(message);
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
      // Reply and edit are mutually exclusive; starting a reply drops any
      // in-progress edit and its prefilled draft.
      if (_editingMessage != null) {
        _editingMessage = null;
        _composerController.clear();
      }
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

  /// Enters WhatsApp-style inline edit: prefill the composer with the
  /// message text, focus it, and show the "Editing message" bar. The actual
  /// save runs through [_saveEdit] when the send/save button is tapped.
  void _startEditingMessage(ChatMessage message) {
    setState(() {
      _pendingReply = null;
      _editingMessage = message;
      _composerController.text = message.text;
      _composerController.selection = TextSelection.collapsed(
        offset: _composerController.text.length,
      );
    });
    _composerFocusNode.requestFocus();
  }

  void _cancelEditing() {
    setState(() {
      _editingMessage = null;
      _composerController.clear();
    });
  }

  /// Commits the in-progress inline edit (called from [_handleSendTap] when
  /// [_editingMessage] is set). Clears the editing state, then persists via
  /// the controller; a no-op edit (unchanged/empty text) just closes.
  Future<void> _saveEdit(String threadId) async {
    final message = _editingMessage;
    if (message == null) {
      return;
    }
    final trimmed = _composerController.text.trim();
    _cancelEditing();
    if (trimmed.isEmpty || trimmed == message.text.trim()) {
      return;
    }
    final didEdit = await widget.controller.editMessage(
      threadId: threadId,
      messageId: message.id,
      text: trimmed,
    );
    if (!didEdit && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.errorMessage ??
                'We could not edit that message right now.',
          ),
        ),
      );
    }
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

    // reverse:true: the newest message sits at scroll offset 0.
    const targetOffset = 0.0;
    final distance = _messageListController.offset.abs();
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
      avatarUrl: thread.isGroup ? null : thread.avatarUrl,
      memberUids: thread.isGroup ? thread.otherMemberUids(currentUid) : null,
      memberDisplayNames: thread.isGroup
          ? <String, String>{
              for (final participant in thread.participants ?? const [])
                participant.uid: participant.name,
            }
          : null,
      memberAvatarUrls: thread.isGroup
          ? <String, String>{
              for (final participant in thread.participants ?? const [])
                if (participant.avatarUrl?.trim().isNotEmpty ?? false)
                  participant.uid: participant.avatarUrl!.trim(),
            }
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

    return null;
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

/// The "Editing message" bar shown above the composer while an inline edit is
/// in progress (see [_startEditingMessage]) -- mirrors [_ReplyPreviewBar] but
/// with a pencil affordance and the original text as the preview.
class _EditingBar extends StatelessWidget {
  const _EditingBar({
    required this.message,
    required this.onCancel,
  });

  final ChatMessage message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('conversation_editing_bar'),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      color: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.3 : 0.5,
      ),
      child: Row(
        children: [
          Icon(
            Icons.edit_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Editing message',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  message.text,
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
            key: const Key('conversation_cancel_edit_button'),
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
class _ConversationAppBarHost extends StatelessWidget
    implements PreferredSizeWidget {
  const _ConversationAppBarHost({required this.state});

  final _ConversationScreenState state;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        state.widget.controller,
        state.widget.updatesController,
      ]),
      builder: (context, _) {
        final thread =
            state.widget.controller.threadById(state.widget.threadId);
        return state._buildConversationAppBar(context, thread);
      },
    );
  }
}

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

class _ComposerBar extends StatefulWidget {
  const _ComposerBar({
    required this.composerBarKey,
    required this.threadId,
    required this.controller,
    required this.isBusy,
    required this.lockedMinHeight,
    required this.onAttachmentTap,
    required this.onSendTap,
    required this.onVoiceRecorded,
    this.focusNode,
  });

  final GlobalKey composerBarKey;
  final String threadId;
  final TextEditingController controller;
  final bool isBusy;
  final double? lockedMinHeight;
  final ValueChanged<ChatAttachmentType> onAttachmentTap;
  final VoidCallback onSendTap;
  final ValueChanged<ChatAttachment> onVoiceRecorded;
  final FocusNode? focusNode;

  @override
  State<_ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends State<_ComposerBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleComposerDraftChanged);
    widget.focusNode?.addListener(_handleComposerDraftChanged);
  }

  @override
  void didUpdateWidget(covariant _ComposerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleComposerDraftChanged);
      widget.controller.addListener(_handleComposerDraftChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleComposerDraftChanged);
      widget.focusNode?.addListener(_handleComposerDraftChanged);
    }
    if (oldWidget.isBusy != widget.isBusy) {
      _handleComposerDraftChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleComposerDraftChanged);
    widget.focusNode?.removeListener(_handleComposerDraftChanged);
    super.dispose();
  }

  void _handleComposerDraftChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _canSendText =>
      widget.controller.text.trim().isNotEmpty && !widget.isBusy;

  @override
  Widget build(BuildContext context) {
    return _ComposerBarContent(
      composerBarKey: widget.composerBarKey,
      threadId: widget.threadId,
      controller: widget.controller,
      focusNode: widget.focusNode,
      isBusy: widget.isBusy,
      canSendText: _canSendText,
      lockedMinHeight: widget.lockedMinHeight,
      onAttachmentTap: widget.onAttachmentTap,
      onSendTap: widget.onSendTap,
      onVoiceRecorded: widget.onVoiceRecorded,
      onComposerDraftChanged: _handleComposerDraftChanged,
    );
  }
}

class _ComposerBarContent extends StatelessWidget {
  const _ComposerBarContent({
    required this.composerBarKey,
    required this.threadId,
    required this.controller,
    required this.isBusy,
    required this.canSendText,
    required this.lockedMinHeight,
    required this.onAttachmentTap,
    required this.onSendTap,
    required this.onVoiceRecorded,
    required this.onComposerDraftChanged,
    this.focusNode,
  });

  final GlobalKey composerBarKey;
  final String threadId;
  final TextEditingController controller;
  final bool isBusy;
  final bool canSendText;
  final double? lockedMinHeight;
  final ValueChanged<ChatAttachmentType> onAttachmentTap;
  final VoidCallback onSendTap;
  final ValueChanged<ChatAttachment> onVoiceRecorded;
  final VoidCallback onComposerDraftChanged;
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
      // 4 rows + 3 hairline dividers -- voice moved to the composer bar.
      const popupHeight = 192.0;
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
              onChanged: (_) => onComposerDraftChanged(),
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
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
          const SizedBox(width: 10),
          if (canSendText)
            LiquidGlassIconButton(
              key: const ValueKey('composer_send_action'),
              actionKey: const Key('conversation_send_button'),
              icon: Icons.send_rounded,
              size: 48,
              blurred: false,
              selected: true,
              iconColor: theme.colorScheme.primary,
              borderColor:
                  theme.colorScheme.outlineVariant.withValues(alpha: 0.34),
              onTap: !isBusy ? onSendTap : null,
              child: isBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : null,
            )
          else
            ComposerVoiceButton(
              key: const Key('conversation_voice_button'),
              threadId: threadId,
              enabled: !isBusy,
              onRecorded: onVoiceRecorded,
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

class _KeepAliveMessageItem extends StatefulWidget {
  const _KeepAliveMessageItem({required this.child});

  final Widget child;

  @override
  State<_KeepAliveMessageItem> createState() => _KeepAliveMessageItemState();
}

class _KeepAliveMessageItemState extends State<_KeepAliveMessageItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// WhatsApp-style swipe-right-to-reply. A horizontal drag translates the
/// message and reveals a reply glyph; releasing past the threshold fires
/// [onReply], then the bubble springs back. A custom translation (rather than
/// Dismissible) is used so the reaction badge that overflows below the bubble
/// is never clipped.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
    required this.onReply,
    required this.child,
    super.key,
  });

  final VoidCallback onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  static const double _maxDrag = 80;
  static const double _triggerAt = 52;

  late final AnimationController _spring;
  double _dragX = 0;
  double _springFrom = 0;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        setState(() {
          _dragX = _springFrom * (1 - Curves.easeOut.transform(_spring.value));
        });
      });
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails details) {
    if (_spring.isAnimating) {
      _spring.stop();
    }
    setState(() {
      _dragX = (_dragX + details.delta.dx).clamp(0.0, _maxDrag);
    });
  }

  void _onEnd(DragEndDetails details) {
    final shouldReply = _dragX >= _triggerAt;
    _springFrom = _dragX;
    _spring.forward(from: 0);
    if (shouldReply) {
      widget.onReply();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (_dragX / _triggerAt).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      child: Stack(
        children: [
          if (_dragX > 2)
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: progress,
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * progress,
                    child: Icon(
                      Icons.reply_rounded,
                      size: 22,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragX, 0),
            child: widget.child,
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
    this.highlightMessageIdNotifier,
    this.onReplyPreviewTap,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onToggleSelection,
  });

  /// The bubble is capped at 320 wide (see the ConstrainedBox in build) and
  /// carries 10px of horizontal padding on each side, so its text has 300px
  /// to lay out in -- the width handed to the inline-meta Text so it wraps.
  static const double _bubbleTextMaxWidth = 300;

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
  final ValueNotifier<String?>? highlightMessageIdNotifier;
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
    if (highlightMessageIdNotifier == null) {
      return _buildWithHighlight(context, isHighlighted: false);
    }
    return ValueListenableBuilder<String?>(
      valueListenable: highlightMessageIdNotifier!,
      builder: (context, highlightedId, _) {
        return _buildWithHighlight(
          context,
          isHighlighted: highlightedId == message.id,
        );
      },
    );
  }

  Widget _buildWithHighlight(
    BuildContext context, {
    required bool isHighlighted,
  }) {
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
                      // No border in the resting state -- WhatsApp's own
                      // bubbles are flat fills with no outline; a border on
                      // every bubble was what made each message read as its
                      // own separate "framed" card instead of a normal chat
                      // bubble. Kept only for states that need to visually
                      // stand out (a failed send, a search-jump highlight).
                      border: isHighlighted
                          ? Border.all(
                              width: 2,
                              color: theme.colorScheme.primary,
                            )
                          : isFailed
                              ? Border.all(
                                  width: 1,
                                  color: theme.colorScheme.error
                                      .withValues(alpha: 0.22),
                                )
                              : null,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMine ? 18 : 5),
                        bottomRight: Radius.circular(isMine ? 5 : 18),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (thread.isGroup && !isMine)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              message.senderName,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: thread.accentColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (message.isDeleted)
                          _textWithInlineMeta(
                            context,
                            text: 'This message was deleted',
                            contentColor: contentColor,
                            maxTextWidth: _bubbleTextMaxWidth,
                            textStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: contentColor.withValues(alpha: 0.6),
                              fontStyle: FontStyle.italic,
                              height: 1.28,
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
                            const SizedBox(height: 4),
                          ],
                          if (message.hasStoryReplyContext) ...[
                            _StoryReplyCard(
                              replyContext: message.storyReplyContext!,
                              isAvailable: isStoryReplyAvailable,
                              onTap: onStoryReplyCardTap,
                            ),
                            const SizedBox(height: 4),
                          ],
                          // Timestamp placement, one consistent rule:
                          //  * a plain text message hugs its text, so tucking
                          //    the time inline right after it already lands it
                          //    at the bubble's right edge (see
                          //    _textWithInlineMeta);
                          //  * every wider bubble -- any attachment (with or
                          //    without a caption) and card-only bubbles -- puts
                          //    the time on its own line, right-aligned. No
                          //    baseline-matching a short caption against the
                          //    time on a shared row (which read as uneven
                          //    padding); the caption simply sits above.
                          if (message.hasAttachments) ...[
                            _buildAttachmentsContent(context),
                            const SizedBox(height: 4),
                            if (message.hasText)
                              // Caption with the time tucked inline bottom-
                              // right -- same line when it fits, end of the
                              // last line when it wraps.
                              _captionWithInlineMeta(
                                context,
                                caption: message.text,
                                contentColor: contentColor,
                                captionStyle:
                                    theme.textTheme.bodyMedium?.copyWith(
                                  color: contentColor,
                                  height: 1.28,
                                ),
                              )
                            else
                              // Attachment with no caption: time on its own
                              // right-aligned line.
                              Align(
                                alignment: Alignment.centerRight,
                                child: _metaRow(context, contentColor),
                              ),
                          ] else if (message.hasText)
                            _textWithInlineMeta(
                              context,
                              text: message.text,
                              contentColor: contentColor,
                              maxTextWidth: _bubbleTextMaxWidth,
                              textStyle: theme.textTheme.bodyMedium?.copyWith(
                                color: contentColor,
                                height: 1.28,
                              ),
                            )
                          else
                            // Card-only bubble (reply/story quote, no text or
                            // media): time on its own right-aligned line.
                            Align(
                              alignment: Alignment.centerRight,
                              child: _metaRow(context, contentColor),
                            ),
                        ],
                        if (isMine && isFailed) ...[
                          const SizedBox(height: 6),
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
                    // The badge (~26px tall with the 20px glyph) hangs in the
                    // gutter below the bubble -- its top lands ~2px below the
                    // last text line, so it never covers the message. -22 with
                    // a 30px reserved gap below (see the message list's
                    // SizedBox) keeps it clear of both this bubble's last line
                    // and the next message.
                    bottom: -22,
                    // Inset a touch from the bubble's left corner (not past
                    // it) so it reads as attached to the bubble; the trailer
                    // row above always right-aligns, so the left side never
                    // collides with the timestamp.
                    left: 6,
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

  /// The compact time + delivery-state trailer that WhatsApp tucks into the
  /// bottom-right of a bubble. Kept small and low-contrast so it reads as
  /// metadata, not content.
  Widget _metaRow(BuildContext context, Color contentColor) {
    final theme = Theme.of(context);
    final isMine = message.isFromCurrentUser;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.isEdited && !message.isDeleted) ...[
          Text(
            'Edited',
            style: theme.textTheme.labelSmall?.copyWith(
              color: contentColor.withValues(alpha: 0.55),
              fontStyle: FontStyle.italic,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 5),
        ],
        if (message.isStarred && !message.isDeleted) ...[
          Icon(
            Icons.star_rounded,
            size: 12,
            color: contentColor.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 3),
        ],
        Text(
          _timeLabelFor(message.sentAt),
          style: theme.textTheme.labelSmall?.copyWith(
            color: contentColor.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
        if (isMine) ...[
          const SizedBox(width: 4),
          Icon(
            _deliveryIcon(message.deliveryState),
            size: 14,
            color: switch (message.deliveryState) {
              MessageDeliveryState.read => AppPalette.green,
              MessageDeliveryState.failed => theme.colorScheme.error,
              _ => contentColor.withValues(alpha: 0.72),
            },
          ),
        ],
      ],
    );
  }

  /// Message text with the time/ticks tucked inline at the end, WhatsApp
  /// style. A [Wrap] keeps the trailer on the same line as short messages
  /// (the common case) so the bubble is two lines tall instead of three;
  /// the [ConstrainedBox] gives the [Text] the bubble's own max content
  /// width so long messages still wrap (a bare Text inside a Wrap would be
  /// handed unbounded width and refuse to wrap), and the trailer drops to a
  /// tight line of its own only when the text actually fills the width.
  Widget _textWithInlineMeta(
    BuildContext context, {
    required String text,
    required TextStyle? textStyle,
    required Color contentColor,
    required double maxTextWidth,
  }) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 8,
      runSpacing: 2,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxTextWidth),
          child: Text(text, style: textStyle),
        ),
        _metaRow(context, contentColor),
      ],
    );
  }

  /// Roughly how wide [_metaRow] renders, so a caption can reserve room for
  /// it on its last line. Measured (not guessed) for the time text, plus the
  /// fixed widths/gaps of the optional edited label, star, and delivery tick
  /// exactly as [_metaRow] lays them out. Over-reserving slightly is fine
  /// (a hair of extra gap); under-reserving would let text slide under the
  /// timestamp, so a small safety margin is added.
  double _metaRowWidth(BuildContext context) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String value, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      return painter.width;
    }

    var width = measure(
      _timeLabelFor(message.sentAt),
      theme.textTheme.labelSmall?.copyWith(fontSize: 11),
    );
    if (message.isEdited && !message.isDeleted) {
      width += measure(
            'Edited',
            theme.textTheme.labelSmall
                ?.copyWith(fontSize: 11, fontStyle: FontStyle.italic),
          ) +
          5;
    }
    if (message.isStarred && !message.isDeleted) {
      width += 12 + 3;
    }
    if (message.isFromCurrentUser) {
      width += 4 + 14;
    }
    return width + 8;
  }

  /// An attachment caption with the timestamp tucked inline at the bottom-
  /// right, WhatsApp style: on the same line as a short caption, or at the
  /// end of the last line when the caption wraps. The caption fills the media
  /// width (minus a reserved strip on the right) so the overlaid [_metaRow]
  /// lands at the bubble's right edge and wrapped text never slides under it.
  /// Kept as a plain [Text] (not [Text.rich]) so `find.text` still locates
  /// captioned-attachment messages in widget tests.
  Widget _captionWithInlineMeta(
    BuildContext context, {
    required String caption,
    required TextStyle? captionStyle,
    required Color contentColor,
  }) {
    final reservedWidth = _metaRowWidth(context);
    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(right: reservedWidth),
            child: SizedBox(
              width: double.infinity,
              child: Text(caption, style: captionStyle),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: _metaRow(context, contentColor),
          ),
        ],
      ),
    );
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
      // The map has a fixed 1.45 aspect ratio, so at the bubble's ~300px
      // content width its natural height is ~207. The height cap has to sit
      // above that (240) or it clamps the height first and the map ends up
      // narrower than the bubble -- which left a gap on its right once the
      // timestamp row stretched the bubble to full width. With the cap
      // above the natural height, width binds and the map fills the bubble.
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('attachment_preview_${attachment.id}'),
              onTap: () => onAttachmentTap(attachment),
              child: LazyLocationMapSnippet(
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
            padding: const EdgeInsets.all(5),
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
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(
                    width: 30,
                    height: 38,
                    child: _buildThumbnail(theme),
                  ),
                ),
                const SizedBox(width: 8),
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
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final emoji in distinctEmojis)
              // A comfortably-sized glyph with a tight line box (height: 1)
              // so it sits centred in the pill rather than riding high with
              // the default line spacing above/below it. The Positioned offset
              // where this badge is placed is tuned to this size so the taller
              // pill still clears the message text.
              Text(
                emoji,
                style: const TextStyle(fontSize: 20, height: 1),
              ),
            if (reactions.length > 1) ...[
              const SizedBox(width: 3),
              Text(
                '${reactions.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  height: 1,
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
class _MediaAttachmentTile extends StatefulWidget {
  const _MediaAttachmentTile({
    required this.attachment,
    required this.onTap,
    this.aspectRatio,
  });

  final ChatAttachment attachment;
  final VoidCallback onTap;
  final double? aspectRatio;

  @override
  State<_MediaAttachmentTile> createState() => _MediaAttachmentTileState();
}

class _MediaAttachmentTileState extends State<_MediaAttachmentTile> {
  Future<Uint8List?>? _videoThumbnailFuture;

  @override
  void initState() {
    super.initState();
    final localPath = widget.attachment.localMediaPath;
    if (widget.attachment.type == ChatAttachmentType.video &&
        localPath != null &&
        statusMediaSourceExists(localPath)) {
      _videoThumbnailFuture = videoThumbnailFor(localPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final localPath = attachment.localMediaPath;
    final isPhoto = attachment.type == ChatAttachmentType.photo ||
        attachment.isImageDocument;
    final hasRealPhoto =
        isPhoto && localPath != null && statusMediaSourceExists(localPath);
    final hasRealVideo = attachment.type == ChatAttachmentType.video &&
        localPath != null &&
        statusMediaSourceExists(localPath);
    final resolvedAspectRatio =
        (widget.aspectRatio ?? attachment.aspectRatio).clamp(0.7, 1.5);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('attachment_preview_${attachment.id}'),
          onTap: widget.onTap,
          child: AspectRatio(
            aspectRatio: resolvedAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasRealPhoto)
                  Image(
                    image: imageProviderForStatusMediaPath(localPath)!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
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
                    future: _videoThumbnailFuture,
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
      color: widget.attachment.tintColor.withValues(alpha: 0.18),
      child: Center(
        child: Icon(
          widget.attachment.type == ChatAttachmentType.video
              ? Icons.videocam_outlined
              : Icons.photo_outlined,
          color: widget.attachment.tintColor,
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
      color: widget.attachment.tintColor.withValues(alpha: 0.18),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: widget.attachment.tintColor,
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
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: iconColor.withValues(alpha: 0.16),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
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

/// Small spinner shown at the top of the message list while an older page is
/// being fetched (see windowed pagination in ChatsController).
class _OlderMessagesLoader extends StatelessWidget {
  const _OlderMessagesLoader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      ),
    );
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
