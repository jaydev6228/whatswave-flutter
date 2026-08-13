import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../models/app_user.dart';
import '../models/channel_preview.dart';
import '../models/community_preview.dart';
import '../models/status_story.dart';
import '../../features/calls/domain/call_contact.dart';
import '../../features/calls/domain/call_history_entry.dart';
import '../../features/communities/domain/community_announcement.dart';
import '../../features/communities/domain/community_contact.dart';
import '../../features/communities/domain/community_group_preview.dart';
import '../../features/communities/domain/community_hub.dart';
import '../../features/chats/domain/chat_attachment.dart';
import '../../features/chats/domain/chat_message.dart';
import '../../features/chats/domain/chat_thread.dart';
import '../../features/chats/domain/group_participant.dart';

abstract final class DemoData {
  static const AppUser currentUser = AppUser(
    name: 'Jay Devra',
    phoneNumber: '+81 90 1234 5678',
    about: 'Building calm, reliable chat products one release at a time.',
    avatarLabel: 'JD',
    accentColor: AppPalette.emerald,
  );

  static const String _demoStatusLaunchCafeAsset =
      'asset://assets/media/status_demo/launch_cafe.jpg';
  static const String _demoStatusSunsetCityAsset =
      'asset://assets/media/status_demo/sunset_city.jpg';
  static const String _demoStatusSketchboardAsset =
      'asset://assets/media/status_demo/sketchboard.jpg';
  static const String _demoStatusCityWalkAsset =
      'asset://assets/media/status_demo/city_walk.mp4';
  static const StatusTextStyle _demoStoryTextStyle = StatusTextStyle(
    fontId: 'clean',
    backgroundId: 'midnight_drive',
    layout: StatusTextLayout.note,
    alignment: StatusTextAlignment.center,
    textColorValue: 0xFFFFFFFF,
    sizeScale: 0.94,
  );
  static const StatusMusicTrack _demoCityPulseTrack = StatusMusicTrack(
    id: 'city-pulse',
    title: 'City Pulse',
    artist: 'Whatswave House',
    colorValue: 0xFF25D366,
    secondaryColorValue: 0xFFD9FBE8,
    previewAssetPath: 'assets/audio/status_music/city_pulse.wav',
    bannerStyleId: 'pulse',
  );

