import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/backend_runtime_config.dart';
import 'backend_repository_bundle.dart';

enum DeliveryTarget {
  localSeeded,
  firebaseReady,
  awsCompatible,
}

extension DeliveryTargetCopy on DeliveryTarget {
  String get label {
    return switch (this) {
      DeliveryTarget.localSeeded => 'Local active',
      DeliveryTarget.firebaseReady => 'Firebase next',
      DeliveryTarget.awsCompatible => 'AWS ready',
    };
  }

  String get description {
    return switch (this) {
      DeliveryTarget.localSeeded =>
        'The app is currently running against local seeded repositories.',
      DeliveryTarget.firebaseReady =>
        'Repository seams are being prepared for FlutterFire adapters and token sync.',
      DeliveryTarget.awsCompatible =>
        'The data and media boundaries stay portable for future AWS-backed services.',
    };
  }
}

enum IntegrationProviderStatus {
  active,
  scaffolded,
  compatible,
}

extension IntegrationProviderStatusCopy on IntegrationProviderStatus {
  String get label {
    return switch (this) {
      IntegrationProviderStatus.active => 'Active',
      IntegrationProviderStatus.scaffolded => 'Scaffolded',
      IntegrationProviderStatus.compatible => 'Compatible',
    };
  }
}

class IntegrationProviderReadiness {
  const IntegrationProviderReadiness({
    required this.target,
    required this.providerName,
    required this.status,
    required this.summary,
    this.capabilities = const <String>[],
    this.nextSteps = const <String>[],
  });

  final DeliveryTarget target;
  final String providerName;
  final IntegrationProviderStatus status;
  final String summary;
  final List<String> capabilities;
  final List<String> nextSteps;
}

enum PushRegistrationState {
  registered,
  paused,
  actionRequired,
  failed,
}

extension PushRegistrationStateCopy on PushRegistrationState {
  String get label {
    return switch (this) {
      PushRegistrationState.registered => 'Registered',
      PushRegistrationState.paused => 'Paused',
      PushRegistrationState.actionRequired => 'Action required',
      PushRegistrationState.failed => 'Failed',
    };
  }

  String get description {
    return switch (this) {
      PushRegistrationState.registered =>
        'APNs/FCM registration is synced for this device context.',
      PushRegistrationState.paused =>
        'Push delivery is paused because notifications are disabled on this device.',
      PushRegistrationState.actionRequired =>
        'Sign in and keep notifications enabled before syncing device tokens.',
      PushRegistrationState.failed =>
        'The last token sync did not complete. Retry after checking connectivity and setup.',
    };
  }
}

enum SyncActivityStatus {
  synced,
  failed,
}

extension SyncActivityStatusCopy on SyncActivityStatus {
  String get label {
    return switch (this) {
      SyncActivityStatus.synced => 'Synced',
      SyncActivityStatus.failed => 'Failed',
    };
  }
}

enum MediaTransferKind {
  photo,
  video,
  file,
  location,
  voiceNote,
  statusPhoto,
  statusVideo,
}

extension MediaTransferKindCopy on MediaTransferKind {
  String get label {
    return switch (this) {
      MediaTransferKind.photo => 'Photo',
      MediaTransferKind.video => 'Video',
      MediaTransferKind.file => 'File',
      MediaTransferKind.location => 'Location',
      MediaTransferKind.voiceNote => 'Voice note',
      MediaTransferKind.statusPhoto => 'Status photo',
      MediaTransferKind.statusVideo => 'Status video',
    };
  }
}

enum MediaTransferState {
  queued,
  uploading,
  uploaded,
  failed,
}

extension MediaTransferStateCopy on MediaTransferState {
  String get label {
    return switch (this) {
      MediaTransferState.queued => 'Queued',
      MediaTransferState.uploading => 'Uploading',
      MediaTransferState.uploaded => 'Uploaded',
      MediaTransferState.failed => 'Failed',
    };
  }
}

