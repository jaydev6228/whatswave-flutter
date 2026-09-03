import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show Color;

import '../../features/auth/data/auth_repository.dart';
import '../../features/calls/data/calls_overview.dart';
import '../../features/calls/data/calls_repository.dart';
import '../../features/calls/domain/call_history_entry.dart';
import '../media/media_transfer.dart';
import '../../features/chats/data/chat_repository.dart';
import '../../features/chats/domain/chat_attachment.dart';
import '../../features/chats/domain/chat_attachment.dart' as chat_attachment;
import '../../features/chats/domain/chat_message.dart';
import '../../features/chats/domain/chat_thread.dart';
import '../../features/chats/domain/message_reply_preview.dart';
import '../../features/chats/domain/story_reply_context.dart';
import '../../features/communities/data/communities_overview.dart';
import '../../features/communities/data/communities_repository.dart';
import '../../features/updates/data/updates_repository.dart';
import '../../features/updates/data/updates_repository.dart' as updates_data;
import '../../core/models/app_user.dart';
import '../../core/models/status_story.dart';
import '../../core/models/story_viewer.dart';
import '../utils/user_profile_lookup.dart';
import 'integration_hub_controller.dart';

class TrackedAuthRepository implements AuthRepository {
  TrackedAuthRepository({
    required AuthRepository delegate,
    required IntegrationHubController integrations,
  })  : _delegate = delegate,
        _integrations = integrations;

  final AuthRepository _delegate;
  final IntegrationHubController _integrations;

