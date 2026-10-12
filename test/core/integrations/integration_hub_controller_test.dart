import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/core/config/backend_runtime_config.dart';
import 'package:whatswave/core/integrations/backend_integration_bundle.dart';
import 'package:whatswave/core/integrations/backend_repository_bundle.dart';
import 'package:whatswave/core/integrations/integration_hub_controller.dart';

import '../../support/firebase_core_mocks.dart';

void main() {
  // The firebase-first bundle constructs real Firebase-backed
  // repositories, which resolve their Firebase singletons eagerly.
  setUpAll(installFirebaseCoreMocks);

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('syncs push registration and tracks media uploads on the happy path',
      () async {
    final controller = IntegrationHubController();
    await controller.ensureLoaded();

    await controller.applyRuntimeContext(
      notificationsEnabled: true,
      isAuthenticated: true,
    );
    await controller.recordSyncSuccess(
      source: 'Chats',
      title: 'Message synced',
      details: 'Shipping notes',
    );
    final upload = await controller.queueMediaTransfer(
      source: 'Chats',
      label: 'Photo · Launch board',
      kind: MediaTransferKind.photo,
    );

    expect(controller.pushRegistration.state, PushRegistrationState.registered);
    expect(controller.pushRegistration.tokenPreview, isNotNull);
    expect(controller.recentActivity.first.title, 'Message synced');
    expect(upload.state, MediaTransferState.uploaded);
    expect(controller.uploadedTransferCount, 1);
  });

  test('persists push and media pipeline state across relaunches', () async {
    final firstController = IntegrationHubController();
    await firstController.ensureLoaded();

    await firstController.applyRuntimeContext(
      notificationsEnabled: true,
      isAuthenticated: true,
    );
    firstController.debugFailNextMediaTransfer();
    final failedUpload = await firstController.queueMediaTransfer(
      source: 'Updates',
      label: 'Launch recap.mov',
      kind: MediaTransferKind.statusVideo,
    );
    expect(failedUpload.state, MediaTransferState.failed);

    final secondController = IntegrationHubController();
    await secondController.ensureLoaded();

    expect(
      secondController.pushRegistration.state,
      PushRegistrationState.registered,
    );
    expect(secondController.pushRegistration.tokenPreview, isNotNull);
    expect(secondController.mediaTransfers, isNotEmpty);
    expect(
      secondController.mediaTransfers.first.state,
      MediaTransferState.failed,
    );

    await secondController.retryFailedTransfers();

    expect(secondController.mediaTransfers.first.state,
        MediaTransferState.uploaded);
  });

  test('supports injected provider services without changing controller flows',
      () async {
    final controller = IntegrationHubController(
      pushRegistrationService: const _StubPushRegistrationService(),
      mediaTransferService: const _StubMediaTransferService(),
      providerCatalog: const _StubIntegrationProviderCatalog(),
    );
    await controller.ensureLoaded();

    await controller.applyRuntimeContext(
      notificationsEnabled: true,
      isAuthenticated: true,
    );
    final upload = await controller.queueMediaTransfer(
      source: 'Chats',
      label: 'Investor deck.pdf',
      kind: MediaTransferKind.file,
    );

    expect(controller.pushProviderName, 'Firebase push adapter stub');
    expect(controller.mediaTransferProviderName, 'Firebase storage stub');
    expect(controller.pushRegistration.tokenPreview, 'firebase_stub_token');
    expect(upload.state, MediaTransferState.uploaded);
    expect(
      controller.providerReadiness.first.providerName,
      'Firebase adapter pack',
    );
    expect(
      controller.deliveryTargets,
      <DeliveryTarget>[
        DeliveryTarget.firebaseReady,
        DeliveryTarget.awsCompatible,
      ],
    );
  });

  test('firebase-first push surfaces a failure when FCM is unreachable',
      () async {
    // Firebase-first wires the real FirebaseMessagingPushRegistrationService,
    // which has no platform to talk to in a test, so registration fails.
    // That is the honest expectation here: this test used to assert an
    // `actionRequired` scaffold state gated on the WW_*_READY flags, from
    // back when push was simulated. What is still worth asserting is that
    // the controller *surfaces* the failure instead of swallowing it.
    final config = BackendRuntimeConfig.fromValues(
      backendModeValue: 'firebase',
      environmentValue: 'staging',
    );
    final bundle = const BackendIntegrationBundleFactory().create(
      runtimeConfig: config,
    );
    final controller = IntegrationHubController(
      runtimeConfig: config,
      pushRegistrationService: bundle.pushRegistrationService,
      mediaTransferService: bundle.mediaTransferService,
      providerCatalog: bundle.providerCatalog,
    );
    await controller.ensureLoaded();

    await controller.applyRuntimeContext(
      notificationsEnabled: true,
      isAuthenticated: true,
    );
    final upload = await controller.queueMediaTransfer(
      source: 'Chats',
      label: 'Launch notes.pdf',
      kind: MediaTransferKind.file,
    );

    expect(controller.runtimeConfig.backendMode, BackendMode.firebaseFirst);
    expect(controller.pushProviderName, 'Firebase Cloud Messaging');
    expect(controller.pushRegistration.state, PushRegistrationState.failed);
    expect(controller.failedActivityCount, greaterThan(0));
    expect(controller.recentActivity.first.status, SyncActivityStatus.failed);
    expect(upload.state, MediaTransferState.failed);
  });

  test('firebase-first scaffolding succeeds when setup flags are marked ready',
      () async {
    final config = BackendRuntimeConfig.fromValues(
      backendModeValue: 'firebase',
      environmentValue: 'development',
      callingProviderValue: 'livekit',
      firebaseOptionsGenerated: true,
      iosFirebaseConfigPresent: true,
      androidFirebaseConfigPresent: true,
      firebaseAuthReady: true,
      firestoreReady: true,
      firebaseStorageReady: true,
      fcmReady: true,
      apnsReady: true,
      firebaseProjectId: 'ww-dev',
    );
    final bundle = const BackendIntegrationBundleFactory().create(
      runtimeConfig: config,
    );
    // The push service is injected rather than taken from the bundle: the
    // bundle's firebase-first choice is the real FCM client, which cannot
    // register off-device (covered by the failure test above). What this
    // test is actually about is the controller's success path -- that a
    // registered token reaches `pushRegistration` and is surfaced only as a
    // truncated preview.
    final controller = IntegrationHubController(
      runtimeConfig: config,
      pushRegistrationService: const _RegisteringPushService(),
      mediaTransferService: bundle.mediaTransferService,
      providerCatalog: bundle.providerCatalog,
    );
    await controller.ensureLoaded();

    await controller.applyRuntimeContext(
      notificationsEnabled: true,
      isAuthenticated: true,
    );
    final upload = await controller.queueMediaTransfer(
      source: 'Updates',
      label: 'Launch reel.mov',
      kind: MediaTransferKind.statusVideo,
    );

    expect(controller.mediaTransferProviderName, 'Firebase Storage scaffold');
    expect(controller.pushRegistration.state, PushRegistrationState.registered);
    expect(controller.pushRegistration.tokenPreview, 'tok_abcdefgh');
    expect(upload.state, MediaTransferState.uploaded);
    expect(controller.runtimeConfig.firebaseProjectLabel, 'ww-dev');
  });

  test('exposes runtime-aware repository adapters alongside sync providers',
      () async {
    final config = BackendRuntimeConfig.fromValues(
      backendModeValue: 'firebase',
      environmentValue: 'development',
      useFirebaseEmulators: true,
      firebaseProjectId: 'ww-dev',
    );
    final controller = IntegrationHubController(runtimeConfig: config);
    await controller.ensureLoaded();

    expect(controller.repositoryReadiness, hasLength(5));
    expect(
      controller.repositoryReadiness.first.featureArea,
      'Auth and session',
    );
    expect(
      controller.repositoryReadiness.first.providerName,
      'Firebase Phone Auth',
    );
    expect(
      controller.repositoryReadiness.first.status,
      RepositoryAdapterStatus.liveCloud,
    );
    expect(
      controller.repositoryReadiness[2].capabilities,
      contains('Firebase emulators'),
    );
  });
}