  static List<ChatThread> buildChatThreads() {
    final now = DateTime.now();

    return List<ChatThread>.unmodifiable([
      ChatThread(
        id: 'ava-patel',
        name: 'Ava Patel',
        avatarLabel: 'AP',
        accentColor: AppPalette.green,
        unreadCount: 3,
        hasStory: true,
        messages: List<ChatMessage>.unmodifiable([
          ChatMessage(
            id: 'ava-1',
            senderName: 'Ava Patel',
            sentAt: now.subtract(const Duration(hours: 3, minutes: 40)),
            isFromCurrentUser: false,
            text:
                'The onboarding shots look good. The motion pacing feels much cleaner.',
          ),
          ChatMessage(
            id: 'ava-2',
            senderName: 'You',
            sentAt: now.subtract(const Duration(hours: 3, minutes: 25)),
            isFromCurrentUser: true,
            text: 'Sending the edited export now.',
            attachments: List<ChatAttachment>.unmodifiable([
              const ChatAttachment(
                id: 'ava-photo-1',
                type: ChatAttachmentType.photo,
                title: 'Onboarding board',
                details: '4-up polished photo set',
                tintColor: AppPalette.green,
                aspectRatio: 1.1,
              ),
            ]),
            deliveryState: MessageDeliveryState.read,
          ),
          ChatMessage(
            id: 'ava-3',
            senderName: 'Ava Patel',
            sentAt: now.subtract(const Duration(minutes: 18)),
            isFromCurrentUser: false,
            text: 'Want the final export tonight?',
          ),
        ]),
      ),
      ChatThread(
        id: 'design-sprint',
        name: 'Design Sprint',
        avatarLabel: 'DS',
        accentColor: AppPalette.purple,
        unreadCount: 8,
        isGroup: true,
        isPinned: true,
        typingPreview: 'Marco is typing…',
        groupDescription: 'Motion, visual QA, and rollout checkpoints.',
        participants: const [
          GroupParticipant(
            uid: 'me',
            name: 'You',
            avatarLabel: 'ME',
            accentColor: AppPalette.slate,
            isAdmin: true,
            isSelf: true,
          ),
          GroupParticipant(
            uid: 'priya',
            name: 'Priya',
            avatarLabel: 'PR',
            accentColor: AppPalette.purple,
          ),
          GroupParticipant(
            uid: 'marco',
            name: 'Marco',
            avatarLabel: 'MA',
            accentColor: AppPalette.sky,
          ),
        ],
        messages: List<ChatMessage>.unmodifiable([
          ChatMessage(
            id: 'design-1',
            senderName: 'Priya',
            sentAt: now.subtract(const Duration(hours: 4, minutes: 8)),
            isFromCurrentUser: false,
            text: 'Pinned the revised motion notes in Figma.',
          ),
          ChatMessage(
            id: 'design-2',
            senderName: 'Marco',
            sentAt: now.subtract(const Duration(hours: 2, minutes: 52)),
            isFromCurrentUser: false,
            text: 'Added the rollout checklist too.',
            attachments: List<ChatAttachment>.unmodifiable([
              const ChatAttachment(
                id: 'design-file-1',
                type: ChatAttachmentType.file,
                title: 'Sprint-Checkpoints.pdf',
                details: '482 KB • checklist and owners',
                tintColor: AppPalette.purple,
                aspectRatio: 1.28,
              ),
            ]),
          ),
          ChatMessage(
            id: 'design-3',
            senderName: 'You',
            sentAt: now.subtract(const Duration(hours: 1, minutes: 6)),
            isFromCurrentUser: true,
            text: 'Perfect. I will merge feedback after lunch.',
            deliveryState: MessageDeliveryState.delivered,
          ),
        ]),
      ),
      ChatThread(
        id: 'family',
        name: 'Family',
        avatarLabel: 'FA',
        accentColor: AppPalette.amber,
        unreadCount: 12,
        isGroup: true,
        isMuted: true,
        groupDescription: 'Family things, dinner plans, and photos.',
        participants: const [
          GroupParticipant(
            uid: 'me',
            name: 'You',
            avatarLabel: 'ME',
            accentColor: AppPalette.slate,
            isAdmin: true,
            isSelf: true,
          ),
          GroupParticipant(
            uid: 'mom',
            name: 'Mom',
            avatarLabel: 'MO',
            accentColor: AppPalette.rose,
            isAdmin: true,
          ),
          GroupParticipant(
            uid: 'dad',
            name: 'Dad',
            avatarLabel: 'DA',
            accentColor: AppPalette.amber,
          ),
        ],
        messages: List<ChatMessage>.unmodifiable([
          ChatMessage(
            id: 'family-1',
            senderName: 'Mom',
            sentAt: now.subtract(const Duration(days: 1, hours: 1)),
            isFromCurrentUser: false,
            text: 'Dinner at 8? I can bring dessert.',
          ),
          ChatMessage(
            id: 'family-2',
            senderName: 'You',
            sentAt: now.subtract(const Duration(days: 1, minutes: 42)),
            isFromCurrentUser: true,
            text: 'I will pick up fruit on the way.',
            deliveryState: MessageDeliveryState.read,
          ),
          ChatMessage(
            id: 'family-3',
            senderName: 'Dad',
            sentAt: now.subtract(const Duration(hours: 22)),
            isFromCurrentUser: false,
            attachments: List<ChatAttachment>.unmodifiable([
              const ChatAttachment(
                id: 'family-voice-1',
                type: ChatAttachmentType.voiceNote,
                title: 'Voice note',
                details: '0:24 dinner update',
                tintColor: AppPalette.amber,
                aspectRatio: 1.55,
              ),
            ]),
          ),
        ]),
      ),
      ChatThread(
        id: 'product-ops',
        name: 'Product Ops',
        avatarLabel: 'PO',
        accentColor: AppPalette.emerald,
        isGroup: true,
        isPinned: true,
        groupDescription: 'Launch coordination and rollout updates.',
        participants: const [
          GroupParticipant(
            uid: 'me',
            name: 'You',
            avatarLabel: 'ME',
            accentColor: AppPalette.slate,
            isAdmin: true,
            isSelf: true,
          ),
          GroupParticipant(
            uid: 'rina',
            name: 'Rina',
            avatarLabel: 'RI',
            accentColor: AppPalette.emerald,
          ),
        ],
        messages: List<ChatMessage>.unmodifiable([
          ChatMessage(
            id: 'ops-1',
            senderName: 'Rina',
            sentAt: now.subtract(const Duration(days: 1, hours: 4)),
            isFromCurrentUser: false,
            text: 'Here is the cut we discussed for the launch room.',
          ),
          ChatMessage(
            id: 'ops-2',
            senderName: 'Rina',
            sentAt:
                now.subtract(const Duration(days: 1, hours: 3, minutes: 20)),
            isFromCurrentUser: false,
            attachments: List<ChatAttachment>.unmodifiable([
              const ChatAttachment(
                id: 'ops-voice-1',
                type: ChatAttachmentType.voiceNote,
                title: 'Voice note',
                details: '0:37 rollout summary',
                tintColor: AppPalette.emerald,
                aspectRatio: 1.55,
              ),
            ]),
          ),
        ]),
      ),
      ChatThread(
        id: 'noah-kim',
        name: 'Noah Kim',
        avatarLabel: 'NK',
        accentColor: AppPalette.sky,
        hasStory: true,
        isArchived: true,
        messages: List<ChatMessage>.unmodifiable([
          ChatMessage(
            id: 'noah-1',
            senderName: 'Noah Kim',
            sentAt: now.subtract(const Duration(days: 2, hours: 2)),
            isFromCurrentUser: false,
            text: 'Shared a walkthrough clip from the latest build.',
            attachments: List<ChatAttachment>.unmodifiable([
              const ChatAttachment(
                id: 'noah-video-1',
                type: ChatAttachmentType.video,
                title: 'Simulator walkthrough',
                details: '0:18 screen recording',
                tintColor: AppPalette.sky,
                aspectRatio: 0.72,
              ),
            ]),
          ),
        ]),
      ),
      ...buildCommunityChatThreads(now),
    ]);
  }

