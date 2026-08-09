import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/core/config/backend_runtime_config.dart';
import 'package:whatswave/core/integrations/backend_integration_bundle.dart';
import 'package:whatswave/core/integrations/integration_hub_controller.dart';
import 'package:whatswave/core/integrations/tracked_repositories.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';
import 'package:whatswave/features/updates/data/status_media_store.dart';

/// Regression coverage for a real production bug: TrackedChatRepository and
/// TrackedUpdatesRepository used to run a *simulated* media-transfer check
/// (queueMediaTransfer, gated on the manually-maintained
/// WW_FIREBASE_STORAGE_READY dart-define) BEFORE attempting the real send,
/// and threw if that simulated check reported "failed" -- silently blocking
/// every real photo/video/document/voice-note/location send whenever that
/// flag was stale, regardless of whether the real backend actually worked.
/// These tests pin a runtime config where the flag is deliberately false
/// (the exact failure mode reported) and assert the real send still
/// succeeds -- the tracker must observe, never gate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  IntegrationHubController buildControllerWithStaleStorageFlag() {
    final staleConfig = BackendRuntimeConfig.fromValues(
      backendModeValue: 'firebase',
      firebaseOptionsGenerated: true,
      iosFirebaseConfigPresent: true,
      androidFirebaseConfigPresent: true,
      firebaseAuthReady: true,
      firestoreReady: true,
      firebaseStorageReady: false, // the exact stale-flag scenario
    );
    return IntegrationHubController(
      runtimeConfig: staleConfig,
      mediaTransferService: FirebaseScaffoldMediaTransferService(staleConfig),
    );
  }

  test(
      'sending a chat attachment still succeeds even when the media-transfer '
      'tracker reports not-ready', () async {
    final integrations = buildControllerWithStaleStorageFlag();
    await integrations.ensureLoaded();

    final fakeChatRepository = FakeChatRepository(latency: Duration.zero);
    final repository = TrackedChatRepository(
      delegate: fakeChatRepository,
      integrations: integrations,
    );

    final existingThreads = await fakeChatRepository.fetchThreads();
    final threads = await repository.sendAttachmentMessage(
      threadId: existingThreads.first.id,
      attachments: [
        const ChatAttachment(
          id: 'a1',
          type: ChatAttachmentType.photo,
          title: 'Photo',
          details: '',
          tintColor: AppPalette.green,
        ),
      ],
    );

    expect(threads, isNotEmpty);
  });

  test(
      'posting a photo status still succeeds even when the media-transfer '
      'tracker reports not-ready', () async {
    final integrations = buildControllerWithStaleStorageFlag();
    await integrations.ensureLoaded();

    final repository = TrackedUpdatesRepository(
      delegate: FakeUpdatesRepository(
        latency: Duration.zero,
        // Bypasses the real file-copy (path_provider isn't mocked in this
        // test, and isn't what this test is about) -- only the tracking
        // gate above it is under test here.
        mediaStore: const _PassthroughStatusMediaStore(),
      ),
      integrations: integrations,
    );

    final stories = await repository.createStatus(
      type: StatusStoryType.photo,
      caption: 'Launch day',
      localMediaPath: 'asset://media/status_demo/launch_cafe.jpg',
    );

    expect(stories, isNotEmpty);
  });
}

class _PassthroughStatusMediaStore implements StatusMediaStore {
  const _PassthroughStatusMediaStore();

  @override
  Future<String> importMedia(
    String sourcePath, {
    required StatusStoryType type,
  }) async =>
      sourcePath;

  @override
  Future<void> deleteMedia(Iterable<String> mediaPaths) async {}
}
