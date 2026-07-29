enum BackendMode {
  localSeeded,
  firebaseFirst,
  awsCompatible,
}

extension BackendModeCopy on BackendMode {
  String get label {
    return switch (this) {
      BackendMode.localSeeded => 'Local seeded',
      BackendMode.firebaseFirst => 'Firebase first',
      BackendMode.awsCompatible => 'AWS ready',
    };
  }

  String get description {
    return switch (this) {
      BackendMode.localSeeded =>
        'Runs fully against seeded local repositories and simulators.',
      BackendMode.firebaseFirst =>
        'Prepares the app for FlutterFire-backed auth, data, media, and push.',
      BackendMode.awsCompatible =>
        'Keeps the app portable for an AWS or mixed-provider backend path.',
    };
  }
}

enum BackendEnvironment {
  local,
  development,
  staging,
  production,
}

extension BackendEnvironmentCopy on BackendEnvironment {
  String get label {
    return switch (this) {
      BackendEnvironment.local => 'Local',
      BackendEnvironment.development => 'Development',
      BackendEnvironment.staging => 'Staging',
      BackendEnvironment.production => 'Production',
    };
  }
}

enum CallingProvider {
  simulated,
  liveKit,
  twilio,
  agora,
  stream,
  selfManaged,
}

extension CallingProviderCopy on CallingProvider {
  String get label {
    return switch (this) {
      CallingProvider.simulated => 'Simulated',
      CallingProvider.liveKit => 'LiveKit',
      CallingProvider.twilio => 'Twilio',
      CallingProvider.agora => 'Agora',
      CallingProvider.stream => 'Stream',
      CallingProvider.selfManaged => 'Self-managed',
    };
  }

  bool get isProductionReady => this != CallingProvider.simulated;
}

class BackendChecklistItem {
  const BackendChecklistItem({
    required this.title,
    required this.description,
    required this.isComplete,
  });

  final String title;
  final String description;
  final bool isComplete;
}

class BackendRuntimeConfig {
  const BackendRuntimeConfig({
    required this.backendMode,
    required this.environment,
    required this.callingProvider,
    required this.useFirebaseEmulators,
    required this.firebaseOptionsGenerated,
    required this.iosFirebaseConfigPresent,
    required this.androidFirebaseConfigPresent,
    required this.firebaseAuthReady,
    required this.firestoreReady,
    required this.firebaseStorageReady,
    required this.fcmReady,
    required this.apnsReady,
    required this.analyticsEnabled,
    required this.crashReportingEnabled,
    this.firebaseProjectId,
  });

  factory BackendRuntimeConfig.fromEnvironment() {
    return BackendRuntimeConfig.fromValues(
      backendModeValue: const String.fromEnvironment(
        'WW_BACKEND_TARGET',
        defaultValue: 'local',
      ),
      environmentValue: const String.fromEnvironment(
        'WW_APP_ENV',
        defaultValue: 'local',
      ),
      callingProviderValue: const String.fromEnvironment(
        'WW_CALL_PROVIDER',
        defaultValue: 'simulated',
      ),
      useFirebaseEmulators: bool.fromEnvironment(
        'WW_USE_FIREBASE_EMULATORS',
      ),
      firebaseOptionsGenerated: bool.fromEnvironment(
        'WW_FIREBASE_OPTIONS_READY',
      ),
      iosFirebaseConfigPresent: bool.fromEnvironment(
        'WW_IOS_FIREBASE_CONFIG_READY',
      ),
      androidFirebaseConfigPresent: bool.fromEnvironment(
        'WW_ANDROID_FIREBASE_CONFIG_READY',
      ),
      firebaseAuthReady: bool.fromEnvironment(
        'WW_FIREBASE_AUTH_READY',
      ),
      firestoreReady: bool.fromEnvironment(
        'WW_FIRESTORE_READY',
      ),
      firebaseStorageReady: bool.fromEnvironment(
        'WW_FIREBASE_STORAGE_READY',
      ),
      fcmReady: bool.fromEnvironment(
        'WW_FCM_READY',
      ),
      apnsReady: bool.fromEnvironment(
        'WW_APNS_READY',
      ),
      analyticsEnabled: bool.fromEnvironment(
        'WW_ANALYTICS_ENABLED',
      ),
      crashReportingEnabled: bool.fromEnvironment(
        'WW_CRASH_REPORTING_ENABLED',
      ),
      firebaseProjectId: const String.fromEnvironment(
        'WW_FIREBASE_PROJECT_ID',
        defaultValue: '',
      ),
    );
  }

