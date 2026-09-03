import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/presentation/communities_screen.dart';
import 'package:whatswave/features/shared/widgets/avatar_badge.dart';
import 'package:whatswave/features/shared/widgets/liquid_glass.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

import '../../../support/device_matrix.dart';

void main() {
  testWidgets(
      'the new community row is styled as an action, not as a community row',
      (tester) async {
    final controller = await _pumpCommunitiesScreen(tester);
    final theme = AppTheme.lightTheme();

    final createRow = find.byKey(const Key('communities_create_button'));
    final communityRow =
        find.byKey(Key('community_card_${controller.communities.first.id}'));
    expect(createRow, findsOneWidget);
    expect(communityRow, findsOneWidget);

    // Leading affordance: a glass "+" circle, where a real community row
    // carries its filled AvatarBadge.
    expect(
      find.descendant(of: createRow, matching: find.byType(LiquidGlassSurface)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: createRow, matching: find.byType(AvatarBadge)),
      findsNothing,
    );
    expect(
      find.descendant(of: communityRow, matching: find.byType(AvatarBadge)),
      findsOneWidget,
    );

    // Typography: primary-coloured w700 label vs. the community title's
    // w800 on-surface one, and no second preview line under it.
    final actionLabel = tester.widget<Text>(
      find.descendant(of: createRow, matching: find.text('New community')),
    );
    expect(actionLabel.style?.color, theme.colorScheme.primary);
    expect(actionLabel.style?.fontWeight, FontWeight.w700);

    final communityTitle = tester.widget<Text>(
      find.descendant(
        of: communityRow,
        matching: find.text(controller.communities.first.title),
      ),
    );
    expect(communityTitle.style?.fontWeight, FontWeight.w800);
    expect(communityTitle.style?.color, isNot(theme.colorScheme.primary));

    // Separator: the rule under the action row is full-bleed, unlike the
    // avatar-indented dividers that run between community rows.
    final sectionBreak = tester.widget<Divider>(
      find
          .descendant(
            of: find.byKey(const Key('communities_screen')),
            matching: find.byType(Divider),
          )
          .first,
    );
    expect(sectionBreak.indent ?? 0, 0);

    final rowDivider = tester.widget<Divider>(
      find.descendant(of: communityRow, matching: find.byType(Divider)),
    );
    expect(rowDivider.indent, greaterThan(0));
  });
}

Future<CommunitiesController> _pumpCommunitiesScreen(
  WidgetTester tester,
) async {
  await tester.binding.setSurfaceSize(iphoneProProfile.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final controller = CommunitiesController(
    repository: FakeCommunitiesRepository(latency: Duration.zero),
    permissionService: MemoryAppPermissionService(),
  );

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      home: Scaffold(
        body: CommunitiesScreen(
          controller: controller,
          chatsController: ChatsController(
            repository: FakeChatRepository(latency: Duration.zero),
          ),
          callsController: CallsController(
            repository: FakeCallsRepository(latency: Duration.zero),
            permissionService: MemoryAppPermissionService(),
            durationTickInterval: Duration.zero,
          ),
          updatesController: UpdatesController(
            repository: FakeUpdatesRepository(latency: Duration.zero),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}