  static List<ChatThread> buildCommunityChatThreads(DateTime now) {
    const me = GroupParticipant(
      uid: 'me',
      name: 'You',
      avatarLabel: 'ME',
      accentColor: AppPalette.slate,
      isAdmin: true,
      isSelf: true,
    );

    ChatThread communityThread({
      required String id,
      required String name,
      required String avatarLabel,
      required Color accentColor,
      required int unreadCount,
      required String previewText,
      required DateTime sentAt,
      required String senderName,
    }) {
      return ChatThread(
        id: id,
        name: name,
        avatarLabel: avatarLabel,
        accentColor: accentColor,
        isGroup: true,
        isCommunityGroup: true,
        unreadCount: unreadCount,
        participants: const [me],
        messages: List<ChatMessage>.unmodifiable([
          ChatMessage(
            id: '$id-preview',
            senderName: senderName,
            sentAt: sentAt,
            isFromCurrentUser: false,
            text: previewText,
          ),
        ]),
      );
    }

    return <ChatThread>[
      communityThread(
        id: 'studio-community-announcements',
        name: 'Announcements',
        avatarLabel: 'AN',
        accentColor: AppPalette.green,
        unreadCount: 2,
        previewText:
            'QA closes at 6 PM, release notes at 7 PM, and the announcement thread opens right after sign-off.',
        sentAt: now.subtract(const Duration(hours: 3, minutes: 15)),
        senderName: 'Studio admin',
      ),
      communityThread(
        id: 'studio-launch-room',
        name: 'Launch room',
        avatarLabel: 'LR',
        accentColor: AppPalette.green,
        unreadCount: 4,
        previewText: 'Release blockers, builds, and on-call coordination.',
        sentAt: now.subtract(const Duration(minutes: 48)),
        senderName: 'Marco',
      ),
      communityThread(
        id: 'studio-design-critique',
        name: 'Design critique',
        avatarLabel: 'DC',
        accentColor: AppPalette.green,
        unreadCount: 2,
        previewText: 'Motion tweaks, QA notes, and onboarding polish.',
        sentAt: now.subtract(const Duration(hours: 1, minutes: 20)),
        senderName: 'Ava',
      ),
      communityThread(
        id: 'studio-sprint-ops',
        name: 'Sprint ops',
        avatarLabel: 'SO',
        accentColor: AppPalette.green,
        unreadCount: 0,
        previewText: 'Planning, handoffs, and dependency tracking.',
        sentAt: now.subtract(const Duration(hours: 4)),
        senderName: 'Rina',
      ),
      communityThread(
        id: 'friends-trip-2026-announcements',
        name: 'Announcements',
        avatarLabel: 'AN',
        accentColor: AppPalette.amber,
        unreadCount: 1,
        previewText:
            'Terminal maps, baggage rules, and the airport meetup point are all in the announcement channel now.',
        sentAt: now.subtract(const Duration(days: 1, hours: 5)),
        senderName: 'Noah',
      ),
      communityThread(
        id: 'trip-flights',
        name: 'Flights',
        avatarLabel: 'FL',
        accentColor: AppPalette.amber,
        unreadCount: 1,
        previewText: 'Tickets, gate changes, and airport timing.',
        sentAt: now.subtract(const Duration(hours: 2, minutes: 10)),
        senderName: 'Noah',
      ),
      communityThread(
        id: 'trip-stay',
        name: 'Stay',
        avatarLabel: 'ST',
        accentColor: AppPalette.amber,
        unreadCount: 0,
        previewText: 'Check-in timing, room swaps, and local transport.',
        sentAt: now.subtract(const Duration(hours: 9)),
        senderName: 'Ken',
      ),
      communityThread(
        id: 'trip-budget',
        name: 'Budget',
        avatarLabel: 'BG',
        accentColor: AppPalette.amber,
        unreadCount: 1,
        previewText: 'Splitwise reminders and ticket reimbursement.',
        sentAt: now.subtract(const Duration(hours: 14)),
        senderName: 'Ava',
      ),
    ];
  }

