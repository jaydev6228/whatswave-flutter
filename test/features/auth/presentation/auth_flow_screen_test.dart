import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/auth/data/fake_auth_repository.dart';

import '../../../support/device_matrix.dart';

void main() {
  for (final device in deviceMatrix) {
    testWidgets(
      'shows the phone entry screen when no session is restored on ${device.name}',
      (tester) async {
        await pumpWhatsWaveAppForDevice(
          tester,
          device: device,
          authRepository: FakeAuthRepository(latency: Duration.zero),
        );

        expect(find.text('Welcome to WhatsWave'), findsOneWidget);
        expect(find.byKey(const Key('auth_phone_field')), findsOneWidget);
        expect(
            find.byKey(const Key('auth_country_code_field')), findsOneWidget);
        expect(find.text('No saved session yet'), findsOneWidget);
        expect(find.textContaining('Examples:'), findsNothing);
      },
    );
  }

  for (final device in compactDeviceMatrix) {
    testWidgets(
      'keeps the send code button visible above the fold on ${device.name}',
      (tester) async {
        await pumpWhatsWaveAppForDevice(
          tester,
          device: device,
          authRepository: FakeAuthRepository(latency: Duration.zero),
        );

        final buttonBottom = tester
            .getRect(find.byKey(const Key('auth_send_code_button')))
            .bottom;

        expect(
          buttonBottom,
          lessThanOrEqualTo(device.size.height),
          reason:
              '${device.name} should show the auth call-to-action without requiring an initial scroll.',
        );
      },
    );
  }

  testWidgets('completes the new-user onboarding flow into the shell', (
    tester,
  ) async {
    await pumpWhatsWaveAppForDevice(
      tester,
      device: iphoneProProfile,
      authRepository: FakeAuthRepository(latency: Duration.zero),
    );

    await tester.enterText(
      find.byKey(const Key('auth_phone_field')),
      '90 1234 5678',
    );
    await tester.ensureVisible(find.byKey(const Key('auth_send_code_button')));
    await tester.tap(find.byKey(const Key('auth_send_code_button')));
    await pumpUntilVisible(tester, find.text('Verify your number'));

    expect(find.text('Verify your number'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('auth_otp_field')), '123456');
    await tester.tap(find.byKey(const Key('auth_verify_code_button')));
    await pumpUntilVisible(tester, find.text('Set up your profile'));

    expect(find.text('Set up your profile'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('auth_name_field')), 'Jay Devra');
    await tester.enterText(
      find.byKey(const Key('auth_about_field')),
      'Building calm, reliable chat products one release at a time.',
    );
    await tester
        .ensureVisible(find.byKey(const Key('auth_finish_profile_button')));
    await tester.tap(find.byKey(const Key('auth_finish_profile_button')));
    await pumpUntilVisible(tester, find.text('Chats'));
    await pumpForAsyncUi(tester, total: const Duration(milliseconds: 500));

    expect(find.text('Chats'), findsWidgets);
    // Icon-only floating tab bar -- no visible "Settings" text label, just
    // an accessibility tooltip (see whatswave_app_test.dart).
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('shows an inline error when the OTP code is wrong',
      (tester) async {
    await pumpWhatsWaveAppForDevice(
      tester,
      device: androidMediumProfile,
      authRepository: FakeAuthRepository(latency: Duration.zero),
      authLocaleCountryCode: 'US',
    );

    await tester.enterText(
        find.byKey(const Key('auth_phone_field')), '415 555 1234');
    await tester.ensureVisible(find.byKey(const Key('auth_send_code_button')));
    await tester.tap(find.byKey(const Key('auth_send_code_button')));
    await pumpUntilVisible(tester, find.byKey(const Key('auth_otp_field')));

    await tester.enterText(find.byKey(const Key('auth_otp_field')), '111111');
    await tester.tap(find.byKey(const Key('auth_verify_code_button')));
    await pumpUntilVisible(
      tester,
      find.text(
        'That code looks wrong. Enter the 6-digit code we sent to continue.',
      ),
    );

    expect(
      find.text(
          'That code looks wrong. Enter the 6-digit code we sent to continue.'),
      findsOneWidget,
    );
    expect(find.text('Verify your number'), findsOneWidget);
  });

  testWidgets('shows an inline error when sending the OTP fails',
      (tester) async {
    await pumpWhatsWaveAppForDevice(
      tester,
      device: iphoneProProfile,
      authRepository: FakeAuthRepository(latency: Duration.zero),
    );

    await tester.enterText(
      find.byKey(const Key('auth_phone_field')),
      '90 1234 0000',
    );
    await tester.ensureVisible(find.byKey(const Key('auth_send_code_button')));
    await tester.tap(find.byKey(const Key('auth_send_code_button')));
    await pumpUntilVisible(
      tester,
      find.text(
        'We could not send a code to that number right now. Try again in a moment.',
      ),
    );

    expect(
      find.text(
        'We could not send a code to that number right now. Try again in a moment.',
      ),
      findsOneWidget,
    );
    expect(find.text('Phone number'), findsWidgets);
    expect(find.text('Verify your number'), findsNothing);
  });
}
