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
import 'package:whatswave/features/shared/widgets/status_motion.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

/// Group info's Edit -> Cancel/Done swap, and the read-only name -> text
/// field swap underneath it, used to happen in a single frame. These pin the
/// transition itself, not just its end state: a mid-flight frame has to show
/// both sides alive, which is only true if something is animating between
/// them.
Future<void> _pumpGroupInfo(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  final chats = ChatsController(
    repository: FakeChatRepository(latency: Duration.zero),
    permissionService: MemoryAppPermissionService(),
  );
  await chats.ensureLoaded();

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
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
        // Sample data's admin-owned group (lib/core/sample/demo_data.dart).
        threadId: 'design-sprint',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'the app bar cross-fades Edit into Cancel/Done instead of '
      'swapping it in one frame', (tester) async {
    await _pumpGroupInfo(tester);
    expect(find.byKey(const Key('contact_info_edit_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('contact_info_edit_button')));
    // One frame to start the transition, then stop halfway through it.
    await tester.pump();
    await tester.pump(kStatusMotionDuration ~/ 2);

    // Both action sets alive at once is the proof the swap is animated --
    // an instant swap has the outgoing button gone by the frame after the
    // tap.
    expect(find.byKey(const Key('contact_info_edit_button')), findsOneWidget);
    expect(find.byKey(const Key('contact_info_save_button')), findsOneWidget);

    // ...and the transition still ends where it should.
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contact_info_edit_button')), findsNothing);
    expect(find.byKey(const Key('contact_info_save_button')), findsOneWidget);
  });

  testWidgets('the name cross-fades into its text field', (tester) async {
    await _pumpGroupInfo(tester);
    expect(find.byKey(const Key('rename_group_field')), findsNothing);

    await tester.tap(find.byKey(const Key('contact_info_edit_button')));
    await tester.pump();
    await tester.pump(kStatusMotionDuration ~/ 2);

    // Two, not one: the read-only name and the field it becomes are on
    // screen together. find.text matches the field's own editable text too,
    // so the count is what distinguishes a cross-fade from a swap -- an
    // instant swap leaves only the field's copy.
    expect(find.byKey(const Key('rename_group_field')), findsOneWidget);
    expect(find.text('Design Sprint'), findsNWidgets(2));

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rename_group_field')), findsOneWidget);
    expect(find.text('Design Sprint'), findsOneWidget);
  });

  testWidgets(
      'leaving edit mode does not dispose a field that is still '
      'fading out', (tester) async {
    await _pumpGroupInfo(tester);

    await tester.tap(find.byKey(const Key('contact_info_edit_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact_info_cancel_edit_button')));

    // The fields outlive edit mode by a full transition. Disposing their
    // controllers in _cancelGroupEdit threw "A TextEditingController was
    // used after being disposed" on the very next frame.
    await tester.pump();
    await tester.pump(kStatusMotionDuration ~/ 2);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rename_group_field')), findsNothing);
  });

  testWidgets('reduced motion skips the cross-fade entirely', (tester) async {
    await _pumpGroupInfo(tester, disableAnimations: true);

    await tester.tap(find.byKey(const Key('contact_info_edit_button')));
    await tester.pump();

    // No lingering outgoing chrome at all: with animations disabled the
    // swap has to be the instant one it used to be everywhere.
    expect(find.byKey(const Key('contact_info_edit_button')), findsNothing);
    expect(find.byKey(const Key('contact_info_save_button')), findsOneWidget);
    expect(find.byKey(const Key('rename_group_field')), findsOneWidget);
  });
}