  @override
  Future<AppUser?> restoreSession() async {
    try {
      final user = await _delegate.restoreSession();
      if (user != null) {
        unawaited(
          _integrations.recordSyncSuccess(
            source: 'Auth',
            title: 'Session restored',
            details: user.phoneNumber,
          ),
        );
      }
      return user;
    } on AuthException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Auth',
          title: 'Session restore failed',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Auth',
          title: 'Session restore failed',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> requestOtp(String phoneNumber) async {
    try {
      await _delegate.requestOtp(phoneNumber);
      unawaited(
        _integrations.recordSyncSuccess(
          source: 'Auth',
          title: 'Verification code requested',
          details: phoneNumber,
        ),
      );
    } on AuthException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Auth',
          title: 'Verification code request failed',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Auth',
          title: 'Verification code request failed',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<AuthVerificationResult> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    try {
      final result = await _delegate.verifyOtp(
        phoneNumber: phoneNumber,
        code: code,
      );
      unawaited(
        _integrations.recordSyncSuccess(
          source: 'Auth',
          title: result.needsProfile ? 'Number verified' : 'Signed in',
          details: phoneNumber,
        ),
      );
      return result;
    } on AuthException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Auth',
          title: 'Verification failed',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Auth',
          title: 'Verification failed',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<AppUser> completeProfile({
    required String phoneNumber,
    required String name,
    required String about,
  }) async {
    try {
      final user = await _delegate.completeProfile(
        phoneNumber: phoneNumber,
        name: name,
        about: about,
      );
      unawaited(
        _integrations.recordSyncSuccess(
          source: 'Auth',
          title: 'Profile created',
          details: user.name,
        ),
      );
      return user;
    } on AuthException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Auth',
          title: 'Profile creation failed',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Auth',
          title: 'Profile creation failed',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<AppUser> updateCurrentProfile({
    required String name,
    required String about,
  }) async {
    try {
      final user = await _delegate.updateCurrentProfile(
        name: name,
        about: about,
      );
      unawaited(
        _integrations.recordSyncSuccess(
          source: 'Auth',
          title: 'Profile updated',
          details: user.name,
        ),
      );
      return user;
    } on AuthException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Auth',
          title: 'Profile update failed',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Auth',
          title: 'Profile update failed',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<AppUser> updateAvatar(File photo) async {
    try {
      final user = await _delegate.updateAvatar(photo);
      unawaited(
        _integrations.recordSyncSuccess(
          source: 'Auth',
          title: 'Profile photo updated',
          details: user.name,
        ),
      );
      return user;
    } on AuthException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Auth',
          title: 'Profile photo update failed',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Auth',
          title: 'Profile photo update failed',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<AppUser> deleteAvatar() {
    return _delegate.deleteAvatar();
  }

  @override
  Future<void> signOut() async {
    try {
      await _delegate.signOut();
      unawaited(
        _integrations.recordSyncSuccess(
          source: 'Auth',
          title: 'Signed out',
        ),
      );
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Auth',
          title: 'Sign out failed',
        ),
      );
      rethrow;
    }
  }
}

class TrackedChatRepository implements ChatRepository {
  TrackedChatRepository({
    required ChatRepository delegate,
    required IntegrationHubController integrations,
  })  : _delegate = delegate,
        _integrations = integrations;

  final ChatRepository _delegate;
  final IntegrationHubController _integrations;

  @override
  String get currentUserReactionKey => _delegate.currentUserReactionKey;

  @override
  Future<List<ChatThread>> fetchThreads() => _delegate.fetchThreads();

  @override
  Future<ChatThread> fetchThreadWithMessages(String threadId) =>
      _delegate.fetchThreadWithMessages(threadId);

  @override
  Future<ChatMessagePage> fetchThreadMessagesPage({
    required String threadId,
    int limit = 50,
    ChatMessage? before,
  }) =>
      _delegate.fetchThreadMessagesPage(
        threadId: threadId,
        limit: limit,
        before: before,
      );

  @override
  Stream<List<ChatThread>>? watchThreads() => _delegate.watchThreads();

  @override
  Future<List<ChatThread>> deleteThread(String threadId) =>
      _delegate.deleteThread(threadId);

  @override
  Future<ChatThread> startThread({
    required String participantUid,
    required String participantName,
    required String avatarLabel,
    required Color accentColor,
  }) {
    return _delegate.startThread(
      participantUid: participantUid,
      participantName: participantName,
      avatarLabel: avatarLabel,
      accentColor: accentColor,
    );
  }

  @override
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
    bool isCommunityGroup = false,
    bool isAnnouncementOnly = false,
  }) {
    return _delegate.createGroup(
      name: name,
      memberUids: memberUids,
      isCommunityGroup: isCommunityGroup,
      isAnnouncementOnly: isAnnouncementOnly,
    );
  }

  @override
  Future<List<ChatThread>> addGroupMembers({
    required String threadId,
    required List<String> memberUids,
  }) {
    return _delegate.addGroupMembers(
        threadId: threadId, memberUids: memberUids);
  }

  @override
  Future<List<ChatThread>> removeGroupMember({
    required String threadId,
    required String memberUid,
  }) {
    return _delegate.removeGroupMember(
        threadId: threadId, memberUid: memberUid);
  }

  @override
  Future<List<ChatThread>> leaveGroup(String threadId) {
    return _delegate.leaveGroup(threadId);
  }

  @override
  Future<List<ChatThread>> setGroupAdmin({
    required String threadId,
    required String memberUid,
    required bool isAdmin,
  }) {
    return _delegate.setGroupAdmin(
      threadId: threadId,
      memberUid: memberUid,
      isAdmin: isAdmin,
    );
  }

  @override
  Future<List<ChatThread>> renameGroup({
    required String threadId,
    required String name,
  }) {
    return _delegate.renameGroup(threadId: threadId, name: name);
  }

  @override
  Future<List<ChatThread>> updateGroupDescription({
    required String threadId,
    required String description,
  }) {
    return _delegate.updateGroupDescription(
      threadId: threadId,
      description: description,
    );
  }

  @override
  Future<List<ChatThread>> updateGroupAvatar({
    required String threadId,
    required File photo,
  }) {
    return _delegate.updateGroupAvatar(threadId: threadId, photo: photo);
  }

  @override
  Future<List<ChatThread>> deleteGroupAvatar(String threadId) {
    return _delegate.deleteGroupAvatar(threadId);
  }

  @override
  Future<List<ChatThread>> setThreadArchived({
    required String threadId,
    required bool isArchived,
  }) {
    return _delegate.setThreadArchived(
      threadId: threadId,
      isArchived: isArchived,
    );
  }

  @override
  Future<void> markThreadRead(String threadId) {
    return _delegate.markThreadRead(threadId);
  }

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
    StoryReplyContext? storyReplyContext,
    MessageReplyPreview? replyPreview,
  }) async {
    try {
      final threads = await _delegate.sendTextMessage(
        threadId: threadId,
        text: text,
        storyReplyContext: storyReplyContext,
        replyPreview: replyPreview,
      );
      unawaited(
        _integrations.recordSyncSuccess(
          source: 'Chats',
          title: 'Message synced',
          details: text,
        ),
      );
      return threads;
    } on ChatRepositoryException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Chats',
          title: 'Message failed to sync',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Chats',
          title: 'Message failed to sync',
        ),
      );
      rethrow;
    }
  }

  // Not wrapped with sync-success/failure tracking like the other mutating
  // methods here -- reacting is a lightweight, frequent interaction, not a
  // content-sync event worth surfacing in the integration hub's log.
  @override
  Future<List<ChatThread>> toggleMessageReaction({
    required String threadId,
    required String messageId,
    required String emoji,
  }) {
    return _delegate.toggleMessageReaction(
      threadId: threadId,
      messageId: messageId,
      emoji: emoji,
    );
  }

  @override
  Future<List<ChatThread>> toggleMessageStar({
    required String threadId,
    required String messageId,
  }) {
    return _delegate.toggleMessageStar(
        threadId: threadId, messageId: messageId);
  }

  @override
  Future<List<StarredMessageEntry>> fetchStarredMessages() {
    return _delegate.fetchStarredMessages();
  }

  @override
  Future<List<ChatThread>> editMessage({
    required String threadId,
    required String messageId,
    required String text,
  }) {
    return _delegate.editMessage(
      threadId: threadId,
      messageId: messageId,
      text: text,
    );
  }

  @override
  Future<List<ChatThread>> deleteMessage({
    required String threadId,
    required String messageId,
    required bool forEveryone,
  }) {
    return _delegate.deleteMessage(
      threadId: threadId,
      messageId: messageId,
      forEveryone: forEveryone,
    );
  }

  @override
  Future<List<ChatThread>> setThreadBlocked({
    required String threadId,
    required bool isBlocked,
  }) {
    return _delegate.setThreadBlocked(
      threadId: threadId,
      isBlocked: isBlocked,
    );
  }

  @override
  Future<List<ChatThread>> clearThreadMessages(String threadId) {
    return _delegate.clearThreadMessages(threadId);
  }

  @override
  Future<List<ChatThread>> groupThreadsSharedWith(String participantUid) {
    return _delegate.groupThreadsSharedWith(participantUid);
  }

  @override
  Future<UserProfileSnapshot?> fetchContactProfile(String uid) {
    return _delegate.fetchContactProfile(uid);
  }

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
    MessageReplyPreview? replyPreview,
    MediaTransfer? transfer,
  }) async {
    final combinedLabel = attachments.length == 1
        ? attachments.single.compactLabel
        : '${attachments.length} attachments';
    final List<ChatThread> threads;
    try {
      // The real send happens first, unconditionally -- queueMediaTransfer
      // below is a demo/telemetry recording for the "Backend and sync"
      // activity feed, not a real upload of anything. It must never gate
      // whether the actual message goes out: it previously ran BEFORE this
      // call and threw if a manually-maintained "is Storage ready" flag
      // happened to be stale, which silently blocked every photo/video/
      // document/voice-note/location send regardless of whether Storage
      // itself was actually working.
      threads = await _delegate.sendAttachmentMessage(
        threadId: threadId,
        attachments: attachments,
        caption: caption,
        replyPreview: replyPreview,
      );
    } on ChatRepositoryException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Chats',
          title: 'Attachment failed to sync',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Chats',
          title: 'Attachment failed to sync',
        ),
      );
      rethrow;
    }

    for (final attachment in attachments) {
      unawaited(
        _integrations.queueMediaTransfer(
          source: 'Chats',
          label: attachment.compactLabel,
          kind: _kindForChatAttachment(attachment.type),
        ),
      );
    }
    unawaited(
      _integrations.recordSyncSuccess(
        source: 'Chats',
        title: 'Attachment synced',
        details: combinedLabel,
      ),
    );
    return threads;
  }
}

