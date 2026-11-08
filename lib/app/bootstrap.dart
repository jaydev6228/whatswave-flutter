import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/observability/app_telemetry.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import '../core/config/backend_runtime_config.dart';
import '../firebase_options.dart';

/// Ports for the local emulator suite.
///
/// firebase.json is gitignored (it carries project and app ids), so these
/// constants are the only copy of this contract in the repository. A fresh
/// clone needs the matching block added to its own firebase.json, or
/// `firebase emulators:start` serves different ports and the app silently
/// talks to production instead:
///
///     "emulators": {
///       "auth": { "port": 9099 },
///       "firestore": { "port": 8080 },
///       "storage": { "port": 9199 },
///       "functions": { "port": 5001 },
///       "ui": { "enabled": true },
///       "singleProjectMode": true
///     }
const int _authEmulatorPort = 9099;
const int _firestoreEmulatorPort = 8080;
const int _storageEmulatorPort = 9199;
const int _functionsEmulatorPort = 5001;

/// Where the emulator suite is reachable from [platform].
///
/// An Android emulator is a guest VM: loopback there is the guest itself,
/// and the host machine is 10.0.2.2. Getting this wrong does not fail
/// loudly -- the app just cannot reach the suite.
///
/// shortcut: covers simulators only. A physical device needs the host's
/// LAN IP, so widen this if we ever debug against the suite on-device.
String firebaseEmulatorHost(TargetPlatform platform) {
  return platform == TargetPlatform.android ? '10.0.2.2' : '127.0.0.1';
}

/// Points every Firebase SDK at the local emulator suite.
///
/// Without this the WW_USE_FIREBASE_EMULATORS flag only changed what the
/// Backend sync screen *claimed*: the app still talked to the real
/// project, which is worse than having no flag at all.
Future<void> _useFirebaseEmulators() async {
  final host = firebaseEmulatorHost(defaultTargetPlatform);

  await fb_auth.FirebaseAuth.instance.useAuthEmulator(host, _authEmulatorPort);
  FirebaseFirestore.instance.useFirestoreEmulator(
    host,
    _firestoreEmulatorPort,
  );
  await FirebaseStorage.instance.useStorageEmulator(
    host,
    _storageEmulatorPort,
  );
  FirebaseFunctions.instance.useFunctionsEmulator(
    host,
    _functionsEmulatorPort,
  );
}

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
      // Before anything touches a Firebase SDK: Firestore in particular
      // refuses to be pointed at an emulator once it has been used.
      if (BackendRuntimeConfig.fromEnvironment().useFirebaseEmulators) {
        await _useFirebaseEmulators();
      }
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