class PushRegistration {
  const PushRegistration({
    this.state = PushRegistrationState.actionRequired,
    this.tokenPreview,
    this.lastSyncedAt,
  });

  final PushRegistrationState state;
  final String? tokenPreview;
  final DateTime? lastSyncedAt;

  bool get isRegistered => state == PushRegistrationState.registered;

  PushRegistration copyWith({
    PushRegistrationState? state,
    String? tokenPreview,
    bool clearTokenPreview = false,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
  }) {
    return PushRegistration(
      state: state ?? this.state,
      tokenPreview:
          clearTokenPreview ? null : (tokenPreview ?? this.tokenPreview),
      lastSyncedAt:
          clearLastSyncedAt ? null : (lastSyncedAt ?? this.lastSyncedAt),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'state': state.name,
      'tokenPreview': tokenPreview,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    };
  }

  static PushRegistration fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return const PushRegistration();
    }

    final stateName = value['state'];
    final tokenPreview = value['tokenPreview'];
    final lastSyncedAt = value['lastSyncedAt'];
    return PushRegistration(
      state: PushRegistrationState.values.firstWhere(
        (candidate) => candidate.name == stateName,
        orElse: () => PushRegistrationState.actionRequired,
      ),
      tokenPreview: tokenPreview is String && tokenPreview.isNotEmpty
          ? tokenPreview
          : null,
      lastSyncedAt: lastSyncedAt is String && lastSyncedAt.isNotEmpty
          ? DateTime.tryParse(lastSyncedAt)
          : null,
    );
  }
}

class SyncActivityEntry {
  const SyncActivityEntry({
    required this.id,
    required this.source,
    required this.title,
    required this.status,
    required this.createdAt,
    this.details,
  });

  final String id;
  final String source;
  final String title;
  final String? details;
  final SyncActivityStatus status;
  final DateTime createdAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'source': source,
      'title': title,
      'details': details,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static SyncActivityEntry? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }

    final id = value['id'];
    final source = value['source'];
    final title = value['title'];
    final statusName = value['status'];
    final createdAt = value['createdAt'];
    if (id is! String ||
        source is! String ||
        title is! String ||
        createdAt is! String) {
      return null;
    }

    final parsedCreatedAt = DateTime.tryParse(createdAt);
    if (parsedCreatedAt == null) {
      return null;
    }

    return SyncActivityEntry(
      id: id,
      source: source,
      title: title,
      details: value['details'] is String ? value['details'] as String : null,
      status: SyncActivityStatus.values.firstWhere(
        (candidate) => candidate.name == statusName,
        orElse: () => SyncActivityStatus.synced,
      ),
      createdAt: parsedCreatedAt,
    );
  }
}

class MediaTransferJob {
  const MediaTransferJob({
    required this.id,
    required this.source,
    required this.label,
    required this.kind,
    required this.state,
    required this.createdAt,
    this.completedAt,
  });

  final String id;
  final String source;
  final String label;
  final MediaTransferKind kind;
  final MediaTransferState state;
  final DateTime createdAt;
  final DateTime? completedAt;

  MediaTransferJob copyWith({
    String? id,
    String? source,
    String? label,
    MediaTransferKind? kind,
    MediaTransferState? state,
    DateTime? createdAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return MediaTransferJob(
      id: id ?? this.id,
      source: source ?? this.source,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'source': source,
      'label': label,
      'kind': kind.name,
      'state': state.name,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  static MediaTransferJob? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }

    final id = value['id'];
    final source = value['source'];
    final label = value['label'];
    final createdAt = value['createdAt'];
    if (id is! String ||
        source is! String ||
        label is! String ||
        createdAt is! String) {
      return null;
    }

    final parsedCreatedAt = DateTime.tryParse(createdAt);
    if (parsedCreatedAt == null) {
      return null;
    }

    final completedAt = value['completedAt'];
    return MediaTransferJob(
      id: id,
      source: source,
      label: label,
      kind: MediaTransferKind.values.firstWhere(
        (candidate) => candidate.name == value['kind'],
        orElse: () => MediaTransferKind.file,
      ),
      state: MediaTransferState.values.firstWhere(
        (candidate) => candidate.name == value['state'],
        orElse: () => MediaTransferState.queued,
      ),
      createdAt: parsedCreatedAt,
      completedAt: completedAt is String && completedAt.isNotEmpty
          ? DateTime.tryParse(completedAt)
          : null,
    );
  }
}

class PushRegistrationContext {
  const PushRegistrationContext({
    required this.notificationsEnabled,
    required this.isAuthenticated,
  });

