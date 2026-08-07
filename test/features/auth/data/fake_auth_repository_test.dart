import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/features/auth/data/fake_auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('persists the demo session until app data is cleared', () async {
    final firstLaunchRepository = FakeAuthRepository(
      latency: Duration.zero,
      persistSession: true,
    );

    await firstLaunchRepository.requestOtp('+819012345678');
    final verifyResult = await firstLaunchRepository.verifyOtp(
      phoneNumber: '+819012345678',
      code: '123456',
    );
    expect(verifyResult.needsProfile, isTrue);

    final createdUser = await firstLaunchRepository.completeProfile(
      phoneNumber: '+819012345678',
      name: 'Jay Devra',
      about: 'Testing the demo app.',
    );

    final relaunchedRepository = FakeAuthRepository(
      latency: Duration.zero,
      persistSession: true,
    );
    final restoredUser = await relaunchedRepository.restoreSession();

    expect(restoredUser, isNotNull);
    expect(restoredUser?.name, createdUser.name);
    expect(restoredUser?.phoneNumber, createdUser.phoneNumber);
    expect(restoredUser?.about, createdUser.about);
    expect(restoredUser?.avatarLabel, createdUser.avatarLabel);
    expect(
      restoredUser?.accentColor.toARGB32(),
      createdUser.accentColor.toARGB32(),
    );
  });

  test('sign out clears the persisted session but keeps the account known',
      () async {
    final repository = FakeAuthRepository(
      latency: Duration.zero,
      persistSession: true,
    );

    await repository.requestOtp('+819012345678');
    await repository.verifyOtp(
      phoneNumber: '+819012345678',
      code: '123456',
    );
    await repository.completeProfile(
      phoneNumber: '+819012345678',
      name: 'Jay Devra',
      about: 'Testing the demo app.',
    );

    await repository.signOut();

    final afterSignOutRepository = FakeAuthRepository(
      latency: Duration.zero,
      persistSession: true,
    );
    expect(await afterSignOutRepository.restoreSession(), isNull);

    await afterSignOutRepository.requestOtp('+819012345678');
    final verifyResult = await afterSignOutRepository.verifyOtp(
      phoneNumber: '+819012345678',
      code: '123456',
    );
    expect(verifyResult.needsProfile, isFalse);
    expect(verifyResult.user?.name, 'Jay Devra');
  });
}
