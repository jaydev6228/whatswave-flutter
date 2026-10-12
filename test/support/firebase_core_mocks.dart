import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in a fake `firebase_core` so a test can construct the
/// firebase-first repositories.
///
/// `BackendRepositoryBundleFactory.create` builds every repository eagerly,
/// and each firebase-backed one resolves `FirebaseAuth.instance` /
/// `FirebaseFirestore.instance` / `FirebaseStorage.instance` in its
/// initializer list. That is always safe in the real app, because
/// `bootstrap()` awaits `Firebase.initializeApp()` before `runApp` -- so the
/// eagerness is not a production bug, it is a precondition the app
/// guarantees and a test has to supply for itself. Without it the bundle
/// throws `[core/no-app] No Firebase App '[DEFAULT]' has been created`.
///
/// Rolls its own host mock rather than calling the package's
/// `setupFirebaseCoreMocks()`, whose canned options omit `storageBucket` --
/// which gets you past the no-app error only to hit
/// `[firebase_storage/no-bucket]` the moment `FirebaseMediaUploader`
/// resolves `FirebaseStorage.instance`.
Future<void> installFirebaseCoreMocks() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestFirebaseCoreHostApi.setUp(_BucketedMockFirebaseApp());
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}

CoreFirebaseOptions _options() => CoreFirebaseOptions(
      apiKey: 'test-api-key',
      projectId: 'whatswave-test',
      appId: 'test-app-id',
      messagingSenderId: 'test-sender-id',
      // The reason this class exists -- see installFirebaseCoreMocks.
      storageBucket: 'whatswave-test.appspot.com',
    );

CoreInitializeResponse _response(String appName) => CoreInitializeResponse(
      name: appName,
      options: _options(),
      pluginConstants: const <String, Object?>{},
    );

class _BucketedMockFirebaseApp implements TestFirebaseCoreHostApi {
  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) async =>
      _response(appName);

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async =>
      <CoreInitializeResponse>[_response(defaultFirebaseAppName)];

  @override
  Future<CoreFirebaseOptions> optionsFromResource() async => _options();
}
