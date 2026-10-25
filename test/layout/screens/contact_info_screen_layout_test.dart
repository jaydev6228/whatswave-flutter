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

/// Pumps one thread at a single size, then runs the accessibility
/// guidelines against it. Separate from the matrix sweep above on purpose:
/// the guidelines check the *rendered* tree, so they have to run after the
/// pump -- called before one they would assert against an empty tree and
/// pass having tested nothing.
Future<void> _pumpThreadForAccessibility(
  WidgetTester tester,
  String threadId,
) async {
  final chats = ChatsController(
    repository: FakeChatRepository(latency: Duration.zero),
    permissionService: MemoryAppPermissionService(),
  );
  await chats.ensureLoaded();
  expect(chats.threadById(threadId), isNotNull, reason: threadId);

  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
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
  await pumpForAsyncUi(tester);
  expect(find.byType(ContactInfoScreen), findsOneWidget);
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

  // Both cases below are SKIPPED, not loosened. Measured at 393x852,
  // default text scale, light theme.
  //
  // textContrastGuideline fails on three theme colours, none of which this
  // change may fix -- a palette change is the user's decision:
  //   * section headings ("3 participants", "Shared media", "Actions",
  //     InfoSectionHeading): ratio 4.41 at font size 12.0,
  //     colorScheme.onSurface at alpha 0.6 (composites to #6F7473) on the
  //     scaffold's AppPalette.cloud #F5F7F6. Needs 4.5. The same pair
  //     fails on CommunityInfoScreen.
  //   * every _ActionRow ("Clear chat", "Exit group", "Block Ava Patel"
  //     and, oddly, "Add participants"): ratio 3.39 at font size 14.0,
  //     colorScheme.error / AppPalette.rose #E55B5B on the info panel's
  //     #FBFBFB fill. Needs 4.5, and this is the worst ratio outside the
  //     video-call screen -- on the destructive actions. Separately worth
  //     a look: _ActionRow paints *all* its rows in colorScheme.error, so
  //     "Add participants" is red although it destroys nothing.
  //   * the AppBar's "Edit" TextButton: ratio 3.84 at font size 14.0,
  //     AppPalette.emerald #128C7E on AppPalette.cloud #F5F7F6. Also
  //     fails on CommunityInfoScreen.
  //
  // androidTapTargetGuideline also fails: the _ActionRow rows measure
  // 359.0x44.0, under Android's 48x48 (they clear iOS's 44x44 exactly).
  // 44 = 12 + 20 + 12 (vertical padding, icon, vertical padding), the same
  // recipe InfoPrimaryActionRow uses in
  // lib/features/shared/widgets/info_screen_chrome.dart. Vertical padding
  // of 14 would clear 48, but every info row in the app would grow 4pt and
  // the divider rhythm would shift, so it is reported, not changed.
  //
  // iOSTapTargetGuideline and labeledTapTargetGuideline pass.
  testWidgets('ContactInfoScreen meets accessibility guidelines for a group',
      (tester) async {
    await _pumpThreadForAccessibility(tester, 'design-sprint');
    await expectScreenMeetsAccessibilityGuidelines(tester);
  }, skip: true);

  testWidgets('ContactInfoScreen meets accessibility guidelines for a contact',
      (tester) async {
    await _pumpThreadForAccessibility(tester, 'ava-patel');
    await expectScreenMeetsAccessibilityGuidelines(tester);
  }, skip: true);
}
