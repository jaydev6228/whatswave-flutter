import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';

import '../core/config/backend_runtime_config.dart';
import '../core/config/runtime_flags.dart';
import '../core/controllers/app_preferences_controller.dart';
import '../core/integrations/backend_integration_bundle.dart';
import '../core/integrations/backend_repository_bundle.dart';
import '../core/integrations/integration_hub_controller.dart';
import '../core/permissions/app_permission_service.dart';
import '../core/integrations/tracked_repositories.dart';
import '../core/observability/app_telemetry.dart';
import '../core/widgets/app_lock_gate.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/auth_flow_screen.dart';
import '../features/auth/presentation/session_splash_screen.dart';
import '../features/calls/application/calls_controller.dart';
import '../features/calls/data/calls_repository.dart';
import '../features/calls/data/firestore_call_signaling_service.dart';
import '../features/calls/data/livekit_token_service.dart';
import '../features/calls/data/ringtone_player.dart';
import '../features/calls/domain/call_history_entry.dart';
import '../features/calls/presentation/call_experience_screen.dart';
import '../features/chats/application/chats_controller.dart';
import '../features/chats/data/chat_repository.dart';
import '../features/communities/application/communities_controller.dart';
import '../features/communities/data/communities_repository.dart';
import '../features/updates/application/updates_controller.dart';
import '../features/updates/data/updates_repository.dart';
import 'theme/app_scroll_behavior.dart';
import 'theme/app_theme.dart';
import '../features/shell/presentation/app_shell.dart';

class WhatsWaveApp extends StatefulWidget {
  const WhatsWaveApp({
    this.authRepository,
    this.callsRepository,
    this.chatRepository,
    this.communitiesRepository,
    this.updatesRepository,
    this.preferencesController,
    this.integrationController,
    this.backendRuntimeConfig,
    this.permissionService,
    this.authLocaleCountryCode,
    this.telemetry,
    super.key,
  });

  final AuthRepository? authRepository;
  final CallsRepository? callsRepository;
  final ChatRepository? chatRepository;
  final CommunitiesRepository? communitiesRepository;
  final UpdatesRepository? updatesRepository;
  final AppPreferencesController? preferencesController;
  final IntegrationHubController? integrationController;
  final BackendRuntimeConfig? backendRuntimeConfig;
  final AppPermissionService? permissionService;
  final String? authLocaleCountryCode;
  final AppTelemetry? telemetry;

  @override
  State<WhatsWaveApp> createState() => _WhatsWaveAppState();
}

class _WhatsWaveAppState extends State<WhatsWaveApp> {
  final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
  String? _presentedIncomingCallSessionId;

  late final AuthController _authController;
  late final CallsController _callsController;
  late final ChatsController _chatsController;
  late final CommunitiesController _communitiesController;
  late final UpdatesController _updatesController;
  late final AppPreferencesController _preferencesController;
  late final IntegrationHubController _integrationController;
  late final BackendRuntimeConfig _backendRuntimeConfig;
  late final AppPermissionService _permissionService;
  late final AppTelemetry _telemetry;
  late final bool _ownsPreferencesController;
  late final bool _ownsIntegrationController;

  @override
  void initState() {
    super.initState();
    _ownsPreferencesController = widget.preferencesController == null;
    _preferencesController =
        widget.preferencesController ?? AppPreferencesController();
    _backendRuntimeConfig =
        widget.backendRuntimeConfig ?? BackendRuntimeConfig.fromEnvironment();
    _ownsIntegrationController = widget.integrationController == null;
    final backendBundle = const BackendIntegrationBundleFactory().create(
      runtimeConfig: _backendRuntimeConfig,
    );
    final repositoryBundle = const BackendRepositoryBundleFactory().create(
      runtimeConfig: _backendRuntimeConfig,
      enableDemoRestoreSession: kEnableDemoRestoreSession,
    );
    _integrationController = widget.integrationController ??
        IntegrationHubController(
          runtimeConfig: _backendRuntimeConfig,
          pushRegistrationService: backendBundle.pushRegistrationService,
          mediaTransferService: backendBundle.mediaTransferService,
          providerCatalog: backendBundle.providerCatalog,
          repositoryCatalog: repositoryBundle.repositoryCatalog,
        );
    _permissionService =
        widget.permissionService ?? NativeAppPermissionService();
    _telemetry = widget.telemetry ?? NoopAppTelemetry.instance;
    _preferencesController.ensureLoaded();
    _integrationController.ensureLoaded();
    _authController = AuthController(
      repository: TrackedAuthRepository(
        delegate: widget.authRepository ?? repositoryBundle.authRepository,
        integrations: _integrationController,
      ),
      localeCountryCode: widget.authLocaleCountryCode ??
          WidgetsBinding.instance.platformDispatcher.locale.countryCode,
      permissionService: _permissionService,
    );
    const liveKitUrl = String.fromEnvironment('LIVEKIT_URL');
    const tokenServerUrl = String.fromEnvironment('LIVEKIT_TOKEN_SERVER_URL');
    final prefersFirebase = _backendRuntimeConfig.prefersFirebase;
    _callsController = CallsController(
      repository: TrackedCallsRepository(
        delegate: widget.callsRepository ?? repositoryBundle.callsRepository,
        integrations: _integrationController,
      ),
      permissionService: _permissionService,
      telemetry: _telemetry,
      signalingService:
          prefersFirebase ? FirestoreCallSignalingService() : null,
      tokenService: prefersFirebase && tokenServerUrl.isNotEmpty
          ? LiveKitTokenService(tokenServerUrl: tokenServerUrl)
          : null,
      liveKitUrl: liveKitUrl.isEmpty ? null : liveKitUrl,
      currentUserIdStream: prefersFirebase
          ? fb_auth.FirebaseAuth.instance
              .authStateChanges()
              .map((user) => user?.uid)
          : null,
      // Unconditional (not gated on prefersFirebase like signaling/token
      // above) -- ringing is a local, platform-side concern that should
      // also fire for the debug "simulate incoming call" flow, not just
      // real signaled calls.
      ringtonePlayer: SystemRingtonePlayer(),
    );
    _callsController.addListener(_handleIncomingCallSession);
    _chatsController = ChatsController(
      repository: TrackedChatRepository(
        delegate: widget.chatRepository ?? repositoryBundle.chatRepository,
        integrations: _integrationController,
      ),
      permissionService: _permissionService,
    );
    _communitiesController = CommunitiesController(
      repository: TrackedCommunitiesRepository(
        delegate: widget.communitiesRepository ??
            repositoryBundle.communitiesRepository,
        integrations: _integrationController,
      ),
      permissionService: _permissionService,
      createGroupThread: _chatsController.createGroup,
    );
    _updatesController = UpdatesController(
      repository: TrackedUpdatesRepository(
        delegate:
            widget.updatesRepository ?? repositoryBundle.updatesRepository,
        integrations: _integrationController,
      ),
    );
    _authController.addListener(_handleIntegrationContextChanged);
    _preferencesController.addListener(_handleIntegrationContextChanged);
    _handleIntegrationContextChanged();
    _authController.restoreSession();
  }

