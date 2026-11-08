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

  // Both cases below pass all four guidelines. Four things had to change,
  // measured at 393x852, default text scale, light theme:
  //   * section headings were onSurface at alpha 0.6 -- 4.41 at font size
  //     12.0 on cloud, under WCAG's 4.5. They are alpha 0.66 now, and
  //     this screen uses the shared InfoSectionHeading rather than the
  //     byte-identical private copy it used to carry.
  //   * every _ActionRow drew colorScheme.error on the panel's #FBFBFB
  //     fill: 3.39 at font size 14.0 while that was rose #E55B5B. The
  //     light scheme uses roseDeep #CC3B3B now, 4.77 on that fill.
  //   * _ActionRow measured 359x44 against Android's 48x48. Its vertical
  //     padding is 14, so the rows are 48.
  //   * the AppBar's "Edit" TextButton draws colorScheme.primary on
  //     cloud: 3.84 while emerald was #128C7E, 5.38 at #0E7268.
  //
  // Still open, and not a guideline failure: _ActionRow paints *all* its
  // rows in colorScheme.error, so "Add participants" is red although it
  // destroys nothing.
  testWidgets('ContactInfoScreen meets accessibility guidelines for a group',
      (tester) async {
    await _pumpThreadForAccessibility(tester, 'design-sprint');
    await expectScreenMeetsAccessibilityGuidelines(tester);
  });

  testWidgets('ContactInfoScreen meets accessibility guidelines for a contact',
      (tester) async {
    await _pumpThreadForAccessibility(tester, 'ava-patel');
    await expectScreenMeetsAccessibilityGuidelines(tester);
  });

  // The report dialog is the tallest transient surface this screen opens:
  // an explanation plus five radio rows, which at a 2.0 text scale on a
  // 320pt phone is well past the viewport. Swept with the screen rather
  // than in its own file because it only exists as a child of this one.
  testWidgets('the report dialog survives the layout matrix', (tester) async {
    final chats = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
    );
    await chats.ensureLoaded();

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
          threadId: 'ava-patel',
        ),
      ),
      afterPump: (tester) async {
        final reportButton =
            find.byKey(const Key('contact_info_report_button'));
        // .first is the page's own CustomScrollView: some sizes render a
        // second, inner Scrollable, and the default finder demands exactly
        // one.
        await tester.scrollUntilVisible(
          reportButton,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        // scrollUntilVisible stops as soon as the row exists; at a large
        // text scale it can stop with the row still under the app bar,
        // and the tap then lands on nothing.
        await tester.ensureVisible(reportButton);
        await tester.pumpAndSettle();
        await tester.tap(reportButton);
        await tester.pumpAndSettle();
        // Without this the sweep could pass having never opened anything.
        expect(
          find.byKey(const Key('contact_info_confirm_report_button')),
          findsOneWidget,
        );
        // Close it before the next combination. pumpWidget updates the
        // existing element tree rather than replacing it, so the Navigator
        // -- and anything pushed onto it -- survives into the next size,
        // where the tap would land on this stale dialog instead.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );
  });
}
