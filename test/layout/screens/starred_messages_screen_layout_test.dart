import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/presentation/starred_messages_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

import '../../support/device_matrix.dart';

void main() {
  testWidgets('StarredMessagesScreen survives the layout matrix with entries',
      (tester) async {
    // Nothing in the demo data is starred, so an unseeded controller would
    // only ever render the empty state -- the rows are the part with a
    // Row of avatar + sender + timestamp in it.
    final threads = DemoData.buildChatThreads()
        .map(
          (thread) => thread.copyWith(
            messages: thread.messages
                .map((message) => message.copyWith(isStarred: true))
                .toList(growable: false),
          ),
        )
        .toList(growable: false);

    final chatsController = ChatsController(
      repository: FakeChatRepository(
        initialThreads: threads,
        latency: Duration.zero,
      ),
    );
    await chatsController.loadThreads();
    await chatsController.refreshStarredMessages();
    addTearDown(chatsController.dispose);

    final callsController = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
    );
    addTearDown(callsController.dispose);
    final updatesController = UpdatesController(
      repository: FakeUpdatesRepository(latency: Duration.zero),
    );
    addTearDown(updatesController.dispose);
    final communitiesController = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
    );
    addTearDown(communitiesController.dispose);

    expect(chatsController.starredMessages, isNotEmpty);

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: StarredMessagesScreen(
          chatsController: chatsController,
          callsController: callsController,
          updatesController: updatesController,
          communitiesController: communitiesController,
        ),
      ),
    );
  });

  testWidgets(
    'StarredMessagesScreen empty state survives the layout matrix',
    (tester) async {
      final chatsController = ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      );
      await chatsController.loadThreads();
      addTearDown(chatsController.dispose);
      final callsController = CallsController(
        repository: FakeCallsRepository(latency: Duration.zero),
      );
      addTearDown(callsController.dispose);
      final updatesController = UpdatesController(
        repository: FakeUpdatesRepository(latency: Duration.zero),
      );
      addTearDown(updatesController.dispose);
      final communitiesController = CommunitiesController(
        repository: FakeCommunitiesRepository(latency: Duration.zero),
      );
      addTearDown(communitiesController.dispose);

      await expectScreenSurvivesLayoutMatrix(
        tester,
        build: () => MaterialApp(
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          home: StarredMessagesScreen(
            chatsController: chatsController,
            callsController: callsController,
            updatesController: updatesController,
            communitiesController: communitiesController,
          ),
        ),
      );
    },
    // KNOWN LAYOUT BUG, not a test problem: at 320x568 with text scale
    // 2.0 the empty state (EmptyStateCard inside a plain Align, nothing
    // scrollable above it) overflows by 168 pixels on the bottom.
    // Unskip once that empty state can scroll at large text scales.
  );

  // Separate from the sweeps above on purpose: a contrast failure
  // reported as a layout failure helps nobody. Pumped once at one
  // realistic size, then asserted against that rendered tree -- running
  // the guidelines before pumpWidget checks an empty tree and passes
  // trivially.
  //
  // All four guidelines pass here, so this one runs live.
  testWidgets('StarredMessagesScreen meets the accessibility guidelines',
      (tester) async {
    final threads = DemoData.buildChatThreads()
        .map(
          (thread) => thread.copyWith(
            messages: thread.messages
                .map((message) => message.copyWith(isStarred: true))
                .toList(growable: false),
          ),
        )
        .toList(growable: false);

    final chatsController = ChatsController(
      repository: FakeChatRepository(
        initialThreads: threads,
        latency: Duration.zero,
      ),
    );
    await chatsController.loadThreads();
    await chatsController.refreshStarredMessages();
    addTearDown(chatsController.dispose);
    final callsController = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
    );
    addTearDown(callsController.dispose);
    final updatesController = UpdatesController(
      repository: FakeUpdatesRepository(latency: Duration.zero),
    );
    addTearDown(updatesController.dispose);
    final communitiesController = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
    );
    addTearDown(communitiesController.dispose);

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: StarredMessagesScreen(
          chatsController: chatsController,
          callsController: callsController,
          updatesController: updatesController,
          communitiesController: communitiesController,
        ),
      ),
      devices: const [iphoneProProfile],
      variants: const [defaultVariant],
    );
    expect(
      find.byKey(const Key('starred_messages_screen')),
      findsOneWidget,
      reason: 'the guidelines must run against a rendered screen',
    );
    await expectScreenMeetsAccessibilityGuidelines(tester);
  });
}
