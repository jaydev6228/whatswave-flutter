import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/calls/presentation/calls_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/contact_access_status.dart';

import '../../support/device_matrix.dart';

/// Accessibility coverage for the Calls tab. Behavioural layout coverage
/// already lives in test/features/calls/presentation/calls_screen_test.dart;
/// this adds the screen-reader side of it.
void main() {
  testWidgets('CallsScreen meets accessibility guidelines', (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
    );
    final communities = CommunitiesController(
      repository: FakeCommunitiesRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(
        contactsStatus: ContactAccessStatus.granted,
      ),
    );
    await communities.ensureLoaded();

    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: Scaffold(
          body: CallsScreen(
            controller: controller,
            communitiesController: communities,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Proof the guidelines below ran against a rendered call list rather
    // than an empty tree, which would pass every one of them.
    expect(find.byType(CallsScreen), findsOneWidget);
    expect(controller.history, isNotEmpty);

    await expectScreenMeetsAccessibilityGuidelines(tester);
    // All four guidelines pass. This was skipped on the shared
    // SearchField measuring 361x42 against the 48x48 minimum; that
    // field's vertical padding is now 12, so it is 48.
  });
}