  static const List<StatusStory> stories = [
    StatusStory(
      id: 'my-status',
      name: 'My Status',
      avatarLabel: 'JD',
      previewText: 'Tap to add a text, photo, or video update',
      timeLabel: 'Add now',
      accentColor: AppPalette.emerald,
      isMine: true,
      totalSegments: 0,
      seenSegments: 0,
    ),
    StatusStory(
      id: 'ava-story',
      name: 'Ava',
      avatarLabel: 'AP',
      previewText: 'Late-night launch coffee',
      timeLabel: '15m ago',
      accentColor: AppPalette.green,
      type: StatusStoryType.photo,
      totalSegments: 3,
      seenSegments: 1,
      segments: <StatusStorySegment>[
        StatusStorySegment(
          id: 'ava-story-0',
          type: StatusStoryType.photo,
          previewText: 'Shared a new photo update',
          localMediaPath: _demoStatusLaunchCafeAsset,
          overlayItems: <StatusMediaOverlayItem>[
            StatusMediaOverlayItem(
              id: 'ava-story-0-text',
              type: StatusMediaOverlayType.text,
              label: 'Late-night launch coffee',
              positionDx: 0.5,
              positionDy: 0.84,
              textStyle: _demoStoryTextStyle,
            ),
            StatusMediaOverlayItem(
              id: 'ava-story-0-emoji',
              type: StatusMediaOverlayType.emoji,
              label: '☕️',
              positionDx: 0.82,
              positionDy: 0.2,
              scale: 1.08,
            ),
          ],
        ),
        StatusStorySegment(
          id: 'ava-story-1',
          type: StatusStoryType.photo,
          previewText: 'Shared a new photo update',
          localMediaPath: _demoStatusSunsetCityAsset,
          overlayItems: <StatusMediaOverlayItem>[
            StatusMediaOverlayItem(
              id: 'ava-story-1-text',
              type: StatusMediaOverlayType.text,
              label: 'Built in one calm evening',
              positionDx: 0.5,
              positionDy: 0.84,
              textStyle: _demoStoryTextStyle,
            ),
          ],
        ),
        StatusStorySegment(
          id: 'ava-story-2',
          type: StatusStoryType.photo,
          previewText: 'Shared a new photo update',
          localMediaPath: _demoStatusLaunchCafeAsset,
          overlayItems: <StatusMediaOverlayItem>[
            StatusMediaOverlayItem(
              id: 'ava-story-2-text',
              type: StatusMediaOverlayType.text,
              label: 'Small team, big launch',
              positionDx: 0.5,
              positionDy: 0.84,
              textStyle: _demoStoryTextStyle,
            ),
          ],
        ),
      ],
    ),
    StatusStory(
      id: 'noah-story',
      name: 'Noah',
      avatarLabel: 'NK',
      previewText: 'Tokyo sunset timelapse',
      timeLabel: '41m ago',
      accentColor: AppPalette.sky,
      type: StatusStoryType.video,
      totalSegments: 4,
      seenSegments: 0,
      segments: <StatusStorySegment>[
        StatusStorySegment(
          id: 'noah-story-0',
          type: StatusStoryType.video,
          previewText: 'Shared a new video update',
          localMediaPath: _demoStatusCityWalkAsset,
          durationMillis: 7000,
          musicTrack: _demoCityPulseTrack,
          overlayItems: <StatusMediaOverlayItem>[
            StatusMediaOverlayItem(
              id: 'noah-story-0-music',
              type: StatusMediaOverlayType.music,
              label: 'City Pulse',
              subtitle: 'Whatswave House',
              positionDx: 0.22,
              positionDy: 0.16,
              accentColorValue: 0xFF25D366,
              secondaryColorValue: 0xFFD9FBE8,
              variantId: 'pulse',
            ),
            StatusMediaOverlayItem(
              id: 'noah-story-0-text',
              type: StatusMediaOverlayType.text,
              label: 'Tokyo sunset timelapse',
              positionDx: 0.5,
              positionDy: 0.84,
              textStyle: _demoStoryTextStyle,
            ),
          ],
        ),
        StatusStorySegment(
          id: 'noah-story-1',
          type: StatusStoryType.photo,
          previewText: 'Shared a new photo update',
          localMediaPath: _demoStatusSunsetCityAsset,
          overlayItems: <StatusMediaOverlayItem>[
            StatusMediaOverlayItem(
              id: 'noah-story-1-text',
              type: StatusMediaOverlayType.text,
              label: 'Blue hour over the city',
              positionDx: 0.5,
              positionDy: 0.84,
              textStyle: _demoStoryTextStyle,
            ),
          ],
        ),
        StatusStorySegment(
          id: 'noah-story-2',
          type: StatusStoryType.video,
          previewText: 'Shared a new video update',
          localMediaPath: _demoStatusCityWalkAsset,
          durationMillis: 7000,
          overlayItems: <StatusMediaOverlayItem>[
            StatusMediaOverlayItem(
              id: 'noah-story-2-text',
              type: StatusMediaOverlayType.text,
              label: 'Last train energy',
              positionDx: 0.5,
              positionDy: 0.84,
              textStyle: _demoStoryTextStyle,
            ),
          ],
        ),
        StatusStorySegment(
          id: 'noah-story-3',
          type: StatusStoryType.photo,
          previewText: 'Shared a new photo update',
          localMediaPath: _demoStatusSunsetCityAsset,
          overlayItems: <StatusMediaOverlayItem>[
            StatusMediaOverlayItem(
              id: 'noah-story-3-text',
              type: StatusMediaOverlayType.text,
              label: 'City lights all the way home',
              positionDx: 0.5,
              positionDy: 0.84,
              textStyle: _demoStoryTextStyle,
            ),
          ],
        ),
      ],
    ),
    StatusStory(
      id: 'priya-story',
      name: 'Priya',
      avatarLabel: 'PR',
      previewText: 'Sketchbook dump',
      timeLabel: '1h ago',
      accentColor: AppPalette.purple,
      type: StatusStoryType.photo,
      totalSegments: 2,
      seenSegments: 2,
      segments: <StatusStorySegment>[
        StatusStorySegment(
          id: 'priya-story-0',
          type: StatusStoryType.photo,
          previewText: 'Shared a new photo update',
          localMediaPath: _demoStatusSketchboardAsset,
          overlayItems: <StatusMediaOverlayItem>[
            StatusMediaOverlayItem(
              id: 'priya-story-0-text',
              type: StatusMediaOverlayType.text,
              label: 'Sketchbook dump',
              positionDx: 0.5,
              positionDy: 0.84,
              textStyle: _demoStoryTextStyle,
            ),
          ],
        ),
        StatusStorySegment(
          id: 'priya-story-1',
          type: StatusStoryType.photo,
          previewText: 'Shared a new photo update',
          localMediaPath: _demoStatusSketchboardAsset,
          overlayItems: <StatusMediaOverlayItem>[
            StatusMediaOverlayItem(
              id: 'priya-story-1-text',
              type: StatusMediaOverlayType.text,
              label: 'Sticker ideas for the weekend drop',
              positionDx: 0.5,
              positionDy: 0.84,
              textStyle: _demoStoryTextStyle,
            ),
          ],
        ),
      ],
    ),
  ];