  final bool notificationsEnabled;
  final bool isAuthenticated;
}

class PushRegistrationSyncResult {
  const PushRegistrationSyncResult({
    required this.registration,
    this.activityStatus,
    this.activityTitle,
    this.activityDetails,
    this.errorMessage,
  });

  final PushRegistration registration;
  final SyncActivityStatus? activityStatus;
  final String? activityTitle;
  final String? activityDetails;
  final String? errorMessage;

  bool get hasActivity => activityStatus != null && activityTitle != null;
}

abstract class PushRegistrationService {
  const PushRegistrationService();

  DeliveryTarget get target;
  String get providerName;

  Future<PushRegistrationSyncResult> syncRegistration({
    required PushRegistrationContext context,
    required bool forceFailure,
  });
}

class LocalPushRegistrationService implements PushRegistrationService {
  const LocalPushRegistrationService();

  @override
  DeliveryTarget get target => DeliveryTarget.localSeeded;

  @override
  String get providerName => 'Local push simulator';

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
        activityTitle: 'Push delivery paused',
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
        activityTitle: 'Push token sync failed',
        activityDetails:
            'Check FlutterFire or server token setup before the next release candidate.',
        errorMessage: 'We could not sync this device token right now.',
      );
    }

    final tokenPreview =
        'ww_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    return PushRegistrationSyncResult(
      registration: PushRegistration(
        state: PushRegistrationState.registered,
        tokenPreview: tokenPreview,
        lastSyncedAt: DateTime.now(),
      ),
      activityStatus: SyncActivityStatus.synced,
      activityTitle: 'Push token synced',
      activityDetails: 'Token $tokenPreview is ready for server-side delivery.',
    );
  }
}

class MediaTransferExecution {
  const MediaTransferExecution({required this.state});

  final MediaTransferState state;
}

abstract class MediaTransferService {
  const MediaTransferService();

  DeliveryTarget get target;
  String get providerName;

  Future<MediaTransferExecution> completeTransfer({
    required MediaTransferJob job,
    required bool forceFailure,
  });
}

class LocalMediaTransferService implements MediaTransferService {
  const LocalMediaTransferService();

  @override
  DeliveryTarget get target => DeliveryTarget.localSeeded;

  @override
  String get providerName => 'Local media transfer pipeline';

  @override
  Future<MediaTransferExecution> completeTransfer({
    required MediaTransferJob job,
    required bool forceFailure,
  }) async {
    if (forceFailure) {
      return const MediaTransferExecution(state: MediaTransferState.failed);
    }

    return const MediaTransferExecution(state: MediaTransferState.uploaded);
  }
}

abstract class IntegrationProviderCatalog {
  const IntegrationProviderCatalog();

  List<IntegrationProviderReadiness> get providers;
}

class DefaultIntegrationProviderCatalog implements IntegrationProviderCatalog {
  const DefaultIntegrationProviderCatalog();

