import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_scroll_behavior.dart';
import 'package:whatswave/core/observability/app_telemetry.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/auth/data/fake_auth_repository.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/shell/presentation/app_shell.dart';

import '../support/device_matrix.dart';

void main() {
  group('navigationLabelScaleForWidth', () {
    test('uses a minimum scale on compact phones', () {
      expect(navigationLabelScaleForWidth(320), _closeTo(0.72));
      expect(navigationLabelScaleForWidth(300), _closeTo(0.72));
    });

    test('interpolates for mid-size phones and caps on wider devices', () {
      expect(navigationLabelScaleForWidth(375), _closeTo(0.86));
      expect(navigationLabelScaleForWidth(430), _closeTo(1));
      expect(navigationLabelScaleForWidth(460), _closeTo(1));
    });
  });

  for (final device in deviceMatrix) {
    testWidgets(
      'renders the main shell tabs and navigates to updates on ${device.name}',
      (tester) async {
        await pumpWhatsWaveAppForDevice(
          tester,
          device: device,
          authRepository: FakeAuthRepository(
            restoredUser: DemoData.currentUser,
            latency: Duration.zero,
          ),
          chatRepository: FakeChatRepository(latency: Duration.zero),
        );
        await pumpUntilVisible(tester, find.text('Chats'));

        expect(find.text('Chats'), findsWidgets);
        expect(find.text('Updates'), findsWidgets);
        expect(find.text('Communities'), findsWidgets);
        expect(find.text('Calls'), findsWidgets);
        expect(find.text('Settings'), findsWidgets);

        await tester.tap(find.text('Updates').last);
        await tester.pump(const Duration(milliseconds: 300));
        await pumpUntilVisible(
          tester,
          find.byKey(const Key('updates_my_status_card')),
        );

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('updates_my_status_card')), findsOneWidget);
        expect(
          find.byKey(const Key('updates_my_status_text_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('updates_my_status_media_button')),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('records shell telemetry for launch and tab switches',
      (tester) async {
    final telemetry = LocalAppTelemetry(debugSink: (_) {});

    await pumpWhatsWaveAppForDevice(
      tester,
      device: iphoneSeProfile,
      authRepository: FakeAuthRepository(
        restoredUser: DemoData.currentUser,
        latency: Duration.zero,
      ),
      chatRepository: FakeChatRepository(latency: Duration.zero),
      telemetry: telemetry,
    );
    await pumpUntilVisible(tester, find.text('Updates'));

    expect(
      telemetry.breadcrumbs.any((event) => event.name == 'tab_chats'),
      isTrue,
    );

    await tester.tap(find.text('Updates').last);
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntilVisible(
      tester,
      find.byKey(const Key('updates_my_status_card')),
    );

    final names = telemetry.breadcrumbs
        .map((event) => event.name)
        .toList(growable: false);
    expect(names, contains('navigation_tab_selected'));
    expect(names, contains('tab_updates'));
  });

  testWidgets('uses the app scroll behavior to avoid Android stretch overscroll',
      (tester) async {
    await pumpWhatsWaveAppForDevice(
      tester,
      device: androidMediumProfile,
      authRepository: FakeAuthRepository(
        restoredUser: DemoData.currentUser,
        latency: Duration.zero,
      ),
      chatRepository: FakeChatRepository(latency: Duration.zero),
    );
    await pumpUntilVisible(tester, find.text('Chats'));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.scrollBehavior, isA<WhatsWaveScrollBehavior>());

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        scrollBehavior: const WhatsWaveScrollBehavior(),
        home: Builder(
          builder: (context) {
            return ScrollConfiguration.of(context).buildOverscrollIndicator(
              context,
              const SizedBox(key: Key('overscroll_child')),
              const ScrollableDetails(direction: AxisDirection.down),
            );
          },
        ),
      ),
    );

    expect(find.byKey(const Key('overscroll_child')), findsOneWidget);
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expect(find.byType(GlowingOverscrollIndicator), findsNothing);
  });
}

Matcher _closeTo(double value) => closeTo(value, 0.01);
