import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/presentation/new_group_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/contact_access_status.dart';

import '../../support/device_matrix.dart';

void main() {
  testWidgets('NewGroupScreen survives the layout matrix', (tester) async {
    final chats = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
    );
    await chats.ensureLoaded();

    final communities = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );
    await communities.ensureLoaded();
    // Member rows only exist if there are contacts to list; an empty picker
    // would make the sweep vacuous.
    expect(communities.onWhatsWaveContacts, isNotEmpty);

    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: NewGroupScreen(
          communitiesController: communities,
          chatsController: chats,
        ),
      ),
    );
  });

  testWidgets('NewGroupScreen meets accessibility guidelines', (tester) async {
    final chats = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
    );
    await chats.ensureLoaded();

    final communities = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );
    await communities.ensureLoaded();
    expect(communities.onWhatsWaveContacts, isNotEmpty);

    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: NewGroupScreen(
          communitiesController: communities,
          chatsController: chats,
        ),
      ),
    );
    await pumpForAsyncUi(tester);
    expect(find.byType(NewGroupScreen), findsOneWidget);

    await expectScreenMeetsAccessibilityGuidelines(tester);
    // All four guidelines pass. This was skipped on the shared
    // SearchField measuring 361x42 against the 48x48 minimum; that
    // field's vertical padding is now 12, so it is 48.
  });
}
