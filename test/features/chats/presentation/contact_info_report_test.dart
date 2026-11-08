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

const String _threadId = 'ava-patel';

Future<({ChatsController chats, FakeChatRepository repository})>
    _pumpContactInfo(WidgetTester tester) async {
  final repository = FakeChatRepository(latency: Duration.zero);
  final chats = ChatsController(
    repository: repository,
    permissionService: MemoryAppPermissionService(),
  );
  final communities = CommunitiesController(
    repository: FakeCommunitiesRepository(latency: Duration.zero),
  );
  await chats.ensureLoaded();
  await communities.loadOverview();

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(),
      home: ContactInfoScreen(
        controller: chats,
        communitiesController: communities,
        callsController: CallsController(
          repository: FakeCallsRepository(latency: Duration.zero),
        ),
        updatesController: UpdatesController(
          repository: FakeUpdatesRepository(latency: Duration.zero),
        ),
        threadId: _threadId,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (chats: chats, repository: repository);
}

void main() {
  testWidgets(
    'reporting files the chosen reason and blocks the contact',
    (tester) async {
      final harness = await _pumpContactInfo(tester);
      expect(
        harness.chats.threadById(_threadId)!.isBlocked,
        isFalse,
        reason: 'the fixture must start unblocked for this test to mean '
            'anything',
      );

      final reportButton = find.byKey(const Key('contact_info_report_button'));
      await tester.scrollUntilVisible(reportButton, 200);
      await tester.tap(reportButton);
      await tester.pumpAndSettle();

      // Deliberately not the first option: picking a non-default reason is
      // what proves the dialog's selection actually reaches the repository.
      await tester.tap(
        find.byKey(const Key('report_reason_Harassment or bullying')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('contact_info_confirm_report_button')),
      );
      await tester.pumpAndSettle();

      expect(harness.repository.reports, hasLength(1));
      expect(harness.repository.reports.single.threadId, _threadId);
      expect(
        harness.repository.reports.single.reason,
        'Harassment or bullying',
      );
      expect(
        harness.chats.threadById(_threadId)!.isBlocked,
        isTrue,
        reason: 'reporting blocks too -- a user who just reported someone '
            'does not expect to keep hearing from them',
      );
    },
  );

  testWidgets('cancelling the report dialog files nothing', (tester) async {
    final harness = await _pumpContactInfo(tester);

    final reportButton = find.byKey(const Key('contact_info_report_button'));
    await tester.scrollUntilVisible(reportButton, 200);
    await tester.tap(reportButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(harness.repository.reports, isEmpty);
    expect(harness.chats.threadById(_threadId)!.isBlocked, isFalse);
  });
}
