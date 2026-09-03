import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
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
import 'package:whatswave/features/chats/domain/group_participant.dart';
import 'package:whatswave/features/chats/presentation/chats_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

import '../../../support/device_matrix.dart';

const _threadId = 'header-thread';

GroupParticipant _member(String name, {bool isSelf = false}) {
  return GroupParticipant(
    uid: name.toLowerCase(),
    name: name,
    avatarLabel: name.substring(0, 2).toUpperCase(),
    accentColor: const Color(0xFF128C7E),
    isSelf: isSelf,
  );
}

ChatThread _thread({
  bool isGroup = false,
  List<GroupParticipant>? participants,
  List<ChatAttachment> incoming = const [],
}) {
  return ChatThread(
    id: _threadId,
    name: 'Ava Patel',
    avatarLabel: 'AP',
    accentColor: const Color(0xFF128C7E),
    isGroup: isGroup,
    participants: participants,
    messages: [
      ChatMessage(
        id: 'seed',
        senderName: 'Ava Patel',
        sentAt: DateTime(2026, 1, 1, 8),
        isFromCurrentUser: false,
        text: 'Seed',
      ),
      if (incoming.isNotEmpty)
        ChatMessage(
          id: 'incoming-media',
          senderName: 'Ava Patel',
          sentAt: DateTime(2026, 1, 1, 9),
          isFromCurrentUser: false,
          attachments: incoming,
        ),
    ],
  );
}

ChatAttachment _video(String id, {String? path, int? sizeBytes}) {
  return ChatAttachment(
    id: id,
    type: ChatAttachmentType.video,
    title: 'Video',
    details: '',
    tintColor: const Color(0xFF128C7E),
    localMediaPath: path,
    sizeBytes: sizeBytes,
  );
}

Future<void> _openThread(
  WidgetTester tester, {
  required ChatThread thread,
  TestDeviceProfile device = iphoneProProfile,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(device.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: ChatsScreen(
          callsController: CallsController(
            repository: FakeCallsRepository(latency: Duration.zero),
          ),
          communitiesController: CommunitiesController(
            repository: FakeCommunitiesRepository(latency: Duration.zero),
          ),
          controller: ChatsController(
            repository: FakeChatRepository(
              latency: Duration.zero,
              initialThreads: [thread],
            ),
            permissionService: MemoryAppPermissionService(),
          ),
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
  await tester.tap(find.byKey(const Key('chat_tile_$_threadId')));
  await tester.pumpAndSettle();
}

Finder _playBadge(String attachmentId) {
  return find.descendant(
    of: find.byKey(Key('attachment_preview_$attachmentId')),
    matching: find.byIcon(Icons.play_arrow_rounded),
  );
}

void main() {
  testWidgets('a 1:1 conversation header is just the name', (tester) async {
    await _openThread(tester, thread: _thread());

    expect(find.text('Ava Patel'), findsWidgets);
    expect(find.text('Secure chat preview'), findsNothing);
  });

  testWidgets(
    'a group header lists members comma separated with You last',
    (tester) async {
      await _openThread(
        tester,
        thread: _thread(
          isGroup: true,
          participants: [
            _member('You', isSelf: true),
            _member('Priya'),
            _member('Marco'),
          ],
        ),
      );

      expect(find.text('Priya, Marco, You'), findsOneWidget);
      expect(find.textContaining('Group chat'), findsNothing);
    },
  );

  testWidgets(
    'a long member list stays one ellipsised line on a compact phone at '
    'the largest text scale',
    (tester) async {
      await _openThread(
        tester,
        device: androidSmallProfile,
        textScale: 2,
        thread: _thread(
          isGroup: true,
          participants: [
            _member('You', isSelf: true),
            for (final name in [
              'Priyadarshini',
              'Massimiliano',
              'Konstantinos',
              'Bartholomew',
              'Ekaterina',
            ])
              _member(name),
          ],
        ),
      );

      final subtitle = tester.widget<Text>(
        find.text(
          'Priyadarshini, Massimiliano, Konstantinos, Bartholomew, '
          'Ekaterina, You',
        ),
      );
      expect(subtitle.maxLines, 1);
      expect(subtitle.overflow, TextOverflow.ellipsis);
      // A non-flex Text in the header Row has overflowed here before.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a video waiting to be downloaded shows the download button and not '
    'the play badge',
    (tester) async {
      await _openThread(
        tester,
        thread: _thread(
          incoming: [
            _video(
              'gated-video',
              path: 'https://example.com/gated-video.mp4',
              sizeBytes: 2 * 1024 * 1024,
            ),
          ],
        ),
      );

      expect(
        find.byKey(const Key('media_download_button_incoming-media')),
        findsOneWidget,
      );
      expect(_playBadge('gated-video'), findsNothing);
    },
  );

  testWidgets(
    'a video already on the device shows the play badge and no download '
    'button',
    (tester) async {
      await _openThread(
        tester,
        thread: _thread(
          incoming: [_video('local-video', path: '/on/device.mp4')],
        ),
      );

      expect(
        find.byKey(const Key('media_download_button_incoming-media')),
        findsNothing,
      );
      expect(_playBadge('local-video'), findsOneWidget);
    },
  );
}