  static StatusStory? storyById(String storyId) {
    for (final story in stories) {
      if (story.id == storyId) {
        return story.copyWith();
      }
    }
    return null;
  }

  static const List<ChannelPreview> channels = [
    ChannelPreview(
      id: 'design-signals',
      name: 'Design Signals',
      category: 'Productivity',
      followersLabel: '18.2K followers',
      description:
          'Short design patterns, mobile references, and weekly inspo drops.',
      avatarLabel: 'DS',
      accentColor: AppPalette.purple,
      isVerified: true,
    ),
    ChannelPreview(
      id: 'build-notes',
      name: 'Build Notes',
      category: 'Engineering',
      followersLabel: '7.4K followers',
      description:
          'Release notes, infra lessons, and fast architecture sketches.',
      avatarLabel: 'BN',
      accentColor: AppPalette.sky,
    ),
  ];

  static const List<CommunityPreview> communities = [
    CommunityPreview(
      title: 'Studio Community',
      summary:
          'Announcements, standups, design critiques, and launch room threads.',
      groupsLabel: '4 groups',
      avatarLabel: 'SC',
      accentColor: AppPalette.green,
      unreadCount: 9,
    ),
    CommunityPreview(
      title: 'Friends Trip 2026',
      summary: 'Flights, stay planning, budget chat, and memory sharing.',
      groupsLabel: '3 groups',
      avatarLabel: 'FT',
      accentColor: AppPalette.amber,
      unreadCount: 2,
    ),
  ];

