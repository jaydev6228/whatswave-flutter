import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/auth/application/auth_controller.dart';
import 'package:whatswave/features/auth/data/fake_auth_repository.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/presentation/chats_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

import '../../support/device_matrix.dart';

/// Accessibility coverage for the Chats tab.
///
/// The tab already has behavioural layout coverage in
/// test/features/chats/presentation/chats_screen_test.dart; what it had none
/// of was an assertion that a screen reader can actually drive it. The
/// screen is built directly (same shape as that file's `_pumpChatsScreen`)
/// rather than through the app shell, so the failure points at this tab and
/// not at the navigation chrome around it.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Nothing answers the clipboard channel in a widget test, and the chat
    // list's long-press menu reaches for it; without a handler the call
    // never returns.
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(
            SystemChannels.platform, (call) async => null);
  });

  testWidgets('ChatsScreen meets accessibility guidelines', (tester) async {
    final controller = ChatsController(
      repository: FakeChatRepository(latency: Duration.zero),
    );

    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: Scaffold(
          body: ChatsScreen(
            controller: controller,
            callsController: CallsController(
              repository: FakeCallsRepository(latency: Duration.zero),
            ),
            communitiesController: CommunitiesController(
              repository: FakeCommunitiesRepository(latency: Duration.zero),
            ),
            updatesController: UpdatesController(
              repository: FakeUpdatesRepository(latency: Duration.zero),
            ),
            authController: AuthController(
              repository: FakeAuthRepository(latency: Duration.zero),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The guidelines run against whatever is currently pumped, so they would
    // pass trivially against an empty tree. This is the proof there is a
    // rendered chat list under them.
    expect(find.byType(ChatsScreen), findsOneWidget);
    expect(find.byKey(const Key('chat_tile_ava-patel')), findsOneWidget);

    await expectScreenMeetsAccessibilityGuidelines(tester);
    // All four guidelines pass. Two tappable rows used to sit under both
    // platform minimums and both are now 48pt tall: the shared
    // SearchField capsule (was 361x42, vertical padding now 12) and the
    // archived-chats row (was 361x36, vertical padding now 12).
    // labeledTapTargetGuideline passes because the 22x22 "+" status badge
    // (chats_status_add_button) announces as "Add status".
  });
}
