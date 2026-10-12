import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/chats/presentation/widgets/safety_number_card.dart';

import '../../../../support/device_matrix.dart';

Future<void> pumpCard(
  WidgetTester tester, {
  required Future<String?> safetyNumber,
  TestDeviceProfile device = iphoneProProfile,
  double textScale = 1.0,
  bool identityChanged = false,
}) async {
  await tester.binding.setSurfaceSize(device.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SafetyNumberCard(
              safetyNumber: safetyNumber,
              contactName: 'Bob',
              identityChanged: identityChanged,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const digits =
      '123451234512345123451234512345123451234512345123451234512345';

  testWidgets('shows the digits and says what to do with them',
      (tester) async {
    await pumpCard(tester, safetyNumber: Future<String?>.value(digits));

    expect(find.byKey(const Key('safety_number_card')), findsOneWidget);
    final shown = tester
        .widget<Text>(find.byKey(const Key('safety_number_digits')))
        .data!;
    expect(shown.replaceAll(RegExp(r'\s'), ''), digits);
    expect(
      find.textContaining('Compare these digits with Bob'),
      findsOneWidget,
      reason: 'a number nobody knows how to use verifies nothing',
    );
  });

  testWidgets('shows nothing when the contact has no key yet', (tester) async {
    await pumpCard(tester, safetyNumber: Future<String?>.value(null));
    expect(find.byKey(const Key('safety_number_card')), findsNothing);
  });

  testWidgets('shows nothing while still resolving', (tester) async {
    await pumpCard(tester, safetyNumber: Completer<String?>().future);
    expect(find.byKey(const Key('safety_number_card')), findsNothing);
  });

  testWidgets('warns when the safety number changed', (tester) async {
    // A changed key is either a reinstall or an impersonation, and nothing
    // in the protocol can tell them apart -- so the user is told, rather
    // than the app quietly trusting the new key.
    await pumpCard(
      tester,
      safetyNumber: Future<String?>.value(digits),
      identityChanged: true,
    );

    expect(
      find.byKey(const Key('safety_number_changed_warning')),
      findsOneWidget,
    );
    expect(find.textContaining('someone could be intercepting'),
        findsOneWidget);
  });

  testWidgets('shows no warning in the normal case', (tester) async {
    await pumpCard(tester, safetyNumber: Future<String?>.value(digits));
    expect(
      find.byKey(const Key('safety_number_changed_warning')),
      findsNothing,
    );
  });

  for (final device in compactDeviceMatrix) {
    testWidgets('survives a 200% text scale on ${device.name}',
        (tester) async {
      // 60 digits in groups plus three lines of explanation, on the
      // narrowest supported phone at the largest accessibility scale --
      // the combination docs/ui_layout_guidelines.md requires.
      await pumpCard(
        tester,
        safetyNumber: Future<String?>.value(digits),
        device: device,
        textScale: 2.0,
        // The warning is the longest copy on the card, so it is the real
        // overflow risk at this scale.
        identityChanged: true,
      );

      expect(tester.takeException(), isNull,
          reason: '${device.name} should render without overflow');
      expect(find.byKey(const Key('safety_number_card')), findsOneWidget);
    });
  }
}
