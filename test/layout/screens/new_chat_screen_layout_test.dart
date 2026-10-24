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
}
