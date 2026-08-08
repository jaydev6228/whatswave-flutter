import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/core/permissions/device_location_service.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/chat_repository.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';
import 'package:whatswave/features/chats/domain/chat_message.dart';
import 'package:whatswave/features/chats/domain/chat_thread.dart';
import 'package:whatswave/features/chats/presentation/chats_screen.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_ring_avatar.dart';

import '../../../support/device_matrix.dart';
import '../../../support/fake_image_picker_platform.dart';

void main() {
  setUp(() {
    ImagePickerPlatform.instance = FakeImagePickerPlatform();
  });

  for (final device in compactDeviceMatrix) {
    testWidgets(
      'filters, archives, and restores chats on ${device.name}',
      (tester) async {
        final controller = ChatsController(
          repository: FakeChatRepository(latency: Duration.zero),
        );

        await _pumpChatsScreen(
          tester,
          device: device,
          controller: controller,
        );

        await tester.enterText(
          find.byKey(const Key('chat_search_field')),
          'Ava',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -240),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Ava Patel'), findsOneWidget);
        expect(find.text('Design Sprint'), findsNothing);

        await tester.drag(
          find.byKey(const Key('chat_tile_ava-patel')),
          const Offset(-420, 0),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.text('Ava Patel'), findsNothing);

        await tester.tap(find.byKey(const Key('chat_archived_row')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('archived_chats_screen')), findsOneWidget);

        expect(find.text('Ava Patel'), findsOneWidget);

        await tester.drag(
          find.byKey(const Key('chat_tile_ava-patel')),
          const Offset(420, 0),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.text('Ava Patel'), findsOneWidget);
        expect(find.text('Chats'), findsOneWidget);
      },
    );
  }

  testWidgets('opens a conversation, previews media, and sends new content',
      (tester) async {
    const composerFieldKey = Key('conversation_composer_field');
    const sendButtonKey = Key('conversation_send_button');
    const messageListKey = Key('conversation_message_list');
    const lastSentMessageKey =
        ValueKey<String>('conversation_message_ava-patel-message-12');
    const longMessage =
        'Handoff is almost ready.\nI kept the hero motion, tightened the spacing, and left notes for QA.\nPlease review the final build tonight.';

    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(
          latency: const Duration(milliseconds: 120),
        ),
        permissionService: MemoryAppPermissionService(),
        locationService: const _FakeDeviceLocationService(
          fix: DeviceLocationFix(latitude: 35.6595, longitude: 139.7005),
        ),
      ),
    );

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    expect(find.text('Secure chat preview'), findsOneWidget);
    expect(find.byKey(composerFieldKey), findsOneWidget);
    expect(
      find.byKey(const Key('conversation_attachment_menu_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('attachment_preview_ava-photo-1')));
    await tester.pumpAndSettle();

    expect(find.text('Onboarding board'), findsWidgets);
    expect(
      find.byKey(const Key('attachment_viewer_close_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('attachment_viewer_close_button')));
    await tester.pumpAndSettle();

    for (var index = 0; index < 12; index++) {
      await tester.enterText(
        find.byKey(composerFieldKey),
        'Scroll seed $index',
      );
      await tester.pump();
      await tester.tap(find.byKey(sendButtonKey));
      await tester.pumpAndSettle();
    }

    final messageListController =
        tester.widget<ListView>(find.byKey(messageListKey)).controller!;
    final messageListPadding = tester
        .widget<ListView>(find.byKey(messageListKey))
        .padding! as EdgeInsets;
    expect(messageListPadding.bottom, 12);
    messageListController.jumpTo(140);
    await tester.pumpAndSettle();

    final offsetBeforeFinalSend = messageListController.offset;
    expect(
      offsetBeforeFinalSend,
      lessThan(messageListController.position.maxScrollExtent),
    );

    await tester.enterText(
      find.byKey(composerFieldKey),
      longMessage,
    );
    await tester.pump();
    await tester.tap(find.byKey(sendButtonKey));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byKey(composerFieldKey)).controller!.text,
      isEmpty,
    );
    // The composer must stay editable/focused through a send -- flipping it
    // readOnly mid-send would dismiss the keyboard and re-present it once
    // the send resolves, a jarring flicker on a real (non-zero-latency)
    // send.
    expect(
      tester.widget<TextField>(find.byKey(composerFieldKey)).readOnly,
      isFalse,
    );
    await tester.pumpAndSettle();

    expect(find.text(longMessage), findsOneWidget);
    expect(
      messageListController.offset,
      closeTo(messageListController.position.maxScrollExtent, 0.1),
    );
    expect(messageListController.offset, greaterThan(offsetBeforeFinalSend));
    final latestMessageBottom =
        tester.getBottomLeft(find.byKey(lastSentMessageKey)).dy;
    final messageListBottom =
        tester.getBottomLeft(find.byKey(messageListKey)).dy;
    expect(messageListBottom - latestMessageBottom, closeTo(12, 2));

    await tester.tap(
      find.byKey(const Key('conversation_attachment_menu_button')),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('conversation_attachment_sheet')), findsOneWidget);
    expect(
      find.byKey(const Key('conversation_location_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('conversation_photo_button')));
    await tester.pumpAndSettle();

    // The picked photo has no real file on disk in this test environment,
    // so the bubble falls back to its placeholder swatch+icon rather than
    // a title/subtitle row (photo bubbles no longer show text at all).
    expect(find.byIcon(Icons.photo_outlined), findsWidgets);

    await tester.tap(
      find.byKey(const Key('conversation_attachment_menu_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation_location_button')));
    await tester.pumpAndSettle();

    expect(find.text('Current location'), findsOneWidget);
    expect(find.text('Tap to open in Maps'), findsOneWidget);
  });

  testWidgets('keeps the attachment sheet overflow-free on compact phones',
      (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneSeProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('chat_search_field')),
      'Ava',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('conversation_attachment_menu_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('conversation_attachment_sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('conversation_voice_button')), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason:
          'The compact attachment sheet should not overflow on iPhone SE class devices.',
    );
  });

  testWidgets('shows animated typing dots after the typist name',
      (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneSeProfile,
      animateTypingIndicators: true,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    expect(find.byKey(const Key('chat_typing_indicator_design-sprint')),
        findsOneWidget);
    expect(find.byKey(const Key('chat_typing_name_design-sprint')),
        findsOneWidget);
    expect(find.text('Marco is typing…'), findsNothing);

    final dotFinder = find.byKey(const Key('chat_typing_dot_design-sprint_0'));
    final opacityBefore = tester.widget<Opacity>(dotFinder).opacity;

    await tester.pump(const Duration(milliseconds: 250));

    final opacityAfter = tester.widget<Opacity>(dotFinder).opacity;
    expect((opacityAfter - opacityBefore).abs(), greaterThan(0.05));
  });

  testWidgets('archive swipe affordance stays readable on compact phones',
      (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneSeProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('chat_tile_ava-patel')),
      const Offset(-110, 0),
    );
    await tester.pump();

    expect(find.text('Archive'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'Swipe archive affordance should stay readable without overflow.',
    );
  });

  testWidgets(
      'tapping a chat profile story ring opens the story viewer and keeps progress in sync',
      (tester) async {
    final avatarFinder =
        find.byKey(const ValueKey<String>('chat_story_avatar_ava-patel'));

    final updatesController = UpdatesController(
      repository: FakeUpdatesRepository(latency: Duration.zero),
    );

    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
      updatesController: updatesController,
    );

    expect(
      updatesController
          .storyForParticipant(
            avatarLabel: 'AP',
            name: 'Ava Patel',
          )
          ?.seenSegments,
      1,
    );

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(avatarFinder);
    await tester.pump();
    await tester.tap(avatarFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('updates_story_viewer')), findsOneWidget);
    expect(
      updatesController
          .storyForParticipant(
            avatarLabel: 'AP',
            name: 'Ava Patel',
          )
          ?.seenSegments,
      2,
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(
      updatesController
          .storyForParticipant(
            avatarLabel: 'AP',
            name: 'Ava Patel',
          )
          ?.seenSegments,
      2,
    );
    expect(
      updatesController.recentStories.any((story) => story.id == 'ava-story'),
      isTrue,
    );

    final ring = tester.widget<StatusRingAvatar>(
      find.byKey(const ValueKey<String>('chat_story_ring_ava-patel')),
    );
    expect(ring.totalSegments, 3);
    expect(ring.seenSegments, 2);
  });

  testWidgets(
      'keeps chat header actions compact so preview stays visually close',
      (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneSeProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const Key('chat_tile_ava-patel'));
    final titleFinder = find.byKey(const Key('chat_title_ava-patel'));
    final previewFinder = find.byKey(const Key('chat_preview_ava-patel'));
    final tileSize = tester.getSize(tileFinder);
    final titleBottom = tester.getBottomLeft(titleFinder).dy;
    final previewTop = tester.getTopLeft(previewFinder).dy;

    expect(tileSize.height, lessThanOrEqualTo(84));
    expect(previewTop - titleBottom, lessThan(8));
  });

  testWidgets('keeps short conversations naturally top aligned',
      (tester) async {
    final topAlignedThread = ChatThread(
      id: 'top-thread',
      name: 'Top Thread',
      avatarLabel: 'TT',
      accentColor: Colors.green,
      messages: [
        ChatMessage(
          id: 'top-thread-message-1',
          senderName: 'Taylor',
          sentAt: DateTime(2026, 6, 2, 9),
          isFromCurrentUser: false,
          text: 'Morning! Want to review the build after standup?',
        ),
        ChatMessage(
          id: 'top-thread-message-2',
          senderName: 'You',
          sentAt: DateTime(2026, 6, 2, 9, 2),
          isFromCurrentUser: true,
          text: 'Yes, let us do it.',
        ),
      ],
    );

    await _pumpChatsScreen(
      tester,
      device: iphoneSeProfile,
      controller: ChatsController(
        repository: FakeChatRepository(
          initialThreads: [topAlignedThread],
          latency: Duration.zero,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_top-thread')));
    await tester.pumpAndSettle();

    final messageListFinder =
        find.byKey(const Key('conversation_message_list'));
    final messageListController =
        tester.widget<ListView>(messageListFinder).controller!;
    final firstMessageFinder = find.byKey(
      const ValueKey<String>('conversation_message_top-thread-message-1'),
    );
    final lastMessageFinder = find.byKey(
      const ValueKey<String>('conversation_message_top-thread-message-2'),
    );
    final messageListTop = tester.getTopLeft(messageListFinder).dy;
    final firstMessageTop = tester.getTopLeft(firstMessageFinder).dy;
    final messageListBottom = tester.getBottomLeft(messageListFinder).dy;
    final lastMessageBottom = tester.getBottomLeft(lastMessageFinder).dy;

    expect(messageListController.position.maxScrollExtent, 0);
    expect(firstMessageTop - messageListTop, lessThan(96));
    expect(messageListBottom - lastMessageBottom, greaterThan(120));
  });

  testWidgets(
      'shows a failed outgoing message state and retries it successfully',
      (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: _FlakySendChatRepository(),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('chat_search_field')),
      'Ava',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('conversation_composer_field')),
      'Please retry this send.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation_send_button')));
    await tester.pumpAndSettle();

    expect(find.text('Please retry this send.'), findsOneWidget);
    expect(find.text('Message service offline'), findsOneWidget);
    expect(find.text('Not sent'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Please retry this send.'), findsOneWidget);
    expect(find.text('Message service offline'), findsNothing);
    expect(find.text('Not sent'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('dismisses the search focus when the chat list is dragged',
      (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneSeProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_search_field')));
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chat_search_field')))
          .focusNode!
          .hasFocus,
      isTrue,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chat_search_field')))
          .focusNode!
          .hasFocus,
      isFalse,
    );
  });

  testWidgets(
      'keeps the chat list scroll position after returning from a thread',
      (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await tester.pumpAndSettle();

    final listPositionBeforeOpen = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    final familyTileTopBeforeOpen =
        tester.getTopLeft(find.byKey(const Key('chat_tile_family'))).dy;

    expect(find.byKey(const Key('chat_tile_family')), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat_tile_family')));
    await tester.pumpAndSettle();

    expect(find.text('Family'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    final listPositionAfterBack = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    final familyTileTopAfterBack =
        tester.getTopLeft(find.byKey(const Key('chat_tile_family'))).dy;

    expect(find.byKey(const Key('chat_tile_family')), findsOneWidget);
    expect(listPositionAfterBack, closeTo(listPositionBeforeOpen, 40));
    expect(
      familyTileTopAfterBack,
      closeTo(familyTileTopBeforeOpen, 40),
    );
  });

  testWidgets('shows an inline error when the chat repository fails to load',
      (tester) async {
    await _pumpChatsScreen(
      tester,
      device: androidMediumProfile,
      controller: ChatsController(repository: _FailingChatRepository()),
    );

    expect(find.text('Repository offline'), findsOneWidget);
    expect(find.byKey(const Key('chat_search_field')), findsOneWidget);
  });
}

Future<void> _pumpChatsScreen(
  WidgetTester tester, {
  required TestDeviceProfile device,
  required ChatsController controller,
  UpdatesController? updatesController,
  bool animateTypingIndicators = false,
}) async {
  await tester.binding.setSurfaceSize(device.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final resolvedUpdatesController = updatesController ??
      UpdatesController(
        repository: FakeUpdatesRepository(latency: Duration.zero),
      );

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: Scaffold(
        body: ChatsScreen(
          callsController: CallsController(
            repository: FakeCallsRepository(latency: Duration.zero),
          ),
          communitiesController: CommunitiesController(
            repository: FakeCommunitiesRepository(latency: Duration.zero),
          ),
          controller: controller,
          updatesController: resolvedUpdatesController,
          animateTypingIndicators: animateTypingIndicators,
        ),
      ),
    ),
  );
  if (animateTypingIndicators) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  } else {
    await tester.pumpAndSettle();
  }

  expect(
    tester.takeException(),
    isNull,
    reason:
        '${device.name} should render the chats flow without framework exceptions.',
  );
}

class _FailingChatRepository implements ChatRepository {
  @override
  Future<List<Never>> fetchThreads() {
    throw const ChatRepositoryException('Repository offline');
  }

  @override
  Stream<List<ChatThread>>? watchThreads() => null;

  @override
  Future<List<Never>> deleteThread(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<ChatThread> startThread({
    required String participantUid,
    required String participantName,
    required String avatarLabel,
    required Color accentColor,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> markThreadRead(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> sendTextMessage({
    required String threadId,
    required String text,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> setThreadArchived({
    required String threadId,
    required bool isArchived,
  }) {
    throw UnimplementedError();
  }
}

class _FlakySendChatRepository implements ChatRepository {
  _FlakySendChatRepository()
      : _delegate = FakeChatRepository(latency: Duration.zero);

  final FakeChatRepository _delegate;
  bool _shouldFailNextTextSend = true;

  @override
  Future<List<ChatThread>> fetchThreads() => _delegate.fetchThreads();

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
  Future<List<ChatThread>> markThreadRead(String threadId) =>
      _delegate.markThreadRead(threadId);

  @override
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
  }) =>
      _delegate.createGroup(name: name, memberUids: memberUids);

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
  }) =>
      _delegate.sendAttachmentMessage(
        threadId: threadId,
        attachments: attachments,
        caption: caption,
      );

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
  }) {
    if (_shouldFailNextTextSend) {
      _shouldFailNextTextSend = false;
      throw const ChatRepositoryException('Message service offline');
    }
    return _delegate.sendTextMessage(
      threadId: threadId,
      text: text,
    );
  }

  @override
  Future<List<ChatThread>> setThreadArchived({
    required String threadId,
    required bool isArchived,
  }) =>
      _delegate.setThreadArchived(
        threadId: threadId,
        isArchived: isArchived,
      );
}

class _FakeDeviceLocationService implements DeviceLocationService {
  const _FakeDeviceLocationService({required this.fix});

  final DeviceLocationFix fix;

  @override
  Future<DeviceLocationFix> getCurrentLocation() async => fix;
}
