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
import 'package:whatswave/features/chats/presentation/chats_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

import '../../../support/device_matrix.dart';

/// A single message carrying [count] photos, the shape a multi-select
/// gallery pick produces.
ChatThread _albumThread(int count, {List<double>? aspects}) {
  return ChatThread(
    id: 'album-thread',
    name: 'Album Sender',
    avatarLabel: 'AS',
    accentColor: const Color(0xFF128C7E),
    messages: [
      ChatMessage(
        id: 'long-text-message',
        senderName: 'Album Sender',
        sentAt: DateTime(2026, 1, 1, 8),
        isFromCurrentUser: false,
        text: 'A long enough line of text that the bubble around it runs '
            'out to its own full width rather than hugging the words.',
      ),
      ChatMessage(
        id: 'album-message',
        senderName: 'Album Sender',
        sentAt: DateTime(2026, 1, 1, 9),
        isFromCurrentUser: false,
        // A caption is what stretched the bubble: the caption row fills the
        // bubble's width, so the bubble ran to its 320 cap around a
        // 250-wide mosaic and left a band of empty green down the right.
        text: 'a caption',
        attachments: [
          for (var index = 0; index < count; index++)
            ChatAttachment(
              id: 'album-photo-$index',
              type: ChatAttachmentType.photo,
              title: 'Photo ${index + 1}',
              details: 'JPG',
              tintColor: const Color(0xFF128C7E),
              aspectRatio: aspects == null ? 1.25 : aspects[index],
            ),
        ],
      ),
    ],
  );
}

Future<void> _openAlbumThread(
  WidgetTester tester, {
  required int photos,
  List<double>? aspects,
}) async {
  await tester.binding.setSurfaceSize(iphoneProProfile.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
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
              initialThreads: [_albumThread(photos, aspects: aspects)],
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
  await tester.tap(find.byKey(const Key('chat_tile_album-thread')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'an album bubble shows at most four tiles and counts the rest',
    (tester) async {
      await _openAlbumThread(tester, photos: 16);

      // Four tiles, not sixteen -- a bubble that renders every photo grows
      // taller than the screen.
      expect(find.byKey(const Key('attachment_preview_album-photo-3')),
          findsOneWidget);
      expect(find.byKey(const Key('attachment_preview_album-photo-4')),
          findsNothing);
      expect(
        find.byKey(const Key('chat_album_overflow_count')),
        findsOneWidget,
      );
      expect(find.text('+12'), findsOneWidget);
    },
  );

  testWidgets('a pair sits side by side, so each photo gets an upright slot',
      (tester) async {
    await _openAlbumThread(tester, photos: 2, aspects: [1.5, 1.5]);

    final first = tester.getRect(
      find.byKey(const Key('attachment_preview_album-photo-0')),
    );
    final second = tester.getRect(
      find.byKey(const Key('attachment_preview_album-photo-1')),
    );
    // Beside, not below.
    expect(second.left, greaterThan(first.right - 1));
    expect(second.top, first.top);
    // A square block split into two rows would have made each photo a wide
    // strip; split into two columns each one is taller than it is wide.
    expect(first.height, greaterThan(first.width));
  });

  testWidgets('three photos put the tallest one in the hero slot',
      (tester) async {
    // The hero slot is half the width and the full height. Photo 2 is the
    // only portrait one, so it belongs there however the three were picked.
    await _openAlbumThread(tester, photos: 3, aspects: [1.5, 1.4, 0.6]);

    final hero = tester.getRect(
      find.byKey(const Key('attachment_preview_album-photo-2')),
    );
    final other = tester.getRect(
      find.byKey(const Key('attachment_preview_album-photo-0')),
    );
    expect(hero.height, greaterThan(other.height * 1.5));
    expect(hero.left, lessThan(other.left));
  });

  testWidgets('four photos fill a square 2x2', (tester) async {
    await _openAlbumThread(tester, photos: 4);

    final mosaic = find
        .ancestor(
          of: find.byKey(const Key('attachment_preview_album-photo-0')),
          matching: find.byType(AspectRatio),
        )
        .last;
    expect(tester.widget<AspectRatio>(mosaic).aspectRatio, 1.0);

    // Only the mosaic's outer edge is round, so neighbours meet flush
    // instead of each cutting a notch out of the next.
    for (var index = 0; index < 4; index++) {
      final clip = tester.widget<ClipRRect>(
        find
            .ancestor(
              of: find.byKey(Key('attachment_preview_album-photo-$index')),
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      expect(clip.borderRadius, BorderRadius.zero, reason: 'tile $index');
    }
  });

  testWidgets(
    'the viewer opens on the tapped photo and pages the whole album',
    (tester) async {
      await _openAlbumThread(tester, photos: 16);

      await tester.tap(find.byKey(const Key('attachment_preview_album-photo-1')));
      await tester.pumpAndSettle();

      // Opened on the tapped photo, not the first one.
      expect(find.byKey(const Key('attachment_viewer_pager')), findsOneWidget);
      expect(find.text('2 of 16'), findsOneWidget);

      // The twelve photos the bubble had to hide are reachable by swiping
      // the pager -- the counter is what says where you are.
      await tester.fling(
        find.byKey(const Key('attachment_viewer_pager')),
        const Offset(-400, 0),
        1200,
      );
      await tester.pumpAndSettle();
      expect(find.text('3 of 16'), findsOneWidget);
    },
  );

  testWidgets(
    'a lone photo gets no pager and no counter',
    (tester) async {
      await _openAlbumThread(tester, photos: 1);

      await tester.tap(find.byKey(const Key('attachment_preview_album-photo-0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('attachment_viewer_pager')), findsNothing);
      expect(
        find.byKey(const Key('attachment_viewer_page_label')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('attachment_viewer_close_button')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a media bubble is exactly as wide as its media, and text is not',
    (tester) async {
      await _openAlbumThread(tester, photos: 16);

      final mosaic = find
          .ancestor(
            of: find.byKey(const Key('attachment_preview_album-photo-0')),
            matching: find.byType(AspectRatio),
          )
          .last;
      final mediaBubble = find
          .ancestor(of: mosaic, matching: find.byType(AnimatedContainer))
          .first;

      expect(tester.getSize(mosaic).width, 250);
      expect(
        tester.getSize(mediaBubble).width,
        tester.getSize(mosaic).width,
        reason: 'no dead bubble to the right of the media',
      );

      // A text bubble keeps its own, wider cap -- this narrows media, not
      // every message in the thread.
      final textBubble = find
          .ancestor(
            of: find.textContaining('A long enough line of text'),
            matching: find.byType(AnimatedContainer),
          )
          .first;
      expect(tester.getSize(textBubble).width, greaterThan(250));
    },
  );

  for (final count in [2, 3, 4, 16]) {
    testWidgets('an album of $count is the same height as any other',
        (tester) async {
      // A thread with a run of albums scrolls with a steady rhythm only if
      // they all measure the same; per-count block shapes made each one its
      // own size.
      await _openAlbumThread(tester, photos: count);

      final mosaic = find
          .ancestor(
            of: find.byKey(const Key('attachment_preview_album-photo-0')),
            matching: find.byType(AspectRatio),
          )
          .last;
      expect(tester.widget<AspectRatio>(mosaic).aspectRatio, 1.0);
      final size = tester.getSize(mosaic);
      expect(size.height, size.width);
    });
  }
}
