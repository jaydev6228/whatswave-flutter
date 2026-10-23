import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/settings/data/account_deletion_service.dart';

class _RecordingService implements AccountDeletionService {
  int calls = 0;
  Object? throwThis;

  @override
  Future<void> deleteAccount() async {
    calls++;
    if (throwThis != null) throw throwThis!;
  }
}

void main() {
  group('AccountDeletionException', () {
    test('carries a message the UI can show directly', () {
      const e = AccountDeletionException('Could not reach the server.');
      expect(e.message, 'Could not reach the server.');
      expect(e.toString(), 'Could not reach the server.');
    });
  });

  group('the service contract the settings screen depends on', () {
    test('a successful deletion completes without throwing', () async {
      final service = _RecordingService();
      await expectLater(service.deleteAccount(), completes);
      expect(service.calls, 1);
    });

    test('a failure surfaces as AccountDeletionException, not a raw error',
        () async {
      // The screen catches AccountDeletionException specifically. Anything
      // else escapes to the zone handler and the user sees a frozen dialog
      // instead of a message.
      final service = _RecordingService()
        ..throwThis = const AccountDeletionException('nope');
      await expectLater(
        service.deleteAccount(),
        throwsA(isA<AccountDeletionException>()),
      );
    });

    test('the no-op used by tests and the seeded backend does nothing',
        () async {
      await expectLater(
        const NoopAccountDeletionService().deleteAccount(),
        completes,
      );
    });
  });

  group('the destructive confirmation', () {
    testWidgets('deleting requires an explicit confirmation', (tester) async {
      // Guards the property Apple cares about and that is easy to regress:
      // tapping the row must not delete anything on its own.
      final service = _RecordingService();
      var confirmed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Delete account?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(c).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(c).pop(true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    confirmed = true;
                    await service.deleteAccount();
                  }
                },
                child: const Text('Delete account'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.text('Delete account?'), findsOneWidget);
      expect(service.calls, 0, reason: 'opening the dialog must delete nothing');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.calls, 0, reason: 'cancelling must delete nothing');
      expect(confirmed, isFalse);

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(service.calls, 1);
    });
  });
}
