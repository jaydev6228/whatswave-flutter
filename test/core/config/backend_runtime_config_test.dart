import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/config/backend_runtime_config.dart';

void main() {
  test('parses firebase-first runtime values and normalizes aliases', () {
    final config = BackendRuntimeConfig.fromValues(
      backendModeValue: 'firebase',
      environmentValue: 'prod',
      callingProviderValue: 'self_managed',
      firebaseOptionsGenerated: true,
      iosFirebaseConfigPresent: true,
      androidFirebaseConfigPresent: true,
      firebaseAuthReady: true,
      firestoreReady: true,
      firebaseStorageReady: true,
      fcmReady: true,
      apnsReady: true,
      analyticsEnabled: true,
      crashReportingEnabled: true,
      firebaseProjectId: 'ww-prod',
    );

    expect(config.backendMode, BackendMode.firebaseFirst);
    expect(config.environment, BackendEnvironment.production);
    expect(config.callingProvider, CallingProvider.selfManaged);
    expect(config.prefersFirebase, isTrue);
    expect(config.hasFirebaseDataScaffold, isTrue);
    expect(config.hasFirebaseMediaScaffold, isTrue);
    expect(config.hasFirebasePushScaffold, isTrue);
    expect(config.firebaseProjectLabel, 'ww-prod');
  });

  test('surfaces the missing firebase and release checklist items', () {
    final config = BackendRuntimeConfig.fromValues(
      backendModeValue: 'firebase-first',
      environmentValue: 'staging',
      callingProviderValue: 'simulated',
    );

    expect(config.prefersFirebase, isTrue);
    expect(config.firebaseMissingSteps, isNotEmpty);
    expect(
      config.firebaseMissingSteps.first,
      contains('flutterfire configure'),
    );
    expect(config.releaseMissingSteps, hasLength(3));
    expect(
      config.releaseMissingSteps.last,
      contains('simulated calling'),
    );
  });
}
