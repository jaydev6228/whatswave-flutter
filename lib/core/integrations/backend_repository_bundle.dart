import '../../core/config/backend_runtime_config.dart';
import '../../core/sample/demo_data.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/data/fake_auth_repository.dart';
import '../../features/auth/data/firebase_auth_repository.dart';
import '../../features/calls/data/calls_repository.dart';
import '../../features/calls/data/fake_calls_repository.dart';
import '../../features/chats/data/chat_repository.dart';
import '../../features/chats/data/fake_chat_repository.dart';
import '../../features/chats/data/firestore_chat_repository.dart';
import '../../features/communities/data/communities_repository.dart';
import '../../features/communities/data/fake_communities_repository.dart';
import '../../features/updates/data/fake_updates_repository.dart';
import '../../features/updates/data/firestore_updates_repository.dart';
import '../../features/updates/data/updates_repository.dart';

enum RepositoryAdapterStatus {
  localActive,
  localFallback,
  liveCloud,
}

extension RepositoryAdapterStatusCopy on RepositoryAdapterStatus {
  String get label {
    return switch (this) {
      RepositoryAdapterStatus.localActive => 'Local active',
      RepositoryAdapterStatus.localFallback => 'Local fallback',
      RepositoryAdapterStatus.liveCloud => 'Live cloud',
    };
  }
}

class RepositoryAdapterReadiness {
  const RepositoryAdapterReadiness({
    required this.featureArea,
    required this.providerName,
    required this.status,
    required this.summary,
    this.capabilities = const <String>[],
    this.nextSteps = const <String>[],
  });

  final String featureArea;
  final String providerName;
  final RepositoryAdapterStatus status;
  final String summary;
  final List<String> capabilities;
  final List<String> nextSteps;
}

abstract class RepositoryAdapterCatalog {
  const RepositoryAdapterCatalog();

  List<RepositoryAdapterReadiness> get adapters;
}

class RuntimeAwareRepositoryAdapterCatalog implements RepositoryAdapterCatalog {
  const RuntimeAwareRepositoryAdapterCatalog(this.runtimeConfig);

  final BackendRuntimeConfig runtimeConfig;

  @override
  List<RepositoryAdapterReadiness> get adapters {
    switch (runtimeConfig.backendMode) {
      case BackendMode.firebaseFirst:
        return _firebaseAdapters();
      case BackendMode.awsCompatible:
        return _awsAdapters();
      case BackendMode.localSeeded:
        return _localAdapters();
    }
  }

  List<RepositoryAdapterReadiness> _localAdapters() {
    return const <RepositoryAdapterReadiness>[
      RepositoryAdapterReadiness(
        featureArea: 'Auth and session',
        providerName: 'Seeded auth repository',
        status: RepositoryAdapterStatus.localActive,
        summary:
            'Phone entry, OTP simulation, profile bootstrap, and session restore all run locally with persisted seeded state.',
        capabilities: <String>[
          'Persistent local session',
          'OTP happy and sad paths',
          'Profile persistence',
        ],
        nextSteps: <String>[
          'Swap this boundary for Firebase Auth or a custom auth broker when live credentials are ready.',
        ],
      ),
      RepositoryAdapterReadiness(
        featureArea: 'Chats and messages',
        providerName: 'Seeded chat repository',
        status: RepositoryAdapterStatus.localActive,
        summary:
            'Threads, message sends, attachments, archive state, and read markers are served from seeded local data.',
        capabilities: <String>[
          'Seeded chat threads',
          'Attachment composition',
          'Local message persistence',
        ],
        nextSteps: <String>[
          'Replace this with a cloud-backed thread and message repository when the backend path is live.',
        ],
      ),
      RepositoryAdapterReadiness(
        featureArea: 'Updates and channels',
        providerName: 'Seeded updates repository',
        status: RepositoryAdapterStatus.localActive,
        summary:
            'Status stories, viewed state, and channel previews are currently driven by local seeded updates data.',
        capabilities: <String>[
          'Story progress state',
          'Viewed and unviewed splits',
          'Local status creation',
        ],
        nextSteps: <String>[
          'Connect stories, channels, and media metadata to live repositories once the storage path is ready.',
        ],
      ),
      RepositoryAdapterReadiness(
        featureArea: 'Communities and contacts',
        providerName: 'Seeded communities repository',
        status: RepositoryAdapterStatus.localActive,
        summary:
            'Communities, contacts, invite state, and discovery flows are running against seeded local records.',
        capabilities: <String>[
          'Community creation',
          'Invite state transitions',
          'Search and filters',
        ],
        nextSteps: <String>[
          'Map communities, contacts, and invite flows onto the live data layer after the API shape is finalized.',
        ],
      ),
      RepositoryAdapterReadiness(
        featureArea: 'Calls and recents',
        providerName: 'Seeded calls repository',
        status: RepositoryAdapterStatus.localActive,
        summary:
            'Favorites, recent calls, and simulated call history writes stay local so active call UI work remains fast and safe.',
        capabilities: <String>[
          'Favorites and recents',
          'Simulated history writes',
          'Offline-safe local fallback',
        ],
        nextSteps: <String>[
          'Move call recents and signaling metadata to the production backend after a real calling provider is selected.',
        ],
      ),
    ];
  }

