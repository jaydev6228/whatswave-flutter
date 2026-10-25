// Flow 2 of docs/test_strategy.md, "Layer 4": airplane mode, send, relaunch
// -- the failed send AND its retry button survived.
//
// **Backend: local seeded.** `FakeChatRepository`, the repository
// `WW_BACKEND_TARGET=local` builds, subclassed so one send fails. The
// durable half -- `PendingSendStore` -- runs on the real sqflite plugin
// under the real Keychain/Keystore key, which is the part no widget test
// reaches (`test/` runs sqflite through `sqflite_common_ffi` and secure
// storage through `setMockInitialValues`).
//
// **Airplane mode is NOT really on.** `integration_test` cannot toggle the
// radio; a human or CI does that with `adb`/`simctl` before the run, which
// is what docs/test_strategy.md already says about native dialogs. What is
// simulated is a repository that reports the send as failed, which is what
// `ChatsController.sendTextMessage` turns into `didSend == false` and what
// the UI branches on.
//
// So this does NOT cover: the radio actually being off. That matters,
// because in the firebase build Firestore has offline persistence -- with no
// network, `set()` is queued locally and its future may simply never
// complete rather than failing, so the real airplane-mode path may produce a
// *pending* bubble, not a failed one. Driving a real radio-off send is a
// genuine gap and needs a run with the radio off against the firebase
// backend.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/crypto/crypto_box.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/chat_repository.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/data/pending_send_store.dart';
import 'package:whatswave/features/chats/domain/chat_message.dart';
import 'package:whatswave/features/chats/domain/chat_thread.dart';
import 'package:whatswave/features/chats/domain/message_reply_preview.dart';
import 'package:whatswave/features/chats/domain/story_reply_context.dart';
import 'package:whatswave/features/chats/presentation/conversation_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

import 'support/device_storage.dart';

/// A seeded repository with the radio off: every text send fails the way
/// `ChatsController` sees an offline send.
class _OfflineChatRepository extends FakeChatRepository {
  _OfflineChatRepository() : super(latency: Duration.zero);

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
    StoryReplyContext? storyReplyContext,
    MessageReplyPreview? replyPreview,
    String? messageId,
  }) async {
    throw const ChatRepositoryException('No connection.');
  }
}

/// The thread the seeded backend ships, used by every other chat test.
const String _threadId = 'ava-patel';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a failed send and its retry button survive a relaunch',
      (tester) async {
    final root = await freshInstallDirectory('flow2_pending');
    final path = p.join(root, 'pending.db');
    const draft = 'sent while offline';

    // --- before the quit -------------------------------------------------
    var database = await PendingSendStore.open(path: path);
    var store = PendingSendStore(database: database, cryptoBox: CryptoBox());

    var controller = await _openConversation(tester, pendingSends: store);
    await tester.enterText(
      find.byKey(const Key('conversation_composer_field')),
      draft,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation_send_button')));
    await tester.pumpAndSettle();

    expect(find.text(draft), findsOneWidget);
    expect(find.text('Not sent'), findsOneWidget);

    // `_rememberFailedSend` is fire-and-forget, so wait for the row rather
    // than assuming the write landed inside the pump.
    final remembered = await _pendingEventually(store);
    expect(remembered.single.text, draft);
    expect(remembered.single.deliveryState, MessageDeliveryState.failed);

    // "Force-quit": the widget tree, the controller and the database handle
    // all go away. Same limitation as flow 1 -- integration_test cannot kill
    // the host process, so this is a clean teardown, NOT an OS kill
    // mid-write and NOT a reboot.
    //
    // The empty tree is load-bearing, not tidiness: pumping another
    // ConversationScreen straight over this one would reuse the same State
    // (same type, same position, no key), so its `_localMessages` would
    // carry the failed bubble over in memory and the relaunch below would
    // prove nothing. Unmounting first is what forces the restore to come
    // from disk -- verified by emptying the store before the relaunch and
    // watching the assertions fail.
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await database.close();

    // --- the relaunch ----------------------------------------------------
    // Fresh CryptoBox: the payload can only be opened by fetching the key
    // back out of the real keystore.
    database = await PendingSendStore.open(path: path);
    store = PendingSendStore(database: database, cryptoBox: CryptoBox());
    controller = await _openConversation(tester, pendingSends: store);

    expect(find.text(draft), findsOneWidget);
    expect(find.text('Not sent'), findsOneWidget);

    // The button being on screen is not the claim -- it renders for any
    // failed bubble. The claim is that it still *works*, which needs the
    // restored message to be in the screen's local-message list (see
    // `onRetryTap` in conversation_screen.dart).
    final retry = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Retry'),
    );
    expect(retry.onPressed, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await database.close();
  });

  testWidgets('a send that succeeds leaves no pending record behind',
      (tester) async {
    // Without this the flow above would also pass if the store simply kept
    // every send forever.
    final root = await freshInstallDirectory('flow2_cleared');
    final database = await PendingSendStore.open(
      path: p.join(root, 'pending.db'),
    );
    final store = PendingSendStore(database: database, cryptoBox: CryptoBox());

    final controller = await _openConversation(
      tester,
      pendingSends: store,
      repository: FakeChatRepository(latency: Duration.zero),
    );
    await tester.enterText(
      find.byKey(const Key('conversation_composer_field')),
      'back online',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation_send_button')));
    await tester.pumpAndSettle();

    expect(find.text('Not sent'), findsNothing);
    expect(await store.forThread(_threadId), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await database.close();
  });
}

/// Opens the real conversation screen on the seeded thread.
Future<ChatsController> _openConversation(
  WidgetTester tester, {
  required PendingSendStore pendingSends,
  FakeChatRepository? repository,
}) async {
  final controller = ChatsController(
    repository: repository ?? _OfflineChatRepository(),
    permissionService: MemoryAppPermissionService(),
    pendingSends: pendingSends,
  );
  await controller.loadThreads();

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      home: ConversationScreen(
        controller: controller,
        threadId: _threadId,
        callsController: CallsController(
          repository: FakeCallsRepository(latency: Duration.zero),
        ),
        updatesController: UpdatesController(
          repository: FakeUpdatesRepository(latency: Duration.zero),
        ),
        communitiesController: CommunitiesController(
          repository: FakeCommunitiesRepository(latency: Duration.zero),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

/// Polls for the fire-and-forget pending write. Real time, because the
/// integration binding runs on the real clock.
Future<List<ChatMessage>> _pendingEventually(PendingSendStore store) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    final pending = await store.forThread(_threadId);
    if (pending.isNotEmpty) {
      return pending;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return store.forThread(_threadId);
}