  factory BackendRuntimeConfig.fromValues({
    String backendModeValue = 'local',
    String environmentValue = 'local',
    String callingProviderValue = 'simulated',
    bool useFirebaseEmulators = false,
    bool firebaseOptionsGenerated = false,
    bool iosFirebaseConfigPresent = false,
    bool androidFirebaseConfigPresent = false,
    bool firebaseAuthReady = false,
    bool firestoreReady = false,
    bool firebaseStorageReady = false,
    bool fcmReady = false,
    bool apnsReady = false,
    bool analyticsEnabled = false,
    bool crashReportingEnabled = false,
    String? firebaseProjectId,
  }) {
    return BackendRuntimeConfig(
      backendMode: _backendModeFromValue(backendModeValue),
      environment: _environmentFromValue(environmentValue),
      callingProvider: _callingProviderFromValue(callingProviderValue),
      useFirebaseEmulators: useFirebaseEmulators,
      firebaseOptionsGenerated: firebaseOptionsGenerated,
      iosFirebaseConfigPresent: iosFirebaseConfigPresent,
      androidFirebaseConfigPresent: androidFirebaseConfigPresent,
      firebaseAuthReady: firebaseAuthReady,
      firestoreReady: firestoreReady,
      firebaseStorageReady: firebaseStorageReady,
      fcmReady: fcmReady,
      apnsReady: apnsReady,
      analyticsEnabled: analyticsEnabled,
      crashReportingEnabled: crashReportingEnabled,
      firebaseProjectId: firebaseProjectId?.trim().isEmpty == true
          ? null
          : firebaseProjectId?.trim(),
    );
  }

  final BackendMode backendMode;
  final BackendEnvironment environment;
  final CallingProvider callingProvider;
  final bool useFirebaseEmulators;
  final bool firebaseOptionsGenerated;
  final bool iosFirebaseConfigPresent;
  final bool androidFirebaseConfigPresent;
  final bool firebaseAuthReady;
  final bool firestoreReady;
  final bool firebaseStorageReady;
  final bool fcmReady;
  final bool apnsReady;
  final bool analyticsEnabled;
  final bool crashReportingEnabled;
  final String? firebaseProjectId;

  bool get prefersFirebase => backendMode == BackendMode.firebaseFirst;
  bool get prefersAws => backendMode == BackendMode.awsCompatible;
  bool get usesSimulatedCalling => callingProvider == CallingProvider.simulated;
  bool get hasFirebaseNativeConfig =>
      iosFirebaseConfigPresent && androidFirebaseConfigPresent;
  bool get hasFirebaseCoreScaffold =>
      firebaseOptionsGenerated && hasFirebaseNativeConfig;
  bool get hasFirebaseDataScaffold =>
      hasFirebaseCoreScaffold && firebaseAuthReady && firestoreReady;
  bool get hasFirebasePushScaffold =>
      hasFirebaseCoreScaffold && fcmReady && apnsReady;
  bool get hasFirebaseMediaScaffold =>
      hasFirebaseCoreScaffold && firebaseStorageReady;

  String get firebaseProjectLabel =>
      firebaseProjectId?.trim().isNotEmpty == true
          ? firebaseProjectId!.trim()
          : 'Not set';