  List<RepositoryAdapterReadiness> _firebaseAdapters() {
    final environment = runtimeConfig.environment.label;
    final emulatorCapability = runtimeConfig.useFirebaseEmulators
        ? const <String>['Firebase emulators']
        : const <String>[];
    final projectCapability = runtimeConfig.firebaseProjectId != null
        ? <String>['Project: ${runtimeConfig.firebaseProjectId}']
        : const <String>[];
    return <RepositoryAdapterReadiness>[
      RepositoryAdapterReadiness(
        featureArea: 'Auth and session',
        providerName: 'Firebase Auth scaffold',
        status: RepositoryAdapterStatus.localFallback,
        summary:
            'Auth flows are still backed by the persistent local fallback while the Firebase phone auth adapter is being wired for the $environment environment.',
        capabilities: <String>[
          'Local fallback session',
          ...emulatorCapability,
          ...projectCapability,
          if (runtimeConfig.firebaseAuthReady) 'Firebase Auth ready',
        ],
        nextSteps: <String>[
          ..._firebaseCoreSteps(),
          if (!runtimeConfig.firebaseAuthReady)
            'Enable Firebase Auth phone sign-in before replacing the seeded OTP path.',
          'Bind session restore and profile bootstrap to the live Firebase auth boundary.',
        ],
      ),
      RepositoryAdapterReadiness(
        featureArea: 'Chats and messages',
        providerName: 'Firestore chat scaffold',
        status: RepositoryAdapterStatus.localFallback,
        summary:
            'Chat lists, message sends, and thread state still come from seeded local data while Firestore collections and indexes are prepared.',
        capabilities: <String>[
          'Local fallback threads',
          ...emulatorCapability,
          ...projectCapability,
          if (runtimeConfig.firestoreReady) 'Firestore ready',
        ],
        nextSteps: <String>[
          ..._firebaseCoreSteps(),
          if (!runtimeConfig.firestoreReady)
            'Enable Firestore collections, indexes, and security rules for messages and threads.',
          'Bind thread fetch, send, read state, and archive actions to Firestore-backed repositories.',
        ],
      ),
      RepositoryAdapterReadiness(
        featureArea: 'Updates and channels',
        providerName: 'Firestore and Storage updates scaffold',
        status: RepositoryAdapterStatus.localFallback,
        summary:
            'Stories, channels, and status creation are still local while Firestore metadata and Cloud Storage uploads are scaffolded.',
        capabilities: <String>[
          'Local fallback stories',
          ...emulatorCapability,
          ...projectCapability,
          if (runtimeConfig.firestoreReady) 'Firestore ready',
          if (runtimeConfig.firebaseStorageReady) 'Cloud Storage ready',
        ],
        nextSteps: <String>[
          ..._firebaseCoreSteps(),
          if (!runtimeConfig.firestoreReady)
            'Prepare Firestore collections for story metadata and channel previews.',
          if (!runtimeConfig.firebaseStorageReady)
            'Enable Cloud Storage and bucket rules for status media uploads.',
          'Bind status creation, viewed state, and channel discovery to live repositories.',
        ],
      ),
      RepositoryAdapterReadiness(
        featureArea: 'Communities and contacts',
        providerName: 'Firestore communities scaffold',
        status: RepositoryAdapterStatus.localFallback,
        summary:
            'Community hubs, invite state, and contacts search remain local until the shared Firestore community model is finalized.',
        capabilities: <String>[
          'Local fallback communities',
          ...emulatorCapability,
          ...projectCapability,
          if (runtimeConfig.firestoreReady) 'Firestore ready',
        ],
        nextSteps: <String>[
          ..._firebaseCoreSteps(),
          if (!runtimeConfig.firestoreReady)
            'Finalize Firestore collections and access rules for communities, contacts, and invites.',
          'Bind community creation, invite, and discovery flows to the live data layer.',
        ],
      ),
      RepositoryAdapterReadiness(
        featureArea: 'Calls and recents',
        providerName: runtimeConfig.callingProvider.isProductionReady
            ? '${runtimeConfig.callingProvider.label} call scaffold'
            : 'Calling scaffold',
        status: RepositoryAdapterStatus.localFallback,
        summary:
            'Recent calls and active-call state are still written locally while push signaling and the real calling stack are selected.',
        capabilities: <String>[
          'Local fallback recents',
          if (runtimeConfig.hasFirebasePushScaffold) 'Push scaffold ready',
          'Call provider: ${runtimeConfig.callingProvider.label}',
        ],
        nextSteps: <String>[
          if (!runtimeConfig.hasFirebasePushScaffold)
            'Finish FCM and APNs setup before expecting real incoming call delivery.',
          if (!runtimeConfig.callingProvider.isProductionReady)
            'Pick LiveKit, Twilio, Agora, Stream, or a self-managed stack for production calling.',
          'Move call invites, call history, and signaling metadata onto the live provider path.',
        ],
      ),
    ];
  }