  /// Auto-opens the call screen for a real incoming call, which -- unlike
  /// every other way of starting a call in this app -- has no button press
  /// to navigate from (call_flow.dart's helpers push explicitly for
  /// outgoing calls and the debug "simulate incoming call" flow; this
  /// covers the one case those can't: a call arriving via
  /// CallSignalingService while the user is on some unrelated screen).
  /// Scoped tightly to real incoming calls so it never double-pushes over
  /// an explicit push elsewhere.
  void _handleIncomingCallSession() {
    final session = _callsController.currentSession;
    if (session == null) {
      _presentedIncomingCallSessionId = null;
      return;
    }

    final isUnhandledRealIncomingCall = session.direction ==
            CallDirection.incoming &&
        session.isReal &&
        _presentedIncomingCallSessionId != session.id;
    if (!isUnhandledRealIncomingCall) {
      return;
    }

    _presentedIncomingCallSessionId = session.id;
    _rootNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => CallExperienceScreen(controller: _callsController),
        fullscreenDialog: true,
      ),
    );
  }

  void _handleIntegrationContextChanged() {
    unawaited(
      _integrationController.applyRuntimeContext(
        notificationsEnabled: _preferencesController.notificationsEnabled,
        isAuthenticated: _authController.isAuthenticated,
      ),
    );
  }

  @override
  void dispose() {
    _authController.removeListener(_handleIntegrationContextChanged);
    _preferencesController.removeListener(_handleIntegrationContextChanged);
    _callsController.removeListener(_handleIncomingCallSession);
    _authController.dispose();
    _callsController.dispose();
    _chatsController.dispose();
    _communitiesController.dispose();
    _updatesController.dispose();
    if (_ownsPreferencesController) {
      _preferencesController.dispose();
    }
    if (_ownsIntegrationController) {
      _integrationController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_preferencesController, _authController]),
      builder: (context, _) {
        return AppTelemetryScope(
          telemetry: _telemetry,
          child: MaterialApp(
            navigatorKey: _rootNavigatorKey,
            debugShowCheckedModeBanner: false,
            title: 'WhatsWave',
            theme: AppTheme.lightTheme(),
            darkTheme: AppTheme.darkTheme(),
            themeMode: _preferencesController.themeMode,
            scrollBehavior: const WhatsWaveScrollBehavior(),
            home: _buildHome(),
          ),
        );
      },
    );
  }

  Widget _buildHome() {
    if (_authController.step == AuthStep.splash) {
      return SessionSplashScreen(message: _authController.statusMessage);
    }

    if (_authController.isAuthenticated &&
        _authController.currentUser != null) {
      return _authenticatedHome();
    }

    return AuthFlowScreen(controller: _authController);
  }

  Widget _authenticatedHome() {
    return AppLockGate(
      controller: _preferencesController,
      isEnabled: _authController.isAuthenticated,
      child: AppShell(
        authController: _authController,
        currentUser: _authController.currentUser!,
        preferencesController: _preferencesController,
        integrationController: _integrationController,
        callsController: _callsController,
        chatsController: _chatsController,
        communitiesController: _communitiesController,
        updatesController: _updatesController,
      ),
    );
  }
}
