import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/observability/app_telemetry.dart';

void bootstrap(
  Widget app, {
  AppTelemetry? telemetry,
}) {
  final resolvedTelemetry = telemetry ?? LocalAppTelemetry();

  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
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
