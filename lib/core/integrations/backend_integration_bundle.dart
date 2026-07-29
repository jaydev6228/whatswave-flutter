import '../config/backend_runtime_config.dart';
import 'integration_hub_controller.dart';

class BackendIntegrationBundle {
  const BackendIntegrationBundle({
    required this.pushRegistrationService,
    required this.mediaTransferService,
    required this.providerCatalog,
  });

  final PushRegistrationService pushRegistrationService;
  final MediaTransferService mediaTransferService;
  final IntegrationProviderCatalog providerCatalog;
}

class BackendIntegrationBundleFactory {
  const BackendIntegrationBundleFactory();

  BackendIntegrationBundle create({
    required BackendRuntimeConfig runtimeConfig,
  }) {
    switch (runtimeConfig.backendMode) {
      case BackendMode.firebaseFirst:
        return BackendIntegrationBundle(
          pushRegistrationService:
              FirebaseScaffoldPushRegistrationService(runtimeConfig),
          mediaTransferService:
              FirebaseScaffoldMediaTransferService(runtimeConfig),
          providerCatalog:
              RuntimeAwareIntegrationProviderCatalog(runtimeConfig),
        );
      case BackendMode.awsCompatible:
        return BackendIntegrationBundle(
          pushRegistrationService: AwsScaffoldPushRegistrationService(
            runtimeConfig,
          ),
          mediaTransferService: AwsScaffoldMediaTransferService(runtimeConfig),
          providerCatalog:
              RuntimeAwareIntegrationProviderCatalog(runtimeConfig),
        );
      case BackendMode.localSeeded:
        return BackendIntegrationBundle(
          pushRegistrationService: const LocalPushRegistrationService(),
          mediaTransferService: const LocalMediaTransferService(),
          providerCatalog:
              RuntimeAwareIntegrationProviderCatalog(runtimeConfig),
        );
    }
  }
}

class FirebaseScaffoldPushRegistrationService
    implements PushRegistrationService {
  const FirebaseScaffoldPushRegistrationService(this.runtimeConfig);

  final BackendRuntimeConfig runtimeConfig;

  @override
  DeliveryTarget get target => DeliveryTarget.firebaseReady;

  @override
  String get providerName => runtimeConfig.useFirebaseEmulators
      ? 'Firebase push scaffold (emulators)'
      : 'Firebase push scaffold';

  @override
  Future<PushRegistrationSyncResult> syncRegistration({
    required PushRegistrationContext context,
    required bool forceFailure,
  }) async {
    if (!context.notificationsEnabled) {
      return PushRegistrationSyncResult(
        registration: PushRegistration(
          state: PushRegistrationState.paused,
          lastSyncedAt: DateTime.now(),
        ),
        activityStatus: SyncActivityStatus.synced,
        activityTitle: 'Firebase push paused',
        activityDetails: 'Notifications are disabled on this device.',
      );
    }

    if (!context.isAuthenticated) {
      return const PushRegistrationSyncResult(
        registration: PushRegistration(
          state: PushRegistrationState.actionRequired,
        ),
      );
    }

    if (forceFailure) {
      return const PushRegistrationSyncResult(
        registration: PushRegistration(
          state: PushRegistrationState.failed,
        ),
        activityStatus: SyncActivityStatus.failed,
        activityTitle: 'Firebase push sync failed',
        activityDetails:
            'Check FCM, APNs, and your server token registration flow.',
        errorMessage: 'Firebase push scaffolding reported a sync failure.',
      );
    }

    if (!runtimeConfig.hasFirebasePushScaffold) {
      final detail = runtimeConfig.firebaseMissingSteps.isNotEmpty
          ? runtimeConfig.firebaseMissingSteps.first
          : 'Complete the Firebase messaging setup before syncing live device tokens.';
      return PushRegistrationSyncResult(
        registration: const PushRegistration(
          state: PushRegistrationState.actionRequired,
        ),
        activityStatus: SyncActivityStatus.failed,
        activityTitle: 'Firebase push setup incomplete',
        activityDetails: detail,
        errorMessage:
            'Complete the Firebase messaging setup before syncing live device tokens.',
      );
    }

    final tokenPrefix =
        runtimeConfig.useFirebaseEmulators ? 'fcm_emu' : 'fcm_scaffold';
    final tokenPreview =
        '${tokenPrefix}_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    return PushRegistrationSyncResult(
      registration: PushRegistration(
        state: PushRegistrationState.registered,
        tokenPreview: tokenPreview,
        lastSyncedAt: DateTime.now(),
      ),
      activityStatus: SyncActivityStatus.synced,
      activityTitle: 'Firebase push token prepared',
      activityDetails:
          'FCM scaffold is ready to hand this token to your backend delivery path.',
    );
  }
}

class FirebaseScaffoldMediaTransferService implements MediaTransferService {
  const FirebaseScaffoldMediaTransferService(this.runtimeConfig);

  final BackendRuntimeConfig runtimeConfig;

  @override
  DeliveryTarget get target => DeliveryTarget.firebaseReady;

  @override
  String get providerName => runtimeConfig.useFirebaseEmulators
      ? 'Firebase Storage scaffold (emulators)'
      : 'Firebase Storage scaffold';

  @override
  Future<MediaTransferExecution> completeTransfer({
    required MediaTransferJob job,
    required bool forceFailure,
  }) async {
    if (forceFailure || !runtimeConfig.hasFirebaseMediaScaffold) {
      return const MediaTransferExecution(state: MediaTransferState.failed);
    }

    return const MediaTransferExecution(state: MediaTransferState.uploaded);
  }
}