  static const List<IntegrationProviderReadiness> _providers =
      <IntegrationProviderReadiness>[
    IntegrationProviderReadiness(
      target: DeliveryTarget.localSeeded,
      providerName: 'Seeded local repositories',
      status: IntegrationProviderStatus.active,
      summary:
          'The app currently runs against seeded repositories with persistent local state and non-blocking integration tracking.',
      capabilities: <String>[
        'Repository wrappers',
        'Persisted sessions',
        'Push token simulation',
        'Media pipeline simulation',
      ],
      nextSteps: <String>[
        'Swap these services for Firebase-backed implementations once project credentials are available.',
      ],
    ),
    IntegrationProviderReadiness(
      target: DeliveryTarget.firebaseReady,
      providerName: 'FlutterFire adapters',
      status: IntegrationProviderStatus.scaffolded,
      summary:
          'Push, upload, and repository seams are ready for Firebase Auth, Firestore, Storage, and Cloud Messaging adapters.',
      capabilities: <String>[
        'Push token sync contract',
        'Media upload contract',
        'Repository-safe UI boundary',
      ],
      nextSteps: <String>[
        'Run flutterfire configure and commit firebase_options.dart.',
        'Add GoogleService-Info.plist and google-services.json per environment.',
        'Bind Firebase Auth, Firestore, Storage, and FCM to these contracts.',
      ],
    ),
    IntegrationProviderReadiness(
      target: DeliveryTarget.awsCompatible,
      providerName: 'AWS or mixed-provider path',
      status: IntegrationProviderStatus.compatible,
      summary:
          'The same boundaries can later map to AWS services or a custom API layer without rewriting presentation code.',
      capabilities: <String>[
        'Portable repository interfaces',
        'Provider-isolated push and uploads',
        'Custom API escalation path',
      ],
      nextSteps: <String>[
        'Choose Cognito or a custom auth broker.',
        'Define API, media upload, push fanout, and moderation services.',
      ],
    ),
  ];

  @override
  List<IntegrationProviderReadiness> get providers => _providers;
}

class IntegrationHubController extends ChangeNotifier {
  IntegrationHubController({
    SharedPreferences? preferences,
    PushRegistrationService? pushRegistrationService,
    MediaTransferService? mediaTransferService,
    IntegrationProviderCatalog? providerCatalog,
    RepositoryAdapterCatalog? repositoryCatalog,
    BackendRuntimeConfig? runtimeConfig,
    this.pushSyncLatency = Duration.zero,
    this.mediaTransferLatency = Duration.zero,
  })  : _preferences = preferences,
        _runtimeConfig =
            runtimeConfig ?? BackendRuntimeConfig.fromEnvironment(),
        _pushRegistrationService =
            pushRegistrationService ?? const LocalPushRegistrationService(),
        _mediaTransferService =
            mediaTransferService ?? const LocalMediaTransferService(),
        _providerCatalog =
            providerCatalog ?? const DefaultIntegrationProviderCatalog(),
        _repositoryCatalog = repositoryCatalog ??
            RuntimeAwareRepositoryAdapterCatalog(
              runtimeConfig ?? BackendRuntimeConfig.fromEnvironment(),
            );

  static const _pushRegistrationKey = 'integration_push_registration_v1';
  static const _syncActivitiesKey = 'integration_sync_activities_v1';
  static const _mediaTransfersKey = 'integration_media_transfers_v1';
  static const _maxActivities = 10;
  static const _maxTransfers = 8;

  final Duration pushSyncLatency;
  final Duration mediaTransferLatency;
  SharedPreferences? _preferences;
  final BackendRuntimeConfig _runtimeConfig;
  final PushRegistrationService _pushRegistrationService;
  final MediaTransferService _mediaTransferService;
  final IntegrationProviderCatalog _providerCatalog;
  final RepositoryAdapterCatalog _repositoryCatalog;

  bool _hasLoaded = false;
  bool _isLoading = false;
  bool _isSyncingPush = false;
  bool _isRetryingFailedTransfers = false;
  bool _isClearingCompletedTransfers = false;
  bool _notificationsEnabled = true;
  bool _isAuthenticated = false;
  bool _pushContextDirty = false;
  bool _forceNextPushSyncFailure = false;
  bool _forceNextMediaTransferFailure = false;
  String? _errorMessage;
  PushRegistration _pushRegistration = const PushRegistration();
  List<SyncActivityEntry> _recentActivity = const <SyncActivityEntry>[];
  List<MediaTransferJob> _mediaTransfers = const <MediaTransferJob>[];
  DateTime? _lastUpdatedAt;
  int _sequence = 0;