class TrackedUpdatesRepository implements UpdatesRepository {
  TrackedUpdatesRepository({
    required UpdatesRepository delegate,
    required IntegrationHubController integrations,
  })  : _delegate = delegate,
        _integrations = integrations;

  final UpdatesRepository _delegate;
  final IntegrationHubController _integrations;

  @override
  Future<updates_data.UpdatesFeed> fetchUpdates() => _delegate.fetchUpdates();

  @override
  Stream<updates_data.UpdatesFeed>? watchUpdates() => _delegate.watchUpdates();

  @override
  Future<List<StatusStory>> createStatus({
    required StatusStoryType type,
    String? caption,
    String? localMediaPath,
    StatusTextStyle? textStyle,
    StatusMediaTransform? mediaTransform,
    List<StatusMediaOverlayItem>? overlayItems,
    String? emoji,
    List<String>? stickers,
    StatusMusicTrack? musicTrack,
    int? durationMillis,
    int? trimStartMillis,
    List<StatusDrawingStroke>? drawingStrokes,
  }) async {
    final List<StatusStory> stories;
    try {
      // The real post happens first, unconditionally -- see the matching
      // comment on TrackedChatRepository.sendAttachmentMessage for why
      // queueMediaTransfer must never run (and gate) before this.
      stories = await _delegate.createStatus(
        type: type,
        caption: caption,
        localMediaPath: localMediaPath,
        textStyle: textStyle,
        mediaTransform: mediaTransform,
        overlayItems: overlayItems,
        emoji: emoji,
        stickers: stickers,
        musicTrack: musicTrack,
        durationMillis: durationMillis,
        trimStartMillis: trimStartMillis,
        drawingStrokes: drawingStrokes,
      );
    } on UpdatesRepositoryException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Updates',
          title: 'Status failed to sync',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Updates',
          title: 'Status failed to sync',
        ),
      );
      rethrow;
    }

    if (type == StatusStoryType.photo || type == StatusStoryType.video) {
      unawaited(
        _integrations.queueMediaTransfer(
          source: 'Updates',
          label: caption?.trim().isNotEmpty == true
              ? caption!.trim()
              : type == StatusStoryType.photo
                  ? 'New photo status'
                  : 'New video status',
          kind: type == StatusStoryType.photo
              ? MediaTransferKind.statusPhoto
              : MediaTransferKind.statusVideo,
        ),
      );
    }
    unawaited(
      _integrations.recordSyncSuccess(
        source: 'Updates',
        title: 'Status synced',
        details:
            caption?.trim().isNotEmpty == true ? caption!.trim() : type.name,
      ),
    );
    return stories;
  }

  @override
  Future<List<StatusStory>> markStoryViewed(
    String storyId, {
    required int seenSegments,
  }) {
    return _delegate.markStoryViewed(
      storyId,
      seenSegments: seenSegments,
    );
  }

  @override
  Future<List<StatusStory>> deleteStatusSegment({
    required String storyId,
    required String segmentId,
  }) {
    return _delegate.deleteStatusSegment(
      storyId: storyId,
      segmentId: segmentId,
    );
  }

  @override
  Future<List<StatusStory>> clearStory({
    required String storyId,
  }) {
    return _delegate.clearStory(storyId: storyId);
  }

  @override
  Future<List<StoryViewer>> fetchStoryViewers(String storyId) {
    return _delegate.fetchStoryViewers(storyId);
  }

  @override
  Future<bool> isStoryLikedByMe(
    String storyId, {
    required String segmentId,
  }) {
    return _delegate.isStoryLikedByMe(storyId, segmentId: segmentId);
  }

  @override
  Future<void> setStoryLiked(
    String storyId, {
    required String segmentId,
    required bool liked,
  }) {
    return _delegate.setStoryLiked(
      storyId,
      segmentId: segmentId,
      liked: liked,
    );
  }

  @override
  Stream<List<StoryViewer>>? watchStoryViewers(String storyId) {
    return _delegate.watchStoryViewers(storyId);
  }
}

