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

import '../../support/firebase_core_mocks.dart';

void main() {
  // The firebase-first bundle constructs real Firebase-backed
  // repositories, which resolve their Firebase singletons eagerly.
  setUpAll(installFirebaseCoreMocks);

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

  test('describes firebase-first repositories as live cloud adapters', () {
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
      bundle.repositoryCatalog.adapters.map((a) => a.providerName),
      <String>[
        'Firebase Phone Auth',
        'Firestore chats',
        'Firestore updates (media stays local)',
        'Firestore communities (contacts stay local)',
        'LiveKit + Firestore signaling',
      ],
    );
    // Every firebase-first area is genuinely backed by a cloud service now
    // -- this test previously asserted the opposite, from back when they
    // were all local scaffolds, and the assertion was only passing
    // vacuously because constructing the bundle threw before reaching it.
    expect(
      bundle.repositoryCatalog.adapters
          .map((a) => a.status)
          .toSet(),
      <RepositoryAdapterStatus>{RepositoryAdapterStatus.liveCloud},
    );
    // The runtime config still has to surface on the adapters, which is the
    // part of this test that was actually worth keeping.
    expect(
      bundle.repositoryCatalog.adapters[2].capabilities,
      contains('Firebase emulators'),
    );
    expect(
      bundle.repositoryCatalog.adapters.first.capabilities,
      contains('Project: ww-dev'),
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
