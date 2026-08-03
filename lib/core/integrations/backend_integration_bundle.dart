import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

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
          pushRegistrationService: FirebaseMessagingPushRegistrationService(),
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

/// Real Firebase Cloud Messaging implementation of [PushRegistrationService].
///
/// Requests notification permission, fetches a real FCM token, and writes
/// it to `pushTokens/{uid}` in Firestore so a future server-side component
/// (a Cloud Function, once Blaze is available) can actually send pushes to
/// this device -- this class only registers the token, it doesn't send or
/// receive pushes itself.
///
/// Known limitation, not fixable client-side: iOS Simulators cannot obtain
/// a real APNs device token -- that requires real hardware talking to
/// Apple's push servers. On iOS, [getAPNSToken] is checked first and, if
/// null (always true on Simulator), this returns `actionRequired` with a
/// message explaining why, rather than crashing or silently failing.
/// Testing a real token requires a physical iOS device or the Android
/// emulator (which has no equivalent restriction).
class FirebaseMessagingPushRegistrationService
    implements PushRegistrationService {
  FirebaseMessagingPushRegistrationService({
    FirebaseMessaging? messaging,
    fb_auth.FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseMessaging _messaging;
  final fb_auth.FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  @override
  DeliveryTarget get target => DeliveryTarget.firebaseReady;

  @override
  String get providerName => 'Firebase Cloud Messaging';

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
        errorMessage: 'Firebase push sync reported a failure.',
      );
    }

    try {
      final settings = await _messaging.requestPermission();
      final authorized = settings.authorizationStatus ==
              AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!authorized) {
        return const PushRegistrationSyncResult(
          registration: PushRegistration(
            state: PushRegistrationState.actionRequired,
          ),
          activityStatus: SyncActivityStatus.failed,
          activityTitle: 'Notification permission not granted',
          activityDetails:
              'Allow notifications for this app in system settings, then sync again.',
        );
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken == null) {
          return const PushRegistrationSyncResult(
            registration: PushRegistration(
              state: PushRegistrationState.actionRequired,
            ),
            activityStatus: SyncActivityStatus.failed,
            activityTitle: 'No APNs token available',
            activityDetails:
                'iOS Simulators cannot obtain a real APNs token -- this needs a physical iOS device to register for real push delivery.',
          );
        }
      }

      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        return const PushRegistrationSyncResult(
          registration: PushRegistration(
            state: PushRegistrationState.failed,
          ),
          activityStatus: SyncActivityStatus.failed,
          activityTitle: 'Firebase push sync failed',
          activityDetails: 'FCM did not return a device token.',
          errorMessage: 'FCM did not return a device token.',
        );
      }

      final uid = _firebaseAuth.currentUser?.uid;
      if (uid != null) {
        await _firestore.collection('pushTokens').doc(uid).set({
          'token': token,
          'platform': defaultTargetPlatform.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      final tokenPreview =
          token.length > 12 ? '${token.substring(0, 12)}...' : token;
      return PushRegistrationSyncResult(
        registration: PushRegistration(
          state: PushRegistrationState.registered,
          tokenPreview: tokenPreview,
          lastSyncedAt: DateTime.now(),
        ),
        activityStatus: SyncActivityStatus.synced,
        activityTitle: 'Firebase push token registered',
        activityDetails:
            'Real FCM token synced to Firestore, ready for a server-side sender.',
      );
    } catch (e) {
      return PushRegistrationSyncResult(
        registration: const PushRegistration(
          state: PushRegistrationState.failed,
        ),
        activityStatus: SyncActivityStatus.failed,
        activityTitle: 'Firebase push sync failed',
        activityDetails: e.toString(),
        errorMessage: 'We could not sync this device token right now.',
      );
    }
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
