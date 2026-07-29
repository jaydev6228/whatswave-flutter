import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/core/config/backend_runtime_config.dart';
import 'package:whatswave/core/integrations/backend_repository_bundle.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/auth/data/fake_auth_repository.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('builds the local seeded repository bundle by default', () {
    final bundle = const BackendRepositoryBundleFactory().create(
      runtimeConfig: BackendRuntimeConfig.fromValues(),
      enableDemoRestoreSession: false,
    );

    expect(bundle.authRepository, isA<FakeAuthRepository>());
    expect(bundle.chatRepository, isA<FakeChatRepository>());
    expect(bundle.callsRepository, isA<FakeCallsRepository>());
    expect(bundle.communitiesRepository, isA<FakeCommunitiesRepository>());
    expect(bundle.updatesRepository, isA<FakeUpdatesRepository>());
    expect(bundle.repositoryCatalog.adapters, hasLength(5));
    expect(
      bundle.repositoryCatalog.adapters.every(
          (adapter) => adapter.status == RepositoryAdapterStatus.localActive),
      isTrue,
    );
  });

  test('restores the seeded demo user when demo restore mode is enabled',
      () async {
    final bundle = const BackendRepositoryBundleFactory().create(
      runtimeConfig: BackendRuntimeConfig.fromValues(),
      enableDemoRestoreSession: true,
    );

    final user = await bundle.authRepository.restoreSession();

    expect(user?.phoneNumber, DemoData.currentUser.phoneNumber);
    expect(user?.name, DemoData.currentUser.name);
  });

  test('describes firebase-first repositories as local fallback scaffolds', () {
    final config = BackendRuntimeConfig.fromValues(
      backendModeValue: 'firebase',
      environmentValue: 'development',
      useFirebaseEmulators: true,
      firebaseProjectId: 'ww-dev',
    );
    final bundle = const BackendRepositoryBundleFactory().create(
      runtimeConfig: config,
      enableDemoRestoreSession: false,
    );

    expect(bundle.repositoryCatalog.adapters, hasLength(5));
    expect(
      bundle.repositoryCatalog.adapters.first.providerName,
      'Firebase Auth scaffold',
    );
    expect(
      bundle.repositoryCatalog.adapters.first.status,
      RepositoryAdapterStatus.localFallback,
    );
    expect(
      bundle.repositoryCatalog.adapters[1].nextSteps,
      contains(
        'Enable Firestore collections, indexes, and security rules for messages and threads.',
      ),
    );
    expect(
      bundle.repositoryCatalog.adapters[2].capabilities,
      contains('Firebase emulators'),
    );
  });

  test('describes aws-ready repositories as portable local fallback seams', () {
    final config = BackendRuntimeConfig.fromValues(
      backendModeValue: 'aws',
      environmentValue: 'staging',
      callingProviderValue: 'livekit',
    );
    final bundle = const BackendRepositoryBundleFactory().create(
      runtimeConfig: config,
      enableDemoRestoreSession: false,
    );

    expect(bundle.repositoryCatalog.adapters, hasLength(5));
    expect(
      bundle.repositoryCatalog.adapters.first.providerName,
      'AWS auth scaffold',
    );
    expect(
      bundle.repositoryCatalog.adapters.last.providerName,
      'LiveKit AWS bridge',
    );
    expect(
      bundle.repositoryCatalog.adapters.every(
          (adapter) => adapter.status == RepositoryAdapterStatus.localFallback),
      isTrue,
    );
  });
}
