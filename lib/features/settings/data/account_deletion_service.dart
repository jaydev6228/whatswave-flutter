import 'package:cloud_functions/cloud_functions.dart';

/// Erases the signed-in account, server-side.
///
/// This has to be a server call: the cascade spans collections a client is
/// not allowed to touch (another thread's participant list, a story's view
/// records) and ends by deleting the Firebase Auth user, which only the
/// Admin SDK can do. A client-side "deletion" would leave most of it behind.
abstract class AccountDeletionService {
  /// Throws [AccountDeletionException] if the account was not fully erased.
  Future<void> deleteAccount();
}

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);
  final String message;

  @override
  String toString() => message;
}

class FirebaseAccountDeletionService implements AccountDeletionService {
  FirebaseAccountDeletionService({FirebaseFunctions? functions})
      // Must match the region the function is deployed to; a callable
      // resolved against the default region 404s with a confusing
      // "not-found" rather than saying the region is wrong.
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseFunctions _functions;

  @override
  Future<void> deleteAccount() async {
    try {
      await _functions.httpsCallable('deleteAccount').call<void>();
    } on FirebaseFunctionsException catch (e) {
      throw AccountDeletionException(
        switch (e.code) {
          'unauthenticated' => 'Sign in again before deleting your account.',
          'deadline-exceeded' =>
            'Deletion is taking longer than expected. Some data may already '
                'be removed -- try again, it is safe to repeat.',
          _ => 'Could not delete your account (${e.code}). Nothing was '
              'changed; please try again.',
        },
      );
    } catch (_) {
      throw const AccountDeletionException(
        'Could not reach the server. Your account was not deleted.',
      );
    }
  }
}

/// Used by the seeded local backend and by widget tests, which have no
/// Functions instance to call.
class NoopAccountDeletionService implements AccountDeletionService {
  const NoopAccountDeletionService();

  @override
  Future<void> deleteAccount() async {}
}
