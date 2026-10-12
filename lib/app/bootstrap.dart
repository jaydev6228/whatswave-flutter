import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/observability/app_telemetry.dart';

import 'package:firebase_core/firebase_core.dart';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import '../firebase_options.dart';

/// Builds the root widget once Firebase and the bindings are up.
///
/// Async because end-to-end encryption has to open its databases before
/// the first screen can send anything, and it is handed the current-uid
/// getter rather than a uid because it outlives any one session.
typedef AppBuilder = Future<Widget> Function(String? Function() currentUid);

void bootstrap({
  required AppBuilder appBuilder,
  AppTelemetry? telemetry,
}) {
  final resolvedTelemetry = telemetry ?? LocalAppTelemetry();

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        final contextDescription = details.context?.toDescription();
        resolvedTelemetry.recordError(
          details.exception,
          details.stack ?? StackTrace.current,
          source: details.library ?? 'flutter_error',
          fatal: true,
          attributes: <String, Object?>{
            if (contextDescription != null) 'context': contextDescription,
          },
        );
      };

      PlatformDispatcher.instance.onError = (error, stackTrace) {
        resolvedTelemetry.recordError(
          error,
          stackTrace,
          source: 'platform_dispatcher',
          fatal: true,
        );
        return kReleaseMode;
      };
      final app = await appBuilder(
        () => fb_auth.FirebaseAuth.instance.currentUser?.uid,
      );
      runApp(
        AppTelemetryScope(
          telemetry: resolvedTelemetry,
          child: app,
        ),
      );
    },
    (error, stackTrace) {
      resolvedTelemetry.recordError(
        error,
        stackTrace,
        source: 'run_zoned_guarded',
        fatal: true,
      );
    },
  );
}
