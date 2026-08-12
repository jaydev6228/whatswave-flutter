import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/core/permissions/device_location_service.dart';
import 'package:whatswave/features/auth/application/auth_controller.dart';
import 'package:whatswave/features/auth/data/fake_auth_repository.dart';
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
import 'package:whatswave/features/chats/domain/message_reply_preview.dart';
import 'package:whatswave/features/chats/domain/story_reply_context.dart';
import 'package:whatswave/core/media/avatar_photo_picker.dart';
import 'package:whatswave/features/chats/presentation/chats_screen.dart';
import 'package:whatswave/features/chats/presentation/widgets/lazy_heavy_attachment.dart';
import 'package:whatswave/features/chats/presentation/widgets/location_map_preview.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_ring_avatar.dart';

import '../../../support/device_matrix.dart';
import '../../../support/fake_image_picker_platform.dart';

void main() {
  setUp(() {
    ImagePickerPlatform.instance = FakeImagePickerPlatform();
    avatarCropOverride = (_, source) async => source;
    // The full-screen emoji picker (EmojiReactionPickerScreen) persists
    // recent emoji via shared_preferences -- without mock initial values,
    // that read throws in the test environment and the picker never leaves
    // its loading state.
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // TestWidgetsFlutterBinding doesn't answer the clipboard platform
    // channel by default -- without a handler, Clipboard.setData/getData
    // (used by the message long-press menu's Copy action) hang forever
    // waiting for a response nothing ever sends.
    String? clipboardText;
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return <String, Object?>{'text': clipboardText};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    avatarCropOverride = null;
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

    expect(find.text(longMessage), findsOneWidget);

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
    expect(messageListController.offset, closeTo(0, 0.1));
    expect(messageListController.offset, lessThan(offsetBeforeFinalSend));
    final latestMessageBubble = find.ancestor(
      of: find.textContaining('Please review the final build tonight'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value
                .startsWith('conversation_message_') &&
            (widget.key! as ValueKey<String>).value !=
                'conversation_message_list',
      ),
    );
    expect(latestMessageBubble, findsOneWidget);
    final latestMessageBottom =
        tester.getBottomLeft(latestMessageBubble).dy;
    final messageListBottom =
        tester.getBottomLeft(find.byKey(messageListKey)).dy;
    expect(messageListBottom - latestMessageBottom, closeTo(24, 4));

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

    // Picking a photo opens the WhatsApp-style review screen instead of
    // sending immediately -- confirm from there.
    expect(
      find.byKey(const Key('media_send_preview_screen')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('media_send_preview_send_button')));
    await tester.pumpAndSettle();

    // The picked photo has no real file on disk in this test environment,
    // so the bubble falls back to its placeholder swatch+icon rather than
    // a title/subtitle row (photo bubbles no longer show text at all).
    expect(find.byIcon(Icons.photo_outlined), findsWidgets);

    await tester.tap(
      find.byKey(const Key('conversation_attachment_menu_button')),
    );
    await tester.pumpAndSettle();
    await _openLocationSendPreview(tester);
    await _confirmLocationSendFromPreview(tester);

    // The location bubble renders a lazy map snippet (placeholder or real map).
    expect(find.byType(LazyLocationMapSnippet), findsOneWidget);
  });

  testWidgets(
    'typing in the composer stays when opening the location picker',
    (tester) async {
      const composerFieldKey = Key('conversation_composer_field');
      const draftText = 'bug test for media';

      await _pumpChatsScreen(
        tester,
        device: iphoneProProfile,
        controller: ChatsController(
          repository: FakeChatRepository(latency: Duration.zero),
          permissionService: MemoryAppPermissionService(),
          locationService: const _FakeDeviceLocationService(
            fix: DeviceLocationFix(latitude: 37.7879, longitude: -122.4075),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(composerFieldKey), draftText);
      await tester.pump();

      await tester.tap(
        find.byKey(const Key('conversation_attachment_menu_button')),
      );
      await tester.pumpAndSettle();
      await _openLocationSendPreview(tester);

      expect(
        find.byKey(const Key('location_send_preview_screen')),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byKey(composerFieldKey)).controller!.text,
        draftText,
      );

      await tester.tap(find.byKey(const Key('location_send_preview_close_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.widget<TextField>(find.byKey(composerFieldKey)).controller!.text,
        draftText,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('conversation_message_list')),
          matching: find.text(draftText),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'rapid duplicate-text sends after location never shrink visible history',
    (tester) async {
      const composerFieldKey = Key('conversation_composer_field');
      const sendButtonKey = Key('conversation_send_button');
      const duplicateText = 'Sdfsd';

      await _pumpChatsScreen(
        tester,
        device: iphoneProProfile,
        controller: ChatsController(
          repository: FakeChatRepository(latency: Duration.zero),
          permissionService: MemoryAppPermissionService(),
          locationService: const _FakeDeviceLocationService(
            fix: DeviceLocationFix(latitude: 37.7879, longitude: -122.4075),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('chat_tile_design-sprint')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('conversation_attachment_menu_button')),
      );
      await tester.pumpAndSettle();
      await _openLocationSendPreview(tester);
      await _confirmLocationSendFromPreview(tester);

      var peakCount = _groupChatVisibleMessageCount(tester);

      for (var index = 0; index < 7; index++) {
        await tester.enterText(find.byKey(composerFieldKey), duplicateText);
        await tester.pump();
        await tester.tap(find.byKey(sendButtonKey));
        await tester.pump();

        final midFlightCount = _groupChatVisibleMessageCount(tester);
        expect(
          midFlightCount,
          greaterThanOrEqualTo(peakCount),
          reason: 'Message count shrank mid-send on iteration $index',
        );

        await tester.pumpAndSettle();
        final settledCount = _groupChatVisibleMessageCount(tester);
        expect(settledCount, greaterThan(peakCount));
        peakCount = settledCount;
      }

      expect(find.text(duplicateText), findsNWidgets(7));
    },
  );

  testWidgets('long-pressing a bubble reacts, and reacting again removes it',
      (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    await tester.longPress(find.text(
      'The onboarding shots look good. The motion pacing feels much cleaner.',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reaction_option_❤️')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reaction_option_❤️')));
    await tester.pumpAndSettle();

    expect(find.text('❤️'), findsOneWidget);

    await tester.longPress(find.text(
      'The onboarding shots look good. The motion pacing feels much cleaner.',
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reaction_option_❤️')));
    await tester.pumpAndSettle();

    expect(find.text('❤️'), findsNothing);
  });

  testWidgets('message long-press menu: copy puts the text on the clipboard',
      (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    const messageText =
        'The onboarding shots look good. The motion pacing feels much cleaner.';
    await tester.longPress(find.text(messageText));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('message_action_copy')), findsOneWidget);
    await tester.tap(find.byKey(const Key('message_action_copy')));
    await tester.pumpAndSettle();

    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboardData?.text, messageText);
  });

  testWidgets(
      'message long-press menu: replying shows a quote card that jumps '
      'back to the original message', (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    const originalText =
        'The onboarding shots look good. The motion pacing feels much cleaner.';
    await tester.longPress(find.text(originalText));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('message_action_reply')), findsOneWidget);
    await tester.tap(find.byKey(const Key('message_action_reply')));
    await tester.pumpAndSettle();

    // "Ava Patel" also appears in the app bar title, and the original
    // text is still visible in its own message bubble too -- both checks
    // just confirm a second occurrence exists (the reply bar itself)
    // rather than scoping into the bar's own subtree.
    expect(find.text('Ava Patel'), findsNWidgets(2));
    expect(find.text(originalText), findsNWidgets(2));

    await tester.enterText(
      find.byKey(const Key('conversation_composer_field')),
      'Sure thing!',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation_send_button')));
    await tester.pumpAndSettle();

    expect(find.text('Sure thing!'), findsOneWidget);
    // The reply bar clears itself after sending.
    expect(
      find.byKey(const Key('conversation_cancel_reply_button')),
      findsNothing,
    );
    expect(find.byKey(const Key('reply_preview_quote_card')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reply_preview_quote_card')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Jumping back to the original message can scroll the new reply's own
    // bubble (and its quote card, also showing this text) out of the
    // ListView's lazily-built viewport -- at least the original bubble
    // itself must still be visible after the jump.
    expect(find.text(originalText), findsWidgets);
  });

  testWidgets(
      'message long-press menu: multi-select bulk-stars then bulk-deletes '
      'messages', (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_design-sprint')));
    await tester.pumpAndSettle();

    const priyaText = 'Pinned the revised motion notes in Figma.';
    const marcoText = 'Added the rollout checklist too.';

    await tester.longPress(find.text(priyaText));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message_action_select')));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.text(marcoText));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('conversation_selection_star_button')),
    );
    await tester.pumpAndSettle();

    // Bulk actions exit selection mode on completion -- back to the
    // normal header confirms it cleared.
    expect(find.text('Design Sprint'), findsOneWidget);
    expect(find.text('2 selected'), findsNothing);

    await tester.longPress(find.text(priyaText));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message_action_select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(marcoText));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('conversation_selection_delete_button')),
    );
    await tester.pumpAndSettle();

    // Neither message was sent by the current user, so only "Delete for
    // me" is offered.
    expect(
      find.byKey(const Key('confirm_bulk_delete_everyone_button')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('confirm_bulk_delete_me_button')));
    await tester.pumpAndSettle();

    expect(find.text(priyaText), findsNothing);
    expect(find.text(marcoText), findsNothing);
    expect(find.text('Design Sprint'), findsOneWidget);
  });

  testWidgets(
      'message long-press menu: delete for me removes it from this view '
      'only', (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    const messageText = 'Want the final export tonight?';
    await tester.longPress(find.text(messageText));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('message_action_deleteForMe')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm_delete_message_me_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text(messageText), findsNothing);
  });

  testWidgets(
      'message long-press menu: delete for everyone leaves a placeholder',
      (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    const messageText = 'Sending the edited export now.';
    await tester.longPress(find.text(messageText));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('message_action_deleteForEveryone')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('message_action_deleteForEveryone')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm_delete_message_everyone_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text(messageText), findsNothing);
    expect(find.text('This message was deleted'), findsOneWidget);
  });

  testWidgets(
      'message long-press menu: editing shows the new text and '
      '"Edited"', (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    const originalText = 'Sending the edited export now.';
    await tester.longPress(find.text(originalText));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('message_action_edit')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('edit_message_field')),
      'Sending the final export now.',
    );
    await tester.tap(find.byKey(const Key('confirm_edit_message_button')));
    await tester.pumpAndSettle();

    expect(find.text('Sending the final export now.'), findsOneWidget);
    expect(find.text('Edited'), findsOneWidget);
  });

  testWidgets(
      'message long-press menu: forwarding sends the same text to another '
      'chat', (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    const messageText = 'Want the final export tonight?';
    await tester.longPress(find.text(messageText));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('message_action_forward')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forward_message_screen')), findsOneWidget);
    await tester.tap(find.byKey(const Key('forward_target_design-sprint')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forward_message_send_button')));
    await tester.pumpAndSettle();

    expect(find.text('Message forwarded'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat_tile_design-sprint')));
    await tester.pumpAndSettle();

    expect(find.text(messageText), findsWidgets);
  });

  testWidgets(
      'message long-press menu: starring shows a star icon, unstarring '
      'removes it', (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    const messageText = 'Want the final export tonight?';
    await tester.longPress(find.text(messageText));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('message_action_star')), findsOneWidget);
    await tester.tap(find.byKey(const Key('message_action_star')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_rounded), findsOneWidget);

    await tester.longPress(find.text(messageText));
    await tester.pumpAndSettle();
    expect(find.text('Unstar'), findsOneWidget);
    await tester.tap(find.byKey(const Key('message_action_star')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets(
      'message long-press menu: forwarding to multiple chats sends to all '
      'of them', (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    const messageText = 'Want the final export tonight?';
    await tester.longPress(find.text(messageText));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('message_action_forward')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forward_message_screen')), findsOneWidget);
    await tester.tap(find.byKey(const Key('forward_target_design-sprint')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forward_target_family')));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('forward_message_send_button')));
    await tester.pumpAndSettle();

    expect(find.text('Forwarded to 2 chats'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat_tile_design-sprint')));
    await tester.pumpAndSettle();
    expect(find.text(messageText), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat_tile_family')));
    await tester.pumpAndSettle();
    expect(find.text(messageText), findsWidgets);
  });

  testWidgets(
      'the reaction tray\'s + button opens a sheet-based emoji picker and '
      'reacts with the tapped emoji', (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    await tester.longPress(find.text(
      'The onboarding shots look good. The motion pacing feels much cleaner.',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reaction_option_custom')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reaction_option_custom')));
    await tester.pumpAndSettle();

    // A sheet presented over the conversation (search, recent, categories,
    // grid), not a separate pushed screen -- the composer's own TextField
    // is still in the tree underneath it, so scope finders to the sheet.
    final sheetFinder = find.byKey(const Key('emoji_reaction_picker_screen'));
    expect(sheetFinder, findsOneWidget);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: sheetFinder, matching: find.byType(TextField)),
      'unicorn',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('🦄'));
    await tester.pumpAndSettle();

    expect(sheetFinder, findsNothing);
    expect(find.text('🦄'), findsOneWidget);
  });

  testWidgets('contact info: clears chat, then blocks and hides the composer',
      (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ava Patel'));
    await tester.pumpAndSettle();

    expect(find.text('Contact info'), findsOneWidget);
    expect(
      find.byKey(const Key('contact_info_clear_chat_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('contact_info_clear_chat_button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('contact_info_confirm_clear_chat_button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contact_info_block_button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('contact_info_confirm_block_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Blocked'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('You blocked Ava Patel'), findsOneWidget);
    expect(
      find.byKey(const Key('conversation_composer_field')),
      findsNothing,
    );
  });

  testWidgets(
      'contact info: shared media shows as a disclosure row that opens the '
      'full grid', (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_ava-patel')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ava Patel'));
    await tester.pumpAndSettle();

    expect(find.text('Contact info'), findsOneWidget);
    // A row, not an inline grid -- ava-patel has exactly one shared photo
    // (see DemoData), so the row reads "1 item" and there's no standalone
    // media tile sitting directly in contact info.
    final rowFinder = find.byKey(const Key('contact_info_shared_media_row'));
    expect(rowFinder, findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
    expect(find.byKey(const Key('shared_media_ava-photo-1')), findsNothing);

    await tester.tap(rowFinder);
    await tester.pumpAndSettle();

    expect(find.text('Shared media'), findsOneWidget);
    expect(
      find.byKey(const Key('shared_media_screen_grid')),
      findsOneWidget,
    );
    final tileFinder = find.byKey(const Key('shared_media_ava-photo-1'));
    expect(tileFinder, findsOneWidget);

    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    expect(find.text('Onboarding board'), findsWidgets);
  });

  testWidgets(
      'group info: shows participants with admin badges and lets an admin '
      'rename the group, promote a member, and remove a member',
      (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_design-sprint')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Design Sprint'));
    await tester.pumpAndSettle();

    expect(find.text('Group info'), findsOneWidget);
    expect(find.text('3 participants'), findsOneWidget);
    // Scoped to each participant row's own key -- group message bubbles
    // also render the sender's name above them (see
    // ConversationScreen's `if (thread.isGroup && !isMine) Text(message.
    // senderName)`), so a bare find.text('Priya') would match twice while
    // the previous (still-mounted, offstage) conversation route is in the
    // Navigator stack underneath this pushed route.
    expect(
      find.descendant(
        of: find.byKey(const Key('participant_row_me')),
        matching: find.text('You'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('participant_row_priya')),
        matching: find.text('Priya'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('participant_row_marco')),
        matching: find.text('Marco'),
      ),
      findsOneWidget,
    );
    expect(find.text('Admin'), findsOneWidget);

    // Rename the group via Edit -> inline fields -> Done.
    await tester.tap(find.byKey(const Key('contact_info_edit_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('rename_group_field')),
      'Design Sprint 2.0',
    );
    await tester.tap(find.byKey(const Key('contact_info_save_button')));
    await tester.pumpAndSettle();

    expect(find.text('Design Sprint 2.0'), findsWidgets);

    // Promote Priya to admin.
    await tester.tap(find.byKey(const Key('participant_row_priya')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('participant_option_toggle_admin')));
    await tester.pumpAndSettle();

    expect(find.text('Admin'), findsNWidgets(2));

    // Remove Marco from the group.
    await tester.tap(find.byKey(const Key('participant_row_marco')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('participant_option_remove')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm_remove_participant_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 participants'), findsOneWidget);
    // Marco's own message bubble (sent before he was removed) is
    // untouched -- his name still renders there -- so this checks the
    // participant row specifically disappeared, not the word "Marco"
    // anywhere on screen.
    expect(find.byKey(const Key('participant_row_marco')), findsNothing);
  });

  testWidgets('group info: an admin can change the group icon', (tester) async {
    final controller = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
    );
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: controller,
    );

    await tester.tap(find.byKey(const Key('chat_tile_design-sprint')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Design Sprint'));
    await tester.pumpAndSettle();

    expect(find.text('Group info'), findsOneWidget);
    expect(controller.threadById('design-sprint')?.avatarUrl, isNull);

    await tester.tap(find.byKey(const Key('contact_info_edit_button')));
    await tester.pumpAndSettle();

    final iconButtonFinder =
        find.byKey(const Key('contact_info_change_group_icon_button'));
    expect(iconButtonFinder, findsOneWidget);

    await tester.tap(iconButtonFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('avatar_photo_choose_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contact_info_save_button')));
    await tester.pumpAndSettle();

    // FakeImagePickerPlatform (see setUp above) always resolves a single
    // pickImage call to this path.
    expect(
      controller.threadById('design-sprint')?.avatarUrl,
      '/fake/test-photo.jpg',
    );
  });

  testWidgets('group info: exiting a group returns to a closed conversation',
      (tester) async {
    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
    );

    await tester.tap(find.byKey(const Key('chat_tile_family')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contact_info_exit_group_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_exit_group_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('This conversation is no longer available.'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat_tile_family')), findsNothing);
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

    expect(find.byKey(const Key('conversation_voice_button')), findsOneWidget);
    expect(find.byKey(const Key('conversation_send_button')), findsNothing);

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
      'someone else\'s story shows a reply bar, and the heart button just '
      'fills in without sending a chat message', (tester) async {
    final avatarFinder =
        find.byKey(const ValueKey<String>('chat_story_avatar_ava-patel'));

    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
      updatesController: UpdatesController(
        repository: FakeUpdatesRepository(latency: Duration.zero),
      ),
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
    // Someone else's story -- a reply bar (text field + heart quick-react),
    // not the poster-only delete button.
    expect(
      find.byKey(const Key('updates_story_reply_field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('updates_story_delete_button')),
      findsNothing,
    );
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('updates_story_heart_react_button')),
    );
    // Not pumpAndSettle -- the story's own progress bar keeps animating
    // (tapping the heart doesn't pause it the way focusing the reply field
    // does).
    await tester.pump();
    await tester.pump();

    // Filled in, but no chat message (and no SnackBar) went out for it --
    // liking is a lightweight, message-free reaction (see
    // StatusStoryViewerScreen.onSetStoryLiked / _toggleHeart), unlike a typed
    // reply.
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    expect(find.text('Reply sent to Ava'), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // Reopen on the latest segment -- the heart stays outline until we go
    // back to the segment we liked earlier.
    await tester.ensureVisible(avatarFinder);
    await tester.pump();
    await tester.tap(avatarFinder);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('updates_story_viewer_left_zone')),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    // Unlike toggles back to outline.
    await tester.tap(
      find.byKey(const Key('updates_story_heart_react_button')),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // startThreadWith only ever runs for a typed reply -- liking never
    // creates (or reuses) the 1:1 thread keyed by the story's own id.
    expect(find.byKey(const Key('chat_tile_ava-story')), findsNothing);
  });

  testWidgets(
      'a typed story reply lands in chat as a message with a tappable '
      'story card', (tester) async {
    final avatarFinder =
        find.byKey(const ValueKey<String>('chat_story_avatar_ava-patel'));

    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
      updatesController: UpdatesController(
        repository: FakeUpdatesRepository(latency: Duration.zero),
      ),
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
    // Heart starts hollow -- only fills in after a successful send.
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    // The send button doesn't show until the field actually has focus.
    expect(
      find.byKey(const Key('updates_story_reply_send_button')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('updates_story_reply_field')));
    await tester.pump();
    expect(
      find.byKey(const Key('updates_story_reply_send_button')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('updates_story_reply_field')),
      'Nice shot!',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('updates_story_reply_send_button')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Reply sent to Ava'), findsOneWidget);
    // A typed reply isn't a heart -- the button stays hollow.
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // startThreadWith(participantUid: story.id) creates a thread keyed by
    // the story's own id ('ava-story'), distinct from the pre-existing
    // 'ava-patel' contact thread -- see DemoData.
    await tester.tap(find.byKey(const Key('chat_tile_ava-story')));
    await tester.pumpAndSettle();

    expect(find.text('Nice shot!'), findsOneWidget);
    final cardFinder = find.byKey(const Key('story_reply_card'));
    expect(cardFinder, findsOneWidget);
    expect(find.text('Replied to Ava\'s status'), findsOneWidget);

    // Not pumpAndSettle -- the reopened viewer's own progress bar keeps
    // animating (and, for a single-segment story, would run to completion
    // and auto-close the viewer if given unbounded time to settle).
    await tester.tap(cardFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('updates_story_viewer')), findsOneWidget);
  });

  testWidgets('your own story shows a view count instead of a reply bar',
      (tester) async {
    final updatesController = UpdatesController(
      repository: FakeUpdatesRepository(latency: Duration.zero),
    );
    await updatesController.ensureLoaded();
    await updatesController.createStatus(
      type: StatusStoryType.text,
      caption: 'Hello!',
    );

    await _pumpChatsScreen(
      tester,
      device: iphoneProProfile,
      controller: ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      ),
      updatesController: updatesController,
    );

    await tester.tap(find.byKey(const Key('chats_status_mine')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('updates_story_viewer')), findsOneWidget);
    expect(
      find.byKey(const Key('updates_story_viewer_count')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('updates_story_reply_field')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('updates_story_viewer_count')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('story_viewers_sheet')), findsOneWidget);
    expect(find.text('Viewed by'), findsOneWidget);
    // The fake repository never simulates other accounts viewing a story
    // (see FakeUpdatesRepository.fetchStoryViewers) -- this just confirms
    // the tap-to-open wiring and the sheet's empty state render correctly.
    expect(find.text('No views yet.'), findsOneWidget);
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

  testWidgets('keeps short conversations anchored near the composer',
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
    expect(messageListBottom - lastMessageBottom, closeTo(24, 4));
    expect(firstMessageTop - messageListTop, greaterThan(80));
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
    expect(find.text('Not sent'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Please retry this send.'), findsOneWidget);
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

int _groupChatVisibleMessageCount(WidgetTester tester) {
  final subtitleFinder = find.textContaining(' messages');
  expect(subtitleFinder, findsOneWidget);
  final text = tester.widget<Text>(subtitleFinder).data!;
  final match = RegExp(r'(\d+) messages').firstMatch(text);
  expect(match, isNotNull);
  return int.parse(match!.group(1)!);
}

Future<void> _openLocationSendPreview(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('conversation_location_button')));
  await tester.pump();
  // Attachment popup completes only after its close animation finishes.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _confirmLocationSendFromPreview(WidgetTester tester) async {
  expect(
    find.byKey(const Key('location_send_preview_screen')),
    findsOneWidget,
  );
  await tester.ensureVisible(
    find.byKey(const Key('location_send_selected_location_button')),
  );
  await tester.pump();
  await tester.tap(
    find.byKey(const Key('location_send_selected_location_button')),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  expect(
    find.byKey(const Key('location_send_preview_screen')),
    findsNothing,
  );
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpChatsScreen(
  WidgetTester tester, {
  required TestDeviceProfile device,
  required ChatsController controller,
  UpdatesController? updatesController,
  AuthController? authController,
  bool animateTypingIndicators = false,
}) async {
  await tester.binding.setSurfaceSize(device.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final resolvedUpdatesController = updatesController ??
      UpdatesController(
        repository: FakeUpdatesRepository(latency: Duration.zero),
      );
  final resolvedAuthController = authController ??
      AuthController(
        repository: FakeAuthRepository(latency: Duration.zero),
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
          authController: resolvedAuthController,
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
  Future<void> markThreadRead(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<ChatThread> fetchThreadWithMessages(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
    bool isCommunityGroup = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> setThreadBlocked({
    required String threadId,
    required bool isBlocked,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> clearThreadMessages(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> groupThreadsSharedWith(String participantUid) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
    MessageReplyPreview? replyPreview,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> toggleMessageReaction({
    required String threadId,
    required String messageId,
    required String emoji,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> sendTextMessage({
    required String threadId,
    required String text,
    StoryReplyContext? storyReplyContext,
    MessageReplyPreview? replyPreview,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> editMessage({
    required String threadId,
    required String messageId,
    required String text,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> deleteMessage({
    required String threadId,
    required String messageId,
    required bool forEveryone,
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

  @override
  Future<List<Never>> addGroupMembers({
    required String threadId,
    required List<String> memberUids,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> removeGroupMember({
    required String threadId,
    required String memberUid,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> leaveGroup(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> setGroupAdmin({
    required String threadId,
    required String memberUid,
    required bool isAdmin,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> renameGroup({
    required String threadId,
    required String name,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> updateGroupDescription({
    required String threadId,
    required String description,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> updateGroupAvatar({
    required String threadId,
    required File photo,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> deleteGroupAvatar(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<List<Never>> toggleMessageStar({
    required String threadId,
    required String messageId,
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
  Future<ChatThread> fetchThreadWithMessages(String threadId) =>
      _delegate.fetchThreadWithMessages(threadId);

  @override
  Future<void> markThreadRead(String threadId) =>
      _delegate.markThreadRead(threadId);

  @override
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
    bool isCommunityGroup = false,
  }) =>
      _delegate.createGroup(
        name: name,
        memberUids: memberUids,
        isCommunityGroup: isCommunityGroup,
      );

  @override
  Future<List<ChatThread>> setThreadBlocked({
    required String threadId,
    required bool isBlocked,
  }) =>
      _delegate.setThreadBlocked(threadId: threadId, isBlocked: isBlocked);

  @override
  Future<List<ChatThread>> clearThreadMessages(String threadId) =>
      _delegate.clearThreadMessages(threadId);

  @override
  Future<List<ChatThread>> groupThreadsSharedWith(String participantUid) =>
      _delegate.groupThreadsSharedWith(participantUid);

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
    MessageReplyPreview? replyPreview,
  }) =>
      _delegate.sendAttachmentMessage(
        threadId: threadId,
        attachments: attachments,
        caption: caption,
        replyPreview: replyPreview,
      );

  @override
  Future<List<ChatThread>> toggleMessageReaction({
    required String threadId,
    required String messageId,
    required String emoji,
  }) =>
      _delegate.toggleMessageReaction(
        threadId: threadId,
        messageId: messageId,
        emoji: emoji,
      );

  @override
  Future<List<ChatThread>> toggleMessageStar({
    required String threadId,
    required String messageId,
  }) =>
      _delegate.toggleMessageStar(threadId: threadId, messageId: messageId);

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
    StoryReplyContext? storyReplyContext,
    MessageReplyPreview? replyPreview,
  }) {
    if (_shouldFailNextTextSend) {
      _shouldFailNextTextSend = false;
      throw const ChatRepositoryException('Message service offline');
    }
    return _delegate.sendTextMessage(
      threadId: threadId,
      text: text,
      storyReplyContext: storyReplyContext,
      replyPreview: replyPreview,
    );
  }

  @override
  Future<List<ChatThread>> editMessage({
    required String threadId,
    required String messageId,
    required String text,
  }) =>
      _delegate.editMessage(
          threadId: threadId, messageId: messageId, text: text);

  @override
  Future<List<ChatThread>> deleteMessage({
    required String threadId,
    required String messageId,
    required bool forEveryone,
  }) =>
      _delegate.deleteMessage(
        threadId: threadId,
        messageId: messageId,
        forEveryone: forEveryone,
      );

  @override
  Future<List<ChatThread>> setThreadArchived({
    required String threadId,
    required bool isArchived,
  }) =>
      _delegate.setThreadArchived(
        threadId: threadId,
        isArchived: isArchived,
      );

  @override
  Future<List<ChatThread>> addGroupMembers({
    required String threadId,
    required List<String> memberUids,
  }) =>
      _delegate.addGroupMembers(threadId: threadId, memberUids: memberUids);

  @override
  Future<List<ChatThread>> removeGroupMember({
    required String threadId,
    required String memberUid,
  }) =>
      _delegate.removeGroupMember(threadId: threadId, memberUid: memberUid);

  @override
  Future<List<ChatThread>> leaveGroup(String threadId) =>
      _delegate.leaveGroup(threadId);

  @override
  Future<List<ChatThread>> setGroupAdmin({
    required String threadId,
    required String memberUid,
    required bool isAdmin,
  }) =>
      _delegate.setGroupAdmin(
        threadId: threadId,
        memberUid: memberUid,
        isAdmin: isAdmin,
      );

  @override
  Future<List<ChatThread>> renameGroup({
    required String threadId,
    required String name,
  }) =>
      _delegate.renameGroup(threadId: threadId, name: name);

  @override
  Future<List<ChatThread>> updateGroupDescription({
    required String threadId,
    required String description,
  }) =>
      _delegate.updateGroupDescription(
        threadId: threadId,
        description: description,
      );

  @override
  Future<List<ChatThread>> updateGroupAvatar({
    required String threadId,
    required File photo,
  }) =>
      _delegate.updateGroupAvatar(threadId: threadId, photo: photo);

  @override
  Future<List<ChatThread>> deleteGroupAvatar(String threadId) =>
      _delegate.deleteGroupAvatar(threadId);
}

class _FakeDeviceLocationService implements DeviceLocationService {
  const _FakeDeviceLocationService({required this.fix});

  final DeviceLocationFix fix;

  @override
  Future<DeviceLocationFix> getCurrentLocation() async => fix;
}
