import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/presentation/new_chat_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/community_contact.dart';
import 'package:whatswave/features/communities/domain/contact_access_status.dart';

import '../../support/device_matrix.dart';

/// One contact already on WhatsWave (so the message/call/video action row
/// renders) and one who isn't (the invite row) -- the two row shapes the
/// contact list can take.
const _contacts = <CommunityContact>[
  CommunityContact(
    id: 'ava-patel',
    name: 'Ava Patel',
    phoneNumber: '+81 90 3000 1122',
    avatarLabel: 'AP',
    accentColor: AppPalette.green,
    about: 'Already on WhatsWave.',
    matchedUid: 'uid-ava',
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
];

Widget _screen({
  required CommunitiesController communitiesController,
  required ChatsController chatsController,
  required CallsController callsController,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme(),
    darkTheme: AppTheme.darkTheme(),
    home: NewChatScreen(
      communitiesController: communitiesController,
      chatsController: chatsController,
      callsController: callsController,
    ),
  );
}

void main() {
  testWidgets('NewChatScreen survives the layout matrix with contacts',
      (tester) async {
    final communitiesController = CommunitiesController(
      repository: FakeCommunitiesRepository(
        latency: Duration.zero,
        initialContacts: _contacts,
      ),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );
    addTearDown(communitiesController.dispose);
    final chatsController = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
    );
    await chatsController.loadThreads();
    addTearDown(chatsController.dispose);
    final callsController = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
    );
    addTearDown(callsController.dispose);

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => _screen(
        communitiesController: communitiesController,
        chatsController: chatsController,
        callsController: callsController,
      ),
    );
  });

  testWidgets(
      'NewChatScreen survives the layout matrix with contacts access off',
      (tester) async {
    final communitiesController = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.denied,
      ),
    );
    addTearDown(communitiesController.dispose);
    final chatsController = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
    );
    await chatsController.loadThreads();
    addTearDown(chatsController.dispose);
    final callsController = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
    );
    addTearDown(callsController.dispose);

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => _screen(
        communitiesController: communitiesController,
        chatsController: chatsController,
        callsController: callsController,
      ),
    );
  });

  // Separate from the sweeps above on purpose: a contrast failure
  // reported as a layout failure helps nobody. Pumped once at one
  // realistic size, then asserted against that rendered tree -- running
  // the guidelines before pumpWidget checks an empty tree and passes
  // trivially.
  testWidgets(
    'NewChatScreen meets the accessibility guidelines',
    (tester) async {
      final communitiesController = CommunitiesController(
        repository: FakeCommunitiesRepository(
          latency: Duration.zero,
          initialContacts: _contacts,
        ),
        permissionService: MemoryAppPermissionService(
          contactsStatus: ContactAccessStatus.granted,
        ),
      );
      addTearDown(communitiesController.dispose);
      final chatsController = ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      );
      await chatsController.loadThreads();
      addTearDown(chatsController.dispose);
      final callsController = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
      );
      addTearDown(callsController.dispose);

      await expectScreenSurvivesLayoutMatrix(
        tester,
        build: () => _screen(
          communitiesController: communitiesController,
          chatsController: chatsController,
          callsController: callsController,
        ),
        devices: const [iphoneProProfile],
        variants: const [defaultVariant],
      );
      expect(
        find.byKey(const Key('new_chat_screen')),
        findsOneWidget,
        reason: 'the guidelines must run against a rendered screen',
      );
      // The Invite capsule's tap target was grown to 48x48 without
      // repainting it (see _InviteContactTile). Guard the painted height,
      // because the padding there is what keeps it at 32.
      expect(
        tester
            .getSize(
              find
                  .descendant(
                    of: find.byKey(const Key('new_chat_invite_emi-tanaka')),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .height,
        32.0,
      );
      await expectScreenMeetsAccessibilityGuidelines(tester);
    },
    // All four guidelines pass now. Three things had to change: the
    // "Invite" capsule got a 48x48 hit area behind the same painted
    // capsule, the shared SearchField went from 42pt to 48pt, and
    // AppPalette.emerald was darkened to #0E7268, which took the section
    // labels on cloud from 3.84 to 5.38.
  );
}