  static List<CommunityHub> buildCommunities() {
    final now = DateTime.now();
    return <CommunityHub>[
      CommunityHub(
        id: 'studio-community',
        title: 'Studio Community',
        description:
            'Announcements, launch rooms, critiques, and cross-functional coordination in one place.',
        avatarLabel: 'SC',
        accentColor: AppPalette.green,
        memberCount: 48,
        unreadCount: 9,
        announcementThreadId: 'studio-community-announcements',
        announcement: CommunityAnnouncement(
          headline: 'Launch checklist locked for tonight',
          body:
              'QA closes at 6 PM, release notes at 7 PM, and the announcement thread opens right after sign-off.',
          publishedAt: now.subtract(const Duration(hours: 3, minutes: 15)),
        ),
        groups: <CommunityGroupPreview>[
          CommunityGroupPreview(
            id: 'studio-launch-room',
            name: 'Launch room',
            summary: 'Release blockers, builds, and on-call coordination.',
            memberCount: 18,
            unreadCount: 4,
            lastActivityAt: now.subtract(const Duration(minutes: 48)),
            threadId: 'studio-launch-room',
          ),
          CommunityGroupPreview(
            id: 'studio-design-critique',
            name: 'Design critique',
            summary: 'Motion tweaks, QA notes, and onboarding polish.',
            memberCount: 11,
            unreadCount: 2,
            lastActivityAt: now.subtract(const Duration(hours: 1, minutes: 20)),
            threadId: 'studio-design-critique',
          ),
          CommunityGroupPreview(
            id: 'studio-sprint-ops',
            name: 'Sprint ops',
            summary: 'Planning, handoffs, and dependency tracking.',
            memberCount: 24,
            unreadCount: 0,
            lastActivityAt: now.subtract(const Duration(hours: 4)),
            threadId: 'studio-sprint-ops',
          ),
        ],
      ),
      CommunityHub(
        id: 'friends-trip-2026',
        title: 'Friends Trip 2026',
        description:
            'Trip planning, flights, stay details, and shared memories for the whole crew.',
        avatarLabel: 'FT',
        accentColor: AppPalette.amber,
        memberCount: 11,
        unreadCount: 2,
        announcementThreadId: 'friends-trip-2026-announcements',
        announcement: CommunityAnnouncement(
          headline: 'Flight reminders are pinned',
          body:
              'Terminal maps, baggage rules, and the airport meetup point are all in the announcement channel now.',
          publishedAt: now.subtract(const Duration(days: 1, hours: 5)),
        ),
        groups: <CommunityGroupPreview>[
          CommunityGroupPreview(
            id: 'trip-flights',
            name: 'Flights',
            summary: 'Tickets, gate changes, and airport timing.',
            memberCount: 11,
            unreadCount: 1,
            lastActivityAt: now.subtract(const Duration(hours: 2, minutes: 10)),
            threadId: 'trip-flights',
          ),
          CommunityGroupPreview(
            id: 'trip-stay',
            name: 'Stay',
            summary: 'Check-in timing, room swaps, and local transport.',
            memberCount: 8,
            unreadCount: 0,
            lastActivityAt: now.subtract(const Duration(hours: 9)),
            threadId: 'trip-stay',
          ),
          CommunityGroupPreview(
            id: 'trip-budget',
            name: 'Budget',
            summary: 'Splitwise reminders and ticket reimbursement.',
            memberCount: 6,
            unreadCount: 1,
            lastActivityAt: now.subtract(const Duration(hours: 14)),
            threadId: 'trip-budget',
          ),
        ],
      ),
    ];
  }