  bool get hasLoaded => _hasLoaded;
  bool get isLoading => _isLoading;
  bool get isSyncingPush => _isSyncingPush;
  bool get isRetryingFailedTransfers => _isRetryingFailedTransfers;
  bool get isClearingCompletedTransfers => _isClearingCompletedTransfers;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get isAuthenticated => _isAuthenticated;
  String? get errorMessage => _errorMessage;
  PushRegistration get pushRegistration => _pushRegistration;
  List<SyncActivityEntry> get recentActivity =>
      List<SyncActivityEntry>.unmodifiable(_recentActivity);
  List<MediaTransferJob> get mediaTransfers =>
      List<MediaTransferJob>.unmodifiable(_mediaTransfers);
  DateTime? get lastUpdatedAt => _lastUpdatedAt;
  List<DeliveryTarget> get deliveryTargets => providerReadiness
      .map((provider) => provider.target)
      .toList(growable: false);
  List<IntegrationProviderReadiness> get providerReadiness =>
      List<IntegrationProviderReadiness>.unmodifiable(
          _providerCatalog.providers);
  List<RepositoryAdapterReadiness> get repositoryReadiness =>
      List<RepositoryAdapterReadiness>.unmodifiable(
        _repositoryCatalog.adapters,
      );
  String get pushProviderName => _pushRegistrationService.providerName;
  String get mediaTransferProviderName => _mediaTransferService.providerName;
  DeliveryTarget get activePushDeliveryTarget =>
      _pushRegistrationService.target;
  DeliveryTarget get activeMediaDeliveryTarget => _mediaTransferService.target;
  BackendRuntimeConfig get runtimeConfig => _runtimeConfig;

  int get syncedActivityCount => _recentActivity
      .where((entry) => entry.status == SyncActivityStatus.synced)
      .length;

  int get failedActivityCount => _recentActivity
      .where((entry) => entry.status == SyncActivityStatus.failed)
      .length;

  int get queuedTransferCount => _mediaTransfers
      .where((job) => job.state == MediaTransferState.queued)
      .length;

  int get uploadingTransferCount => _mediaTransfers
      .where((job) => job.state == MediaTransferState.uploading)
      .length;

  int get uploadedTransferCount => _mediaTransfers
      .where((job) => job.state == MediaTransferState.uploaded)
      .length;

  int get failedTransferCount => _mediaTransfers
      .where((job) => job.state == MediaTransferState.failed)
      .length;

  Future<void> ensureLoaded() async {
    if (_hasLoaded || _isLoading) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final preferences = await _preferencesInstance;
      _pushRegistration = PushRegistration.fromJson(
        _decodeObjectMap(preferences.getString(_pushRegistrationKey)),
      );
      _recentActivity = _decodeList(
        preferences.getStringList(_syncActivitiesKey),
        SyncActivityEntry.fromJson,
      );
      _mediaTransfers = _decodeList(
        preferences.getStringList(_mediaTransfersKey),
        MediaTransferJob.fromJson,
      );
      _hasLoaded = true;
    } catch (_) {
      _errorMessage =
          'We could not restore backend and sync readiness on this device.';
    }

    _isLoading = false;
    _lastUpdatedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> applyRuntimeContext({
    required bool notificationsEnabled,
    required bool isAuthenticated,
  }) async {
    await ensureLoaded();
    final didChange = _notificationsEnabled != notificationsEnabled ||
        _isAuthenticated != isAuthenticated;
    _notificationsEnabled = notificationsEnabled;
    _isAuthenticated = isAuthenticated;
    if (!didChange) {
      return;
    }

    _pushContextDirty = true;
    if (_isSyncingPush) {
      return;
    }

    while (_pushContextDirty) {
      _pushContextDirty = false;
      await _syncPushRegistrationInternal(recordActivity: true);
    }
  }

