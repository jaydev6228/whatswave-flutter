import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/presentation/forward_message_screen.dart';

import '../../support/device_matrix.dart';

void main() {
  testWidgets('ForwardMessageScreen survives the layout matrix',
      (tester) async {
    final chatsController = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
    );
    await chatsController.loadThreads();
    addTearDown(chatsController.dispose);

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: ForwardMessageScreen(controller: chatsController),
      ),
    );
  });

  // Separate from the sweep above on purpose: a tap-target failure
  // reported as a layout failure helps nobody. Pumped once at one
  // realistic size, then asserted against that rendered tree -- running
  // the guidelines before pumpWidget checks an empty tree and passes
  // trivially.
  testWidgets(
    'ForwardMessageScreen meets the accessibility guidelines',
    (tester) async {
      final chatsController = ChatsController(
        repository: FakeChatRepository(latency: Duration.zero),
      );
      await chatsController.loadThreads();
      addTearDown(chatsController.dispose);

      await expectScreenSurvivesLayoutMatrix(
        tester,
        build: () => MaterialApp(
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          home: ForwardMessageScreen(controller: chatsController),
        ),
        devices: const [iphoneProProfile],
        variants: const [defaultVariant],
      );
      expect(
        find.byKey(const Key('forward_message_screen')),
        findsOneWidget,
        reason: 'the guidelines must run against a rendered screen',
      );
      await expectScreenMeetsAccessibilityGuidelines(tester);
    },
    // All four guidelines pass. This was skipped on the shared
    // SearchField measuring 361x42 against the 48x48 minimum; that
    // field's vertical padding is now 12, so it is 48.
  );
}