  static CommunityHub buildDraftCommunity({
    required String id,
    required String title,
    required String description,
  }) {
    final now = DateTime.now();
    return CommunityHub(
      id: id,
      title: title,
      description: description,
      avatarLabel: title
          .trim()
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .take(2)
          .map((part) => part[0].toUpperCase())
          .join(),
      accentColor: AppPalette.emerald,
      memberCount: 1,
      unreadCount: 0,
      announcement: CommunityAnnouncement(
        headline: 'Welcome to $title',
        body:
            'Admins can post updates here. Members can read announcements but not reply.',
        publishedAt: now,
      ),
      groups: <CommunityGroupPreview>[
        CommunityGroupPreview(
          id: '$id-general',
          name: 'General',
          summary: 'Shared updates and the first coordination thread.',
          memberCount: 1,
          unreadCount: 0,
          lastActivityAt: now,
        ),
      ],
    );
  }

  static List<CommunityContact> buildCommunityContacts() {
    return const <CommunityContact>[
      CommunityContact(
        id: 'ava-patel',
        name: 'Ava Patel',
        phoneNumber: '+81 90 3000 1122',
        avatarLabel: 'AP',
        accentColor: AppPalette.green,
        about: 'Shipping launch polish and keeping reviews calm.',
        username: 'ava.patel',
        matchedUid: 'uid-ava-patel',
        memberCommunityIds: <String>['studio-community'],
      ),
      CommunityContact(
        id: 'noah-kim',
        name: 'Noah Kim',
        phoneNumber: '+81 90 3000 2233',
        avatarLabel: 'NK',
        accentColor: AppPalette.sky,
        about: 'Travel boards, photos, and last-mile planning.',
        username: 'noah.kim',
        matchedUid: 'uid-noah-kim',
        memberCommunityIds: <String>['friends-trip-2026'],
      ),
      CommunityContact(
        id: 'priya-rai',
        name: 'Priya Rai',
        phoneNumber: '+81 90 3000 3344',
        avatarLabel: 'PR',
        accentColor: AppPalette.purple,
        about: 'Ready to join new groups and keep things organized.',
        username: 'priya.rai',
        matchedUid: 'uid-priya-rai',
      ),
      CommunityContact(
        id: 'marco-silva',
        name: 'Marco Silva',
        phoneNumber: '+81 90 3000 4455',
        avatarLabel: 'MS',
        accentColor: AppPalette.amber,
        about: 'Typing dots, release reviews, and steady launch help.',
        username: 'marco.silva',
        matchedUid: 'uid-marco-silva',
        memberCommunityIds: <String>['studio-community'],
      ),
      CommunityContact(
        id: 'emi-tanaka',
        name: 'Emi Tanaka',
        phoneNumber: '+81 90 3000 5566',
        avatarLabel: 'ET',
        accentColor: AppPalette.emerald,
        about: 'Not on WhatsWave yet.',
        isOnWhatsWave: false,
      ),
      CommunityContact(
        id: 'ken-watanabe',
        name: 'Ken Watanabe',
        phoneNumber: '+81 90 3000 6677',
        avatarLabel: 'KW',
        accentColor: AppPalette.sky,
        about: 'Invite link was already shared from a prior test.',
        isOnWhatsWave: false,
        appInviteSent: true,
      ),
    ];
  }

