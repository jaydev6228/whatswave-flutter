import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/media/media_transfer.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/auth/application/auth_controller.dart';
import 'package:whatswave/features/auth/data/fake_auth_repository.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';
import 'package:whatswave/features/chats/domain/chat_message.dart';
import 'package:whatswave/features/chats/domain/chat_thread.dart';
import 'package:whatswave/features/chats/presentation/chats_screen.dart';
import 'package:whatswave/features/chats/presentation/widgets/media_transfer_chrome.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

import '../../../support/device_matrix.dart';
import '../../../support/fake_image_picker_platform.dart';

ChatThread _thread({
  List<ChatAttachment> incoming = const [],
  List<ChatAttachment> outgoing = const [],
}) {
  return ChatThread(
    id: 'transfer-thread',
    name: 'Transfer',
    avatarLabel: 'TR',
    accentColor: const Color(0xFF128C7E),
    messages: [
      ChatMessage(
        id: 'seed',
        senderName: 'Transfer',
        sentAt: DateTime(2026, 1, 1, 8),
        isFromCurrentUser: false,
        text: 'Seed',
      ),
      if (incoming.isNotEmpty)
        ChatMessage(
          id: 'incoming-media',
          senderName: 'Transfer',
          sentAt: DateTime(2026, 1, 1, 9),
          isFromCurrentUser: false,
          attachments: incoming,
        ),
      if (outgoing.isNotEmpty)
        ChatMessage(
          id: 'outgoing-media',
          senderName: 'You',
          sentAt: DateTime(2026, 1, 1, 10),
          isFromCurrentUser: true,
          attachments: outgoing,
        ),
    ],
  );
}

Future<ChatsController> _openThread(
  WidgetTester tester, {
  required FakeChatRepository repository,
}) async {
  await tester.binding.setSurfaceSize(iphoneProProfile.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final controller = ChatsController(
    repository: repository,
    permissionService: MemoryAppPermissionService(),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Scaffold(
        body: ChatsScreen(
          callsController: CallsController(
            repository: FakeCallsRepository(latency: Duration.zero),
          ),
          communitiesController: CommunitiesController(
            repository: FakeCommunitiesRepository(latency: Duration.zero),
          ),
          controller: controller,
          updatesController: UpdatesController(
            repository: FakeUpdatesRepository(latency: Duration.zero),
          ),
          authController: AuthController(
            repository: FakeAuthRepository(latency: Duration.zero),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('chat_tile_transfer-thread')));
  await tester.pumpAndSettle();
  return controller;
}

ChatAttachment _photo(String id, {String? path, int? sizeBytes}) {
  return ChatAttachment(
    id: id,
    type: ChatAttachmentType.photo,
    title: 'Photo',
    details: '',
    tintColor: const Color(0xFF128C7E),
    localMediaPath: path,
    sizeBytes: sizeBytes,
  );
}

void main() {
  testWidgets(
    'an uploading message shows a ring that advances with the bytes',
    (tester) async {
      ImagePickerPlatform.instance = FakeImagePickerPlatform();

      MediaTransfer? captured;
      // Long enough that the send is still in flight while the assertions
      // run -- the ring only exists for as long as the upload does.
      final repository = FakeChatRepository(
        latency: const Duration(seconds: 5),
        initialThreads: [_thread()],
        onAttachmentTransfer: (transfer) => captured = transfer,
      );

      await _openThread(tester, repository: repository);

      await tester.tap(
        find.byKey(const Key('conversation_attachment_menu_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conversation_photo_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('media_send_preview_send_button')),
      );
      // Pump the route pop, but not the send: pumpAndSettle here would run
      // the whole upload to completion and there would be nothing to see.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(captured, isNotNull, reason: 'the send handed down a transfer');

      CircularProgressIndicator ring() =>
          tester.widget<CircularProgressIndicator>(
            find.descendant(
              of: find.byType(MediaTransferRing),
              matching: find.byType(CircularProgressIndicator),
            ),
          );

      // Nothing has reported a size yet, so the ring spins rather than
      // claiming a percentage nobody measured.
      expect(ring().value, isNull);

      captured!.report('up-1', transferred: 25, total: 100);
      await tester.pump();
      expect(ring().value, closeTo(0.25, 0.001));

      await tester.pumpAndSettle(const Duration(seconds: 10));
      // The ring goes when the send does.
      expect(find.byType(MediaTransferRing), findsNothing);
    },
  );

  testWidgets(
    'incoming media that is only a URL offers a download button first',
    (tester) async {
      await _openThread(
        tester,
        repository: FakeChatRepository(
          latency: Duration.zero,
          initialThreads: [
            _thread(
              incoming: [
                _photo(
                  'down-1',
                  path: 'https://example.com/down-1.jpg',
                  sizeBytes: 416 * 1024,
                ),
              ],
            ),
          ],
        ),
      );

      // The size comes from the attachment, so the reader knows what the
      // tap will cost before making it.
      expect(
        find.byKey(const Key('media_download_button_incoming-media')),
        findsOneWidget,
      );
      expect(find.text('416 KB'), findsOneWidget);
    },
  );

  testWidgets(
    'media already on the device gets no ring and no download button',
    (tester) async {
      await _openThread(
        tester,
        repository: FakeChatRepository(
          latency: Duration.zero,
          initialThreads: [
            _thread(incoming: [_photo('local-1', path: '/on/device.jpg')]),
          ],
        ),
      );

      expect(
        find.byKey(const Key('media_download_button_incoming-media')),
        findsNothing,
      );
      expect(find.byType(MediaTransferRing), findsNothing);
    },
  );

  testWidgets(
    'media you sent yourself never offers to download itself back',
    (tester) async {
      // Once the upload finishes the attachment points at its Storage URL,
      // which is not in this device's disk cache -- so a gate keyed on
      // "remote and uncached" offered to download a photo this device had
      // just sent, over placeholder tiles.
      await _openThread(
        tester,
        repository: FakeChatRepository(
          latency: Duration.zero,
          initialThreads: [
            _thread(
              outgoing: [
                _photo(
                  'sent-1',
                  path: 'https://example.com/sent-1.jpg',
                  sizeBytes: 416 * 1024,
                ),
              ],
            ),
          ],
        ),
      );

      expect(
        find.byKey(const Key('media_download_button_outgoing-media')),
        findsNothing,
      );
      expect(find.text('416 KB'), findsNothing);
    },
  );
}