class _StubPushRegistrationService implements PushRegistrationService {
  const _StubPushRegistrationService();

  @override
  DeliveryTarget get target => DeliveryTarget.firebaseReady;

  @override
  String get providerName => 'Firebase push adapter stub';

  @override
  Future<PushRegistrationSyncResult> syncRegistration({
    required PushRegistrationContext context,
    required bool forceFailure,
  }) async {
    return const PushRegistrationSyncResult(
      registration: PushRegistration(
        state: PushRegistrationState.registered,
        tokenPreview: 'firebase_stub_token',
      ),
      activityStatus: SyncActivityStatus.synced,
      activityTitle: 'Stub push synced',
    );
  }
}

class _StubMediaTransferService implements MediaTransferService {
  const _StubMediaTransferService();

  @override
  DeliveryTarget get target => DeliveryTarget.firebaseReady;

  @override
  String get providerName => 'Firebase storage stub';

  @override
  Future<MediaTransferExecution> completeTransfer({
    required MediaTransferJob job,
    required bool forceFailure,
  }) async {
    return const MediaTransferExecution(state: MediaTransferState.uploaded);
  }
}

class _StubIntegrationProviderCatalog implements IntegrationProviderCatalog {
  const _StubIntegrationProviderCatalog();

  @override
  List<IntegrationProviderReadiness> get providers =>
      const <IntegrationProviderReadiness>[
        IntegrationProviderReadiness(
          target: DeliveryTarget.firebaseReady,
          providerName: 'Firebase adapter pack',
          status: IntegrationProviderStatus.scaffolded,
          summary: 'Ready for real FlutterFire bindings.',
        ),
        IntegrationProviderReadiness(
          target: DeliveryTarget.awsCompatible,
          providerName: 'AWS bridge path',
          status: IntegrationProviderStatus.compatible,
          summary: 'Future mixed-provider option.',
        ),
      ];
}

/// Stands in for a push backend that registers successfully, so the
/// controller's success path is coverable without a real FCM platform.
class _RegisteringPushService implements PushRegistrationService {
  const _RegisteringPushService();

  @override
  DeliveryTarget get target => DeliveryTarget.firebaseReady;

  @override
  String get providerName => 'Test push backend';

  @override
  Future<PushRegistrationSyncResult> syncRegistration({
    required PushRegistrationContext context,
    required bool forceFailure,
  }) async {
    return PushRegistrationSyncResult(
      registration: PushRegistration(
        state: PushRegistrationState.registered,
        tokenPreview: 'tok_abcdefgh',
        lastSyncedAt: DateTime.now(),
      ),
      activityStatus: SyncActivityStatus.synced,
      activityTitle: 'Push token registered',
      activityDetails: 'Registered with the test push backend.',
    );
  }
}
