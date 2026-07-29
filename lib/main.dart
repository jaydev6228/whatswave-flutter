import 'app/bootstrap.dart';
import 'app/whatswave_app.dart';
import 'core/observability/app_telemetry.dart';

void main() {
  final telemetry = LocalAppTelemetry();
  bootstrap(
    WhatsWaveApp(telemetry: telemetry),
    telemetry: telemetry,
  );
}
