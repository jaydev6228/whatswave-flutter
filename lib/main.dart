import 'app/bootstrap.dart';
import 'app/whatswave_app.dart';
import 'core/config/backend_runtime_config.dart';
import 'core/observability/app_telemetry.dart';
import 'core/observability/firebase_app_telemetry.dart';

void main() {
  final backendMode = BackendRuntimeConfig.fromEnvironment().backendMode;
  final AppTelemetry telemetry = backendMode == BackendMode.firebaseFirst
      ? FirebaseAppTelemetry()
      : LocalAppTelemetry();
  bootstrap(
    WhatsWaveApp(telemetry: telemetry),
    telemetry: telemetry,
  );
}