  static List<CallContact> buildCallFavorites() {
    return const <CallContact>[
      CallContact(
        id: 'ava-patel',
        name: 'Ava Patel',
        avatarLabel: 'AP',
        accentColor: AppPalette.green,
      ),
      CallContact(
        id: 'noah-kim',
        name: 'Noah Kim',
        avatarLabel: 'NK',
        accentColor: AppPalette.sky,
      ),
      CallContact(
        id: 'priya-rai',
        name: 'Priya Rai',
        avatarLabel: 'PR',
        accentColor: AppPalette.purple,
      ),
      CallContact(
        id: 'marco-silva',
        name: 'Marco Silva',
        avatarLabel: 'MA',
        accentColor: AppPalette.amber,
      ),
    ];
  }

  static List<CallHistoryEntry> buildCallHistory() {
    final now = DateTime.now();
    return <CallHistoryEntry>[
      CallHistoryEntry(
        id: 'call-ava-video-completed',
        contactId: 'ava-patel',
        name: 'Ava Patel',
        avatarLabel: 'AP',
        accentColor: AppPalette.green,
        startedAt: now.subtract(const Duration(hours: 2, minutes: 18)),
        type: CallType.video,
        direction: CallDirection.outgoing,
        status: CallHistoryStatus.completed,
        durationSeconds: 14 * 60 + 32,
      ),
      CallHistoryEntry(
        id: 'call-noah-audio-missed',
        contactId: 'noah-kim',
        name: 'Noah Kim',
        avatarLabel: 'NK',
        accentColor: AppPalette.sky,
        startedAt: now.subtract(const Duration(days: 1, hours: 4)),
        type: CallType.audio,
        direction: CallDirection.incoming,
        status: CallHistoryStatus.missed,
      ),
      CallHistoryEntry(
        id: 'call-design-sprint-video',
        contactId: 'design-sprint',
        name: 'Design Sprint',
        avatarLabel: 'DS',
        accentColor: AppPalette.purple,
        startedAt: now.subtract(const Duration(days: 3, hours: 6)),
        type: CallType.video,
        direction: CallDirection.outgoing,
        status: CallHistoryStatus.completed,
        durationSeconds: 26 * 60 + 5,
        isGroup: true,
        participants: const [
          GroupParticipant(
            uid: 'me',
            name: 'You',
            avatarLabel: 'ME',
            accentColor: AppPalette.slate,
            isSelf: true,
          ),
          GroupParticipant(
            uid: 'priya',
            name: 'Priya',
            avatarLabel: 'PR',
            accentColor: AppPalette.purple,
          ),
          GroupParticipant(
            uid: 'marco',
            name: 'Marco',
            avatarLabel: 'MA',
            accentColor: AppPalette.sky,
          ),
        ],
      ),
      CallHistoryEntry(
        id: 'call-priya-audio-canceled',
        contactId: 'priya-rai',
        name: 'Priya Rai',
        avatarLabel: 'PR',
        accentColor: AppPalette.purple,
        startedAt: now.subtract(const Duration(days: 5, hours: 1)),
        type: CallType.audio,
        direction: CallDirection.outgoing,
        status: CallHistoryStatus.canceled,
      ),
    ];
  }
}
