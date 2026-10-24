import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/presentation/contact_info_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

import '../../support/device_matrix.dart';

/// ContactInfoScreen is two screens wearing one name: "Contact info" for a
/// 1:1 thread and "Group info" (participant roster, admin chips, add/remove)
/// for a group one. They lay out differently enough that covering only one
/// would leave the other's rows unswept.
Future<void> _expectThreadSurvives(
  WidgetTester tester,
  String threadId,
) async {
  final chats = ChatsController(
    repository: FakeChatRepository(latency: Duration.zero),
    permissionService: MemoryAppPermissionService(),
  );
  await chats.ensureLoaded();
  // Resolve it first: an id that is not in the sample data would render the
  // screen's own fallback, and the sweep would pass having laid out nothing.
  expect(chats.threadById(threadId), isNotNull, reason: threadId);

  await expectScreenSurvivesLayoutMatrix(
    tester,
    build: () => MaterialApp(
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: ContactInfoScreen(
        controller: chats,
        communitiesController: CommunitiesController(
          repository: FakeCommunitiesRepository(latency: Duration.zero),
        ),
        callsController: CallsController(
          repository: FakeCallsRepository(latency: Duration.zero),
        ),
        updatesController: UpdatesController(
          repository: FakeUpdatesRepository(latency: Duration.zero),
        ),
        threadId: threadId,
      ),
    ),
  );
}

void main() {
  testWidgets('ContactInfoScreen survives the layout matrix for a group',
      (tester) async {
    await _expectThreadSurvives(tester, 'design-sprint');
  });

  testWidgets('ContactInfoScreen survives the layout matrix for a contact',
      (tester) async {
    await _expectThreadSurvives(tester, 'ava-patel');
  });
}