class AwsScaffoldPushRegistrationService implements PushRegistrationService {
  const AwsScaffoldPushRegistrationService(this.runtimeConfig);

  final BackendRuntimeConfig runtimeConfig;

  @override
  DeliveryTarget get target => DeliveryTarget.awsCompatible;

  @override
  String get providerName =>
      'AWS push bridge scaffold (${runtimeConfig.environment.label})';

  @override
  Future<PushRegistrationSyncResult> syncRegistration({
    required PushRegistrationContext context,
    required bool forceFailure,
  }) async {
    if (!context.notificationsEnabled) {
      return PushRegistrationSyncResult(
        registration: PushRegistration(
          state: PushRegistrationState.paused,
          lastSyncedAt: DateTime.now(),
        ),
        activityStatus: SyncActivityStatus.synced,
        activityTitle: 'AWS push paused',
        activityDetails: 'Notifications are disabled on this device.',
      );
    }

    if (!context.isAuthenticated) {
      return const PushRegistrationSyncResult(
        registration: PushRegistration(
          state: PushRegistrationState.actionRequired,
        ),
      );
    }

    final detail = forceFailure
        ? 'Check SNS, Pinpoint, or your custom push fanout service for the ${runtimeConfig.environment.label.toLowerCase()} environment.'
        : 'Define the AWS push delivery path before syncing live device tokens for the ${runtimeConfig.environment.label.toLowerCase()} environment.';
    return PushRegistrationSyncResult(
      registration: PushRegistration(
        state: forceFailure
            ? PushRegistrationState.failed
            : PushRegistrationState.actionRequired,
      ),
      activityStatus: SyncActivityStatus.failed,
      activityTitle: forceFailure
          ? 'AWS push scaffold failed'
          : 'AWS push setup incomplete',
      activityDetails: detail,
      errorMessage: detail,
    );
  }
}

class AwsScaffoldMediaTransferService implements MediaTransferService {
  const AwsScaffoldMediaTransferService(this.runtimeConfig);

  final BackendRuntimeConfig runtimeConfig;

  @override
  DeliveryTarget get target => DeliveryTarget.awsCompatible;

  @override
  String get providerName =>
      'S3 media scaffold (${runtimeConfig.environment.label})';

  @override
  Future<MediaTransferExecution> completeTransfer({
    required MediaTransferJob job,
    required bool forceFailure,
  }) async {
    return MediaTransferExecution(
      state:
          forceFailure ? MediaTransferState.failed : MediaTransferState.failed,
    );
  }
}

class RuntimeAwareIntegrationProviderCatalog
    implements IntegrationProviderCatalog {
  const RuntimeAwareIntegrationProviderCatalog(this.runtimeConfig);

  final BackendRuntimeConfig runtimeConfig;

  @override
  List<IntegrationProviderReadiness> get providers =>
      <IntegrationProviderReadiness>[
        IntegrationProviderReadiness(
          target: DeliveryTarget.localSeeded,
          providerName: 'Seeded local repositories',
          status: IntegrationProviderStatus.active,
          summary: runtimeConfig.backendMode == BackendMode.localSeeded
              ? 'The app is currently running fully against seeded local repositories and simulator-backed services.'
              : 'Seeded repositories remain available as a safe local fallback while production adapters are scaffolded.',
          capabilities: const <String>[
            'Persisted local session',
            'Seeded chat and status data',
            'Non-blocking integration tracking',
          ],
          nextSteps: const <String>[
            'Keep this fallback path available for UI work while live services are wired in.',
          ],
        ),
        IntegrationProviderReadiness(
          target: DeliveryTarget.firebaseReady,
          providerName: 'FlutterFire adapters',
          status: IntegrationProviderStatus.scaffolded,
          summary: runtimeConfig.prefersFirebase
              ? 'This build is targeting Firebase-first delivery and is waiting on the remaining live setup steps.'
              : 'Firebase-first seams are ready without leaking Firebase SDK assumptions into presentation code.',
          capabilities: <String>[
            'Runtime env: ${runtimeConfig.environment.label}',
            if (runtimeConfig.useFirebaseEmulators) 'Firebase emulators',
            if (runtimeConfig.firebaseProjectId != null)
              'Project: ${runtimeConfig.firebaseProjectId}',
            'Push token contract',
            'Media upload contract',
          ],
          nextSteps: runtimeConfig.firebaseMissingSteps.isNotEmpty
              ? runtimeConfig.firebaseMissingSteps
              : <String>[
                  'Bind Firebase Auth, Firestore, Storage, and FCM to the live repository implementations.',
                ],
        ),
        IntegrationProviderReadiness(
          target: DeliveryTarget.awsCompatible,
          providerName: 'AWS or mixed-provider path',
          status: IntegrationProviderStatus.compatible,
          summary:
              'The current repository and service boundaries stay portable for Cognito, Lambda/API, DynamoDB/Aurora, S3, and custom moderation services later.',
          capabilities: <String>[
            'Portable repository interfaces',
            'Provider-isolated push delivery',
            'Provider-isolated media pipeline',
            'Call provider swap path',
          ],
          nextSteps: <String>[
            'Choose Cognito or a custom auth broker.',
            'Define the API, push fanout, media upload, and moderation services.',
          ],
        ),
      ];
}