class TrackedCommunitiesRepository implements CommunitiesRepository {
  TrackedCommunitiesRepository({
    required CommunitiesRepository delegate,
    required IntegrationHubController integrations,
  })  : _delegate = delegate,
        _integrations = integrations;

  final CommunitiesRepository _delegate;
  final IntegrationHubController _integrations;

  @override
  Future<CommunitiesOverview> fetchOverview() => _delegate.fetchOverview();

  @override
  Future<CommunitiesOverview> createCommunity({
    required String title,
    required String description,
  }) async {
    try {
      final overview = await _delegate.createCommunity(
        title: title,
        description: description,
      );
      unawaited(
        _integrations.recordSyncSuccess(
          source: 'Communities',
          title: 'Community created',
          details: title,
        ),
      );
      return overview;
    } on CommunitiesRepositoryException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Communities',
          title: 'Community creation failed',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Communities',
          title: 'Community creation failed',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<CommunitiesOverview> markCommunityOpened(String communityId) {
    return _delegate.markCommunityOpened(communityId);
  }

  @override
  Future<CommunitiesOverview> exitCommunity(String communityId) {
    return _delegate.exitCommunity(communityId);
  }

  @override
  Future<CommunitiesOverview> attachGroupThread({
    required String communityId,
    required String groupId,
    required String threadId,
  }) {
    return _delegate.attachGroupThread(
      communityId: communityId,
      groupId: groupId,
      threadId: threadId,
    );
  }

  @override
  Future<CommunitiesOverview> attachAnnouncementThread({
    required String communityId,
    required String threadId,
  }) {
    return _delegate.attachAnnouncementThread(
      communityId: communityId,
      threadId: threadId,
    );
  }

  @override
  Future<CommunitiesOverview> deactivateCommunity(String communityId) async {
    try {
      final overview = await _delegate.deactivateCommunity(communityId);
      unawaited(
        _integrations.recordSyncSuccess(
          source: 'Communities',
          title: 'Community deactivated',
        ),
      );
      return overview;
    } on CommunitiesRepositoryException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Communities',
          title: 'Community deactivation failed',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Communities',
          title: 'Community deactivation failed',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<CommunitiesOverview> inviteContactToCommunity({
    required String communityId,
    required String contactId,
  }) async {
    try {
      final overview = await _delegate.inviteContactToCommunity(
        communityId: communityId,
        contactId: contactId,
      );
      unawaited(
        _integrations.recordSyncSuccess(
          source: 'Communities',
          title: 'Community invite synced',
          details: contactId,
        ),
      );
      return overview;
    } on CommunitiesRepositoryException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Communities',
          title: 'Community invite failed',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Communities',
          title: 'Community invite failed',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<CommunitiesOverview> shareAppInvite(String contactId) async {
    try {
      final overview = await _delegate.shareAppInvite(contactId);
      unawaited(
        _integrations.recordSyncSuccess(
          source: 'Communities',
          title: 'App invite prepared',
          details: contactId,
        ),
      );
      return overview;
    } on CommunitiesRepositoryException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Communities',
          title: 'App invite failed',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Communities',
          title: 'App invite failed',
        ),
      );
      rethrow;
    }
  }