  Future<void> syncPushRegistration() async {
    await ensureLoaded();
    _pushContextDirty = true;
    if (_isSyncingPush) {
      return;
    }

    while (_pushContextDirty) {
      _pushContextDirty = false;
      await _syncPushRegistrationInternal(recordActivity: true);
    }
  }

  Future<void> recordSyncSuccess({
    required String source,
    required String title,
    String? details,
  }) async {
    await ensureLoaded();
    _errorMessage = null;
    _prependActivity(
      SyncActivityEntry(
        id: _nextId('sync'),
        source: source,
        title: title,
        details: details,
        status: SyncActivityStatus.synced,
        createdAt: DateTime.now(),
      ),
    );
    await _persistState();
    notifyListeners();
  }

  Future<void> recordSyncFailure({
    required String source,
    required String title,
    String? details,
  }) async {
    await ensureLoaded();
    _prependActivity(
      SyncActivityEntry(
        id: _nextId('sync'),
        source: source,
        title: title,
        details: details,
        status: SyncActivityStatus.failed,
        createdAt: DateTime.now(),
      ),
    );
    await _persistState();
    notifyListeners();
  }

  Future<MediaTransferJob> queueMediaTransfer({
    required String source,
    required String label,
    required MediaTransferKind kind,
  }) async {
    await ensureLoaded();
    _errorMessage = null;
    final createdJob = MediaTransferJob(
      id: _nextId('media'),
      source: source,
      label: label,
      kind: kind,
      state: MediaTransferState.queued,
      createdAt: DateTime.now(),
    );
    _prependTransfer(createdJob);
    await _persistState();
    notifyListeners();

    final uploadingJob = await _updateTransferState(
      createdJob.id,
      MediaTransferState.uploading,
    );
    return _completeTransferJob(uploadingJob);
  }

