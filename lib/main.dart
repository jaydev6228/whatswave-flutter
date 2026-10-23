import 'app/bootstrap.dart';
import 'app/whatswave_app.dart';
import 'core/config/backend_runtime_config.dart';
import 'core/crypto/signal_crypto_scope.dart';
import 'core/observability/app_telemetry.dart';
import 'core/notifications/push_tap_router.dart';
import 'core/observability/firebase_app_telemetry.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

void main() {
  final backendMode = BackendRuntimeConfig.fromEnvironment().backendMode;
  final AppTelemetry telemetry = backendMode == BackendMode.firebaseFirst
      ? FirebaseAppTelemetry()
      : LocalAppTelemetry();

  bootstrap(
    telemetry: telemetry,
    // Built inside bootstrap's zone, after Firebase.initializeApp: the
    // crypto scope opens two SQLite files and reads the signed-in uid, so
    // it cannot be constructed before the bindings and Firebase exist.
    //
    // Only in a Firebase-backed build. The seeded local backend has no
    // peers and nothing to encrypt, so it runs without one -- which is
    // also what keeps every widget test on the plaintext path.
    appBuilder: (currentUid) async {
      final isFirebase = backendMode == BackendMode.firebaseFirst;

      // Started here rather than in the widget tree so the terminated-launch
      // payload is read once, before the first frame. FirebaseMessaging
      // delivers it exactly once per launch.
      PushTapRouter? pushTapRouter;
      if (isFirebase) {
        pushTapRouter = PushTapRouter();
        await attachFirebaseMessaging(
          pushTapRouter,
          FirebaseMessagingPushBindings(
            getInitialMessage: () async =>
                (await FirebaseMessaging.instance.getInitialMessage())?.data,
            onMessageOpenedApp:
                FirebaseMessaging.onMessageOpenedApp.map((m) => m.data),
          ),
        );
      }

      return WhatsWaveApp(
        telemetry: telemetry,
        cryptoScope: isFirebase
            ? await SignalCryptoScope.create(currentUid: currentUid)
            : null,
        pushTapRouter: pushTapRouter,
      );
    },
  );
}