  List<RepositoryAdapterReadiness> _awsAdapters() {
    final environment = runtimeConfig.environment.label;
    return <RepositoryAdapterReadiness>[
      RepositoryAdapterReadiness(
        featureArea: 'Auth and session',
        providerName: 'AWS auth scaffold',
        status: RepositoryAdapterStatus.localFallback,
        summary:
            'The auth boundary is still using persistent local fallback data while Cognito or a custom auth broker is defined for $environment.',
        capabilities: const <String>[
          'Local fallback session',
          'Provider-neutral auth contract',
        ],
        nextSteps: const <String>[
          'Choose Cognito or a custom auth broker for phone verification and session restore.',
          'Map the current auth contract onto the selected AWS or mixed-provider service.',
        ],
      ),
      RepositoryAdapterReadiness(
        featureArea: 'Chats and messages',
        providerName: 'AWS data scaffold',
        status: RepositoryAdapterStatus.localFallback,
        summary:
            'Threads and messages stay on seeded local data while the AWS data model, APIs, and moderation path are planned.',
        capabilities: const <String>[
          'Local fallback threads',
          'Portable repository contract',
        ],
        nextSteps: const <String>[
          'Define the API layer for thread and message reads and writes.',
          'Choose DynamoDB, Aurora, or another store plus the required moderation pipeline.',
        ],
      ),
      RepositoryAdapterReadiness(
        featureArea: 'Updates and channels',
        providerName: 'AWS media scaffold',
        status: RepositoryAdapterStatus.localFallback,
        summary:
            'Status and channel surfaces are still local while the S3, CDN, and metadata strategy is prepared.',
        capabilities: const <String>[
          'Local fallback stories',
          'Portable media abstraction',
        ],
        nextSteps: const <String>[
          'Define the S3 upload, CDN delivery, and metadata sync strategy.',
          'Bind status creation and story reads to the live repository path.',
        ],
      ),
      RepositoryAdapterReadiness(
        featureArea: 'Communities and contacts',
        providerName: 'AWS communities scaffold',
        status: RepositoryAdapterStatus.localFallback,
        summary:
            'Community creation, contact discovery, and invite flows remain local until the API shape and permission model are locked.',
        capabilities: const <String>[
          'Local fallback communities',
          'Portable invite contract',
        ],
        nextSteps: const <String>[
          'Define the communities and contacts API surface.',
          'Add moderation, abuse controls, and rate limiting before public rollout.',
        ],
      ),
      RepositoryAdapterReadiness(
        featureArea: 'Calls and recents',
        providerName: runtimeConfig.callingProvider.isProductionReady
            ? '${runtimeConfig.callingProvider.label} AWS bridge'
            : 'AWS call scaffold',
        status: RepositoryAdapterStatus.localFallback,
        summary:
            'Call history and call-state metadata stay local while the signaling, push fanout, and real media transport are designed.',
        capabilities: <String>[
          'Local fallback recents',
          'Call provider: ${runtimeConfig.callingProvider.label}',
        ],
        nextSteps: <String>[
          'Pick the signaling and calling stack before moving recents and invites to AWS.',
          'Define push fanout, presence, abuse controls, and recording policy if required.',
        ],
      ),
    ];
  }

