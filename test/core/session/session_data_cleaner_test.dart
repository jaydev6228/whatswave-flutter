import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/core/controllers/app_preferences_controller.dart';
import 'package:whatswave/core/session/session_data_cleaner.dart';
import 'package:whatswave/features/auth/application/auth_controller.dart';
import 'package:whatswave/features/auth/data/fake_auth_repository.dart';

void main() {
  group('SessionDataCleaner', () {
    test('wipes the signed-out user data a second account could inherit',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        // The two that actually matter: plaintext message history and the
        // user's own about text, both uid-scoped.
        'chat_inbox_cache_v1:uid-123': '{"threads":[{"name":"Alice"}]}',
        'firebase_auth_about_v1_uid-123': 'Busy at work',
        // Privacy choices that must not carry over to the next account.
        'app_preferences_read_receipts_enabled_v1': false,
        'app_preferences_status_audience_v1': 'nobody',
        'status_media_remote_cache_index_v1': '["https://example.com/a.jpg"]',
      });
      final preferences = await SharedPreferences.getInstance();
      final cacheManager = _RecordingCacheManager();

      await SessionDataCleaner(
        preferences: preferences,
        mediaCacheManager: cacheManager,
      ).clearSignedInUserData();

      expect(
        preferences.getKeys(),
        isEmpty,
        reason: 'every key belonging to the signed-out user should be gone',
      );
      expect(
        cacheManager.emptyCacheCallCount,
        1,
        reason: 'downloaded media bytes should be dropped too',
      );
    });

    test('keeps the theme, which is a device preference rather than user data',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_preferences_theme_mode_v1': 'dark',
        'chat_inbox_cache_v1:uid-123': '{"threads":[]}',
      });
      final preferences = await SharedPreferences.getInstance();

      await SessionDataCleaner(
        preferences: preferences,
        mediaCacheManager: _RecordingCacheManager(),
      ).clearSignedInUserData();

      expect(preferences.getString('app_preferences_theme_mode_v1'), 'dark');
      expect(preferences.getKeys(), hasLength(1));
    });

    test('a media cache that will not empty still leaves the store wiped',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'chat_inbox_cache_v1:uid-123': '{"threads":[]}',
      });
      final preferences = await SharedPreferences.getInstance();

      await SessionDataCleaner(
        preferences: preferences,
        mediaCacheManager: _ThrowingCacheManager(),
      ).clearSignedInUserData();

      expect(preferences.getKeys(), isEmpty);
    });
  });

  group('AppPreferencesController.resetToDefaults', () {
    test('drops the previous user values so they cannot be re-persisted',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_preferences_read_receipts_enabled_v1': false,
        'app_preferences_app_lock_enabled_v1': true,
      });
      final controller = AppPreferencesController(
        preferences: await SharedPreferences.getInstance(),
      );
      await controller.ensureLoaded();
      expect(controller.readReceiptsEnabled, isFalse);
      expect(controller.appLockEnabled, isTrue);

      controller.resetToDefaults();

      expect(controller.readReceiptsEnabled, isTrue);
      expect(controller.appLockEnabled, isFalse);
    });
  });

  group('AuthController sign-out ordering', () {
    test('runs the cleanup before signing out, while the uid still resolves',
        () async {
      // The whole point of the hook: the caches it clears are keyed by the
      // signed-in uid, so running it after sign-out would strand them.
      final order = <String>[];
      final controller = AuthController(
        repository: _OrderRecordingAuthRepository(order),
        onSignOutCleanup: () async => order.add('cleanup'),
      );

      await controller.signOut();

      expect(order, <String>['cleanup', 'signOut']);
    });

    test('still signs out when the cleanup fails', () async {
      final order = <String>[];
      final controller = AuthController(
        repository: _OrderRecordingAuthRepository(order),
        onSignOutCleanup: () async => throw Exception('disk is full'),
      );

      await controller.signOut();

      expect(order, <String>['signOut']);
      expect(controller.currentUser, isNull);
    });
  });
}

class _RecordingCacheManager implements BaseCacheManager {
  int emptyCacheCallCount = 0;

  @override
  Future<void> emptyCache() async => emptyCacheCallCount++;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingCacheManager implements BaseCacheManager {
  @override
  Future<void> emptyCache() async => throw Exception('cache is locked');

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OrderRecordingAuthRepository extends FakeAuthRepository {
  _OrderRecordingAuthRepository(this._order)
      : super(latency: Duration.zero);

  final List<String> _order;

  @override
  Future<void> signOut() async {
    _order.add('signOut');
    await super.signOut();
  }
}