  List<BackendChecklistItem> get firebaseChecklist => <BackendChecklistItem>[
        BackendChecklistItem(
          title: 'FlutterFire options',
          description: firebaseOptionsGenerated
              ? '`firebase_options.dart` is ready for this app.'
              : 'Run `flutterfire configure` and commit `firebase_options.dart`.',
          isComplete: firebaseOptionsGenerated,
        ),
        BackendChecklistItem(
          title: 'Native config files',
          description: hasFirebaseNativeConfig
              ? 'iOS and Android Firebase config files are marked ready.'
              : 'Add `GoogleService-Info.plist` and `google-services.json` for each environment.',
          isComplete: hasFirebaseNativeConfig,
        ),
        BackendChecklistItem(
          title: 'Auth and Firestore',
          description: hasFirebaseDataScaffold
              ? 'Firebase Auth and Firestore are marked ready for live adapter binding.'
              : 'Enable Firebase Auth and Firestore, then wire the live repositories.',
          isComplete: hasFirebaseDataScaffold,
        ),
        BackendChecklistItem(
          title: 'Storage pipeline',
          description: hasFirebaseMediaScaffold
              ? 'Cloud Storage is marked ready for media uploads.'
              : 'Enable Cloud Storage and point uploads to the correct bucket rules.',
          isComplete: hasFirebaseMediaScaffold,
        ),
        BackendChecklistItem(
          title: 'Push delivery',
          description: hasFirebasePushScaffold
              ? 'FCM and APNs handoff are marked ready for push registration.'
              : 'Finish FCM plus APNs setup before expecting live push or call invites.',
          isComplete: hasFirebasePushScaffold,
        ),
      ];

  List<BackendChecklistItem> get releaseChecklist => <BackendChecklistItem>[
        BackendChecklistItem(
          title: 'Crash reporting',
          description: crashReportingEnabled
              ? 'A production crash provider is enabled for this build.'
              : 'Enable Crashlytics, Sentry, Datadog, or another crash provider before release.',
          isComplete: crashReportingEnabled,
        ),
        BackendChecklistItem(
          title: 'Analytics',
          description: analyticsEnabled
              ? 'Analytics events are enabled for this build.'
              : 'Enable analytics only after privacy and consent flows are ready.',
          isComplete: analyticsEnabled,
        ),
        BackendChecklistItem(
          title: 'Call transport',
          description: callingProvider.isProductionReady
              ? '${callingProvider.label} is selected for real calling.'
              : 'The app still uses simulated calling. Pick LiveKit, Twilio, Agora, Stream, or a self-managed stack.',
          isComplete: callingProvider.isProductionReady,
        ),
      ];

  List<String> get firebaseMissingSteps => firebaseChecklist
      .where((item) => !item.isComplete)
      .map((item) => item.description)
      .toList(growable: false);

  List<String> get releaseMissingSteps => releaseChecklist
      .where((item) => !item.isComplete)
      .map((item) => item.description)
      .toList(growable: false);

  static BackendMode _backendModeFromValue(String value) {
    switch (value.trim().toLowerCase()) {
      case 'firebase':
      case 'firebase-first':
      case 'firebase_first':
        return BackendMode.firebaseFirst;
      case 'aws':
      case 'aws-ready':
      case 'aws_ready':
        return BackendMode.awsCompatible;
      default:
        return BackendMode.localSeeded;
    }
  }

  static BackendEnvironment _environmentFromValue(String value) {
    switch (value.trim().toLowerCase()) {
      case 'dev':
      case 'development':
        return BackendEnvironment.development;
      case 'staging':
        return BackendEnvironment.staging;
      case 'prod':
      case 'production':
        return BackendEnvironment.production;
      default:
        return BackendEnvironment.local;
    }
  }

  static CallingProvider _callingProviderFromValue(String value) {
    switch (value.trim().toLowerCase()) {
      case 'livekit':
        return CallingProvider.liveKit;
      case 'twilio':
        return CallingProvider.twilio;
      case 'agora':
        return CallingProvider.agora;
      case 'stream':
        return CallingProvider.stream;
      case 'self-managed':
      case 'self_managed':
      case 'selfmanaged':
        return CallingProvider.selfManaged;
      default:
        return CallingProvider.simulated;
    }
  }
}