  Future<void> retryFailedTransfers() async {
    await ensureLoaded();
    if (_isRetryingFailedTransfers) {
      return;
    }

    _isRetryingFailedTransfers = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final failedJobs = _mediaTransfers
          .where((job) => job.state == MediaTransferState.failed)
          .toList(growable: false);
      for (final job in failedJobs) {
        await _updateTransferState(
          job.id,
          MediaTransferState.queued,
          clearCompletedAt: true,
        );
        final uploadingJob = await _updateTransferState(
          job.id,
          MediaTransferState.uploading,
        );
        await _completeTransferJob(uploadingJob);
      }
    } finally {
      _isRetryingFailedTransfers = false;
      notifyListeners();
    }
  }

  Future<void> clearCompletedTransfers() async {
    await ensureLoaded();
    if (_isClearingCompletedTransfers) {
      return;
    }

    _isClearingCompletedTransfers = true;
    notifyListeners();

    _mediaTransfers = List<MediaTransferJob>.unmodifiable(
      _mediaTransfers.where(
        (job) => job.state != MediaTransferState.uploaded,
      ),
    );
    _lastUpdatedAt = DateTime.now();
    await _persistState();

    _isClearingCompletedTransfers = false;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }

    _errorMessage = null;
    notifyListeners();
  }

  @visibleForTesting
  void debugFailNextPushSync() {
    _forceNextPushSyncFailure = true;
  }

  @visibleForTesting
  void debugFailNextMediaTransfer() {
    _forceNextMediaTransferFailure = true;
  }

  Future<void> _syncPushRegistrationInternal({
    required bool recordActivity,
  }) async {
    _isSyncingPush = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _wait(pushSyncLatency);
      final result = await _pushRegistrationService.syncRegistration(
        context: PushRegistrationContext(
          notificationsEnabled: _notificationsEnabled,
          isAuthenticated: _isAuthenticated,
        ),
        forceFailure: _consumeForcedPushSyncFailure(),
      );
      _pushRegistration = result.registration;
      _errorMessage = result.errorMessage;
      if (recordActivity && result.hasActivity) {
        _prependActivity(
          SyncActivityEntry(
            id: _nextId('sync'),
            source: 'Notifications',
            title: result.activityTitle!,
            details: result.activityDetails,
            status: result.activityStatus!,
            createdAt: DateTime.now(),
          ),
        );
      }

      await _persistState();
    } finally {
      _isSyncingPush = false;
      notifyListeners();
    }
  }

  Future<MediaTransferJob> _updateTransferState(
    String transferId,
    MediaTransferState state, {
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) async {
    await _wait(mediaTransferLatency);

    late MediaTransferJob updatedJob;
    _mediaTransfers = List<MediaTransferJob>.unmodifiable(
      _mediaTransfers.map((job) {
        if (job.id != transferId) {
          return job;
        }

        updatedJob = job.copyWith(
          state: state,
          completedAt: completedAt,
          clearCompletedAt: clearCompletedAt,
        );
        return updatedJob;
      }),
    );
    _lastUpdatedAt = DateTime.now();
    await _persistState();
    notifyListeners();
    return updatedJob;
  }

  Future<MediaTransferJob> _completeTransferJob(MediaTransferJob job) async {
    final execution = await _mediaTransferService.completeTransfer(
      job: job,
      forceFailure: _consumeForcedMediaTransferFailure(),
    );
    return _updateTransferState(
      job.id,
      execution.state,
      completedAt:
          _isTerminalTransferState(execution.state) ? DateTime.now() : null,
    );
  }

  void _prependActivity(SyncActivityEntry entry) {
    _recentActivity = List<SyncActivityEntry>.unmodifiable(
      <SyncActivityEntry>[
        entry,
        ..._recentActivity,
      ].take(_maxActivities),
    );
    _lastUpdatedAt = entry.createdAt;
  }

  void _prependTransfer(MediaTransferJob job) {
    _mediaTransfers = List<MediaTransferJob>.unmodifiable(
      <MediaTransferJob>[
        job,
        ..._mediaTransfers,
      ].take(_maxTransfers),
    );
    _lastUpdatedAt = job.createdAt;
  }

  String _nextId(String prefix) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '$prefix-$timestamp-${_sequence++}';
  }

  bool _consumeForcedPushSyncFailure() {
    if (_forceNextPushSyncFailure) {
      _forceNextPushSyncFailure = false;
      return true;
    }
    return false;
  }

  bool _consumeForcedMediaTransferFailure() {
    if (_forceNextMediaTransferFailure) {
      _forceNextMediaTransferFailure = false;
      return true;
    }
    return false;
  }

  bool _isTerminalTransferState(MediaTransferState state) {
    return switch (state) {
      MediaTransferState.uploaded || MediaTransferState.failed => true,
      MediaTransferState.queued || MediaTransferState.uploading => false,
    };
  }

  Future<void> _persistState() async {
    final preferences = await _preferencesInstance;
    await preferences.setString(
      _pushRegistrationKey,
      jsonEncode(_pushRegistration.toJson()),
    );
    await preferences.setStringList(
      _syncActivitiesKey,
      _recentActivity
          .map((entry) => jsonEncode(entry.toJson()))
          .toList(growable: false),
    );
    await preferences.setStringList(
      _mediaTransfersKey,
      _mediaTransfers
          .map((job) => jsonEncode(job.toJson()))
          .toList(growable: false),
    );
  }

  Future<void> _wait(Duration duration) {
    if (duration == Duration.zero) {
      return Future<void>.value();
    }
    return Future<void>.delayed(duration);
  }

  Future<SharedPreferences> get _preferencesInstance async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  static Map<String, dynamic>? _decodeObjectMap(String? serialized) {
    if (serialized == null || serialized.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(serialized);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static List<T> _decodeList<T>(
    List<String>? serializedValues,
    T? Function(Object?) decoder,
  ) {
    if (serializedValues == null || serializedValues.isEmpty) {
      return <T>[];
    }

    final values = <T>[];
    for (final entry in serializedValues) {
      if (entry.isEmpty) {
        continue;
      }
      final decoded = decoder(jsonDecode(entry));
      if (decoded != null) {
        values.add(decoded);
      }
    }
    return List<T>.unmodifiable(values);
  }
}