  @override
  Stream<void>? watchDeviceContactsChanged() =>
      _delegate.watchDeviceContactsChanged();
}

class TrackedCallsRepository implements CallsRepository {
  TrackedCallsRepository({
    required CallsRepository delegate,
    required IntegrationHubController integrations,
  })  : _delegate = delegate,
        _integrations = integrations;

  final CallsRepository _delegate;
  final IntegrationHubController _integrations;

  @override
  Future<CallsOverview> fetchOverview() => _delegate.fetchOverview();

  @override
  Future<List<CallHistoryEntry>> saveHistoryEntry(
      CallHistoryEntry entry) async {
    try {
      final history = await _delegate.saveHistoryEntry(entry);
      unawaited(
        _integrations.recordSyncSuccess(
          source: 'Calls',
          title: 'Call history synced',
          details: entry.name,
        ),
      );
      return history;
    } on CallsRepositoryException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Calls',
          title: 'Call history sync failed',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Calls',
          title: 'Call history sync failed',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<List<CallHistoryEntry>> deleteHistoryEntry(String entryId) async {
    try {
      final history = await _delegate.deleteHistoryEntry(entryId);
      unawaited(
        _integrations.recordSyncSuccess(
          source: 'Calls',
          title: 'Call deleted',
        ),
      );
      return history;
    } on CallsRepositoryException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Calls',
          title: 'Call delete failed',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Calls',
          title: 'Call delete failed',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<List<CallHistoryEntry>> clearHistory() async {
    try {
      final history = await _delegate.clearHistory();
      unawaited(
        _integrations.recordSyncSuccess(
          source: 'Calls',
          title: 'Call history cleared',
        ),
      );
      return history;
    } on CallsRepositoryException catch (error) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Calls',
          title: 'Call history clear failed',
          details: error.message,
        ),
      );
      rethrow;
    } catch (_) {
      unawaited(
        _integrations.recordSyncFailure(
          source: 'Calls',
          title: 'Call history clear failed',
        ),
      );
      rethrow;
    }
  }
}

MediaTransferKind _kindForChatAttachment(
  chat_attachment.ChatAttachmentType type,
) {
  return switch (type) {
    chat_attachment.ChatAttachmentType.photo => MediaTransferKind.photo,
    chat_attachment.ChatAttachmentType.video => MediaTransferKind.video,
    chat_attachment.ChatAttachmentType.file => MediaTransferKind.file,
    chat_attachment.ChatAttachmentType.location => MediaTransferKind.location,
    chat_attachment.ChatAttachmentType.voiceNote => MediaTransferKind.voiceNote,
  };
}
