import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_scroll_behavior.dart';
import 'package:whatswave/core/observability/app_telemetry.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/auth/data/fake_auth_repository.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';

import '../support/device_matrix.dart';

void main() {
  for (final device in deviceMatrix) {
    testWidgets(
      'renders the main shell tabs and the Chats status strip on ${device.name}',
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

        // Icon-only floating tab bar now -- no visible text labels to find,
        // so destinations are identified by their accessibility tooltip
        // instead. Updates has no tab of its own anymore; its status strip
        // lives directly on the Chats screen (checked below).
        expect(find.byTooltip('Chats'), findsOneWidget);
        expect(find.byTooltip('Communities'), findsOneWidget);
        expect(find.byTooltip('Calls'), findsOneWidget);
        expect(find.byTooltip('Settings'), findsOneWidget);
        expect(find.byTooltip('Updates'), findsNothing);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('chats_status_mine')), findsOneWidget);
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
    await pumpUntilVisible(tester, find.text('Chats'));

    expect(
      telemetry.breadcrumbs.any((event) => event.name == 'tab_chats'),
      isTrue,
    );

    await tester.tap(find.byTooltip('Communities'));
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntilVisible(tester, find.text('Communities'));

    final names = telemetry.breadcrumbs
        .map((event) => event.name)
        .toList(growable: false);
    expect(names, contains('navigation_tab_selected'));
    expect(names, contains('tab_communities'));
  });

  testWidgets(
      'uses the app scroll behavior to avoid Android stretch overscroll',
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
