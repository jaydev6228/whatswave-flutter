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
import 'package:whatswave/features/chats/presentation/chats_screen.dart';
import 'package:whatswave/features/shared/widgets/liquid_glass.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

import '../../../support/device_matrix.dart';

Future<void> _openInfo(
  WidgetTester tester, {
  required String tileKey,
  required String headerName,
}) async {
  await tester.binding.setSurfaceSize(iphoneProProfile.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

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
          controller: ChatsController(
            repository: FakeChatRepository(latency: Duration.zero),
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
  await tester.tap(find.byKey(Key(tileKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(headerName).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('contact info drops the "Contact" subtitle and the About caption',
      (tester) async {
    await _openInfo(tester, tileKey: 'chat_tile_ava-patel', headerName: 'Ava Patel');

    // The subtitle told the reader nothing they did not already know from
    // the screen they opened.
    expect(find.text('Contact'), findsNothing);
    // The value stays; the caption under it was labelling the obvious and
    // made a fact about the person read like a settings row.
    expect(
      find.text('Shipping launch polish and keeping reviews calm.'),
      findsOneWidget,
    );
    expect(find.text('About'), findsNothing);
  });

  testWidgets('group info drops the "Group - N messages" subtitle',
      (tester) async {
    await _openInfo(
      tester,
      tileKey: 'chat_tile_design-sprint',
      headerName: 'Design Sprint',
    );

    expect(find.textContaining('messages'), findsNothing);
    expect(find.textContaining('Group ·'), findsNothing);
  });

  testWidgets('tapping the avatar opens it full screen and closes again',
      (tester) async {
    await _openInfo(tester, tileKey: 'chat_tile_ava-patel', headerName: 'Ava Patel');

    expect(find.byKey(const Key('avatar_preview_close_button')), findsNothing);

    await tester.tap(find.byKey(const Key('contact_info_avatar')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('avatar_preview_close_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('avatar_preview_close_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('avatar_preview_close_button')), findsNothing);
  });

  testWidgets('a group icon opens full screen too', (tester) async {
    // A group icon is composed on the fly from members' avatars when no
    // photo is set, so it has no image to open -- it has to be re-rendered
    // at the larger size instead.
    await _openInfo(
      tester,
      tileKey: 'chat_tile_design-sprint',
      headerName: 'Design Sprint',
    );

    await tester.tap(find.byKey(const Key('contact_info_avatar')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('avatar_preview_close_button')),
      findsOneWidget,
    );
  });

  testWidgets(
    'the group icon options open as the app\'s bubble, not a modal sheet',
    (tester) async {
      await _openInfo(
        tester,
        tileKey: 'chat_tile_design-sprint',
        headerName: 'Design Sprint',
      );

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('contact_info_change_group_icon_button')),
      );
      await tester.pumpAndSettle();

      // The same liquid-glass bubble the status "+" opens, anchored to the
      // avatar -- not a panel sliding up over the whole screen.
      expect(find.byType(LiquidGlassBubbleItem), findsWidgets);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.byKey(const Key('avatar_photo_choose_button')),
        findsOneWidget,
      );
      // Narrow bubbles anchored to a centred avatar used to overflow.
      expect(tester.takeException(), isNull);
    },
  );
}
