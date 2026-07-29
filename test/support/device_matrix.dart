import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/whatswave_app.dart';
import 'package:whatswave/core/observability/app_telemetry.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/auth/data/auth_repository.dart';
import 'package:whatswave/features/chats/data/chat_repository.dart';
import 'package:whatswave/features/updates/data/updates_repository.dart';

class TestDeviceProfile {
  const TestDeviceProfile({
    required this.name,
    required this.size,
  });

  final String name;
  final Size size;
}

const iphoneSeProfile = TestDeviceProfile(
  name: 'iPhone SE (3rd generation)',
  size: Size(375, 667),
);

const iphoneProProfile = TestDeviceProfile(
  name: 'iPhone Pro class',
  size: Size(393, 852),
);

const androidSmallProfile = TestDeviceProfile(
  name: 'Android small phone',
  size: Size(360, 640),
);

const androidMediumProfile = TestDeviceProfile(
  name: 'Android medium phone',
  size: Size(412, 915),
);

const deviceMatrix = <TestDeviceProfile>[
  iphoneSeProfile,
  iphoneProProfile,
  androidSmallProfile,
  androidMediumProfile,
];

const compactDeviceMatrix = <TestDeviceProfile>[
  iphoneSeProfile,
  androidSmallProfile,
];

Future<void> pumpWhatsWaveAppForDevice(
  WidgetTester tester, {
  required TestDeviceProfile device,
  required AuthRepository authRepository,
  ChatRepository? chatRepository,
  UpdatesRepository? updatesRepository,
  String authLocaleCountryCode = 'JP',
  AppPermissionService? permissionService,
  AppTelemetry? telemetry,
}) async {
  await tester.binding.setSurfaceSize(device.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    WhatsWaveApp(
      authRepository: authRepository,
      chatRepository: chatRepository,
      updatesRepository: updatesRepository,
      permissionService: permissionService ?? MemoryAppPermissionService(),
      authLocaleCountryCode: authLocaleCountryCode,
      telemetry: telemetry,
    ),
  );
  await pumpForAsyncUi(tester);

  expect(
    tester.takeException(),
    isNull,
    reason: '${device.name} should render without framework exceptions.',
  );
}

Future<void> pumpForAsyncUi(
  WidgetTester tester, {
  Duration total = const Duration(milliseconds: 900),
}) async {
  await tester.pump();
  await tester.pump(total);
  await tester.pump(const Duration(milliseconds: 120));
}

Future<void> pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 120),
  int maxPumps = 30,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  throw TestFailure('Timed out waiting for a target widget to appear.');
}