  List<String> _firebaseCoreSteps() {
    return <String>[
      if (!runtimeConfig.firebaseOptionsGenerated)
        'Run flutterfire configure and commit firebase_options.dart.',
      if (!runtimeConfig.hasFirebaseNativeConfig)
        'Add GoogleService-Info.plist and google-services.json for this environment.',
    ];
  }
}

class BackendRepositoryBundle {
  const BackendRepositoryBundle({
    required this.authRepository,
    required this.callsRepository,
    required this.chatRepository,
    required this.communitiesRepository,
    required this.updatesRepository,
    required this.repositoryCatalog,
  });

  final AuthRepository authRepository;
  final CallsRepository callsRepository;
  final ChatRepository chatRepository;
  final CommunitiesRepository communitiesRepository;
  final UpdatesRepository updatesRepository;
  final RepositoryAdapterCatalog repositoryCatalog;
}

class BackendRepositoryBundleFactory {
  const BackendRepositoryBundleFactory();

  BackendRepositoryBundle create({
    required BackendRuntimeConfig runtimeConfig,
    required bool enableDemoRestoreSession,
  }) {
    return BackendRepositoryBundle(
      authRepository:
          _buildAuthRepository(runtimeConfig, enableDemoRestoreSession),
      callsRepository: _buildCallsRepository(enableDemoRestoreSession),
      chatRepository:
          _buildChatRepository(runtimeConfig, enableDemoRestoreSession),
      communitiesRepository:
          _buildCommunitiesRepository(enableDemoRestoreSession),
      updatesRepository:
          _buildUpdatesRepository(runtimeConfig, enableDemoRestoreSession),
      repositoryCatalog: RuntimeAwareRepositoryAdapterCatalog(runtimeConfig),
    );
  }

  AuthRepository _buildAuthRepository(
    BackendRuntimeConfig runtimeConfig,
    bool enableDemoRestoreSession,
  ) {
    if (runtimeConfig.backendMode == BackendMode.firebaseFirst) {
      return FirebaseAuthRepository();
    }

    if (enableDemoRestoreSession) {
      return FakeAuthRepository(
        restoredUser: DemoData.currentUser,
        latency: Duration.zero,
        persistSession: true,
      );
    }

    return FakeAuthRepository(persistSession: true);
  }

  CallsRepository _buildCallsRepository(bool enableDemoRestoreSession) {
    return enableDemoRestoreSession
        ? FakeCallsRepository(latency: Duration.zero)
        : FakeCallsRepository();
  }

  ChatRepository _buildChatRepository(
    BackendRuntimeConfig runtimeConfig,
    bool enableDemoRestoreSession,
  ) {
    if (runtimeConfig.backendMode == BackendMode.firebaseFirst) {
      return FirestoreChatRepository();
    }

    return enableDemoRestoreSession
        ? FakeChatRepository(latency: Duration.zero)
        : FakeChatRepository();
  }

  CommunitiesRepository _buildCommunitiesRepository(
    bool enableDemoRestoreSession,
  ) {
    return enableDemoRestoreSession
        ? FakeCommunitiesRepository(latency: Duration.zero)
        : FakeCommunitiesRepository();
  }

  UpdatesRepository _buildUpdatesRepository(
    BackendRuntimeConfig runtimeConfig,
    bool enableDemoRestoreSession,
  ) {
    if (runtimeConfig.backendMode == BackendMode.firebaseFirst) {
      return FirestoreUpdatesRepository();
    }

    return enableDemoRestoreSession
        ? FakeUpdatesRepository(
            latency: Duration.zero,
            persistStories: true,
          )
        : FakeUpdatesRepository(persistStories: true);
  }
}
