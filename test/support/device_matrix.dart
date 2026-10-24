
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// 320pt wide is the narrowest viewport Flutter ships to on either store --
/// iPhone SE (1st gen) and the low-end Android phones that still make up a
/// large share of installs outside the US. It is where overflow shows up
/// first, and nothing in the suite rendered it before.
const smallestPhoneProfile = TestDeviceProfile(
  name: 'Smallest phone (320pt)',
  size: Size(320, 568),
);

const tabletProfile = TestDeviceProfile(
  name: 'Tablet',
  size: Size(768, 1024),
);

/// A text scale and brightness pairing. These are the two axes that break
/// layouts without changing the viewport, so a size-only matrix misses them.
/// 2.0 is Android's ceiling for the font-size slider; iOS AX5 goes higher
/// still, but 2.0 catches all but the most fragile rows.
class UiVariant {
  const UiVariant({
    required this.name,
    this.textScale = 1.0,
    this.brightness = Brightness.light,
    this.viewPadding = EdgeInsets.zero,
  });

  final String name;
  final double textScale;
  final Brightness brightness;

  /// Simulated notch and home indicator. A widget test has no insets at
  /// all by default, so 43 files using SafeArea were being swept against a
  /// device shape that does not exist. Two of the story-rendering bugs were
  /// exactly this: a layer inset by a notch sitting beside one that was not.
  final EdgeInsets viewPadding;

  @override
  String toString() => name;
}

const defaultVariant = UiVariant(name: 'default');
const largeTextVariant = UiVariant(name: 'text scale 2.0', textScale: 2.0);
const darkVariant = UiVariant(name: 'dark', brightness: Brightness.dark);

/// A Dynamic Island phone: 59pt of status bar, 34pt of home indicator.
const notchVariant = UiVariant(
  name: 'notch',
  viewPadding: EdgeInsets.only(top: 59, bottom: 34),
);

/// What every screen must survive. Two extremes of width crossed with the
/// variants that break layouts in place -- four cases per screen, which stays
/// fast enough to run on every push.
const layoutMatrix = <TestDeviceProfile>[
  smallestPhoneProfile,
  tabletProfile,
];

const layoutVariants = <UiVariant>[
  defaultVariant,
  largeTextVariant,
  darkVariant,
  notchVariant,
];

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

  const settingsChannel = MethodChannel('whatswave/app_settings');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    settingsChannel,
    (call) async {
      if (call.method == 'deviceRegionCode') {
        return authLocaleCountryCode;
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(settingsChannel, null),
  );

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

/// Renders [build]'s screen at every [layoutMatrix] size crossed with every
/// [layoutVariants] variant, and fails if any combination throws.
///
/// A RenderFlex overflow is reported through the same channel as any other
/// framework error, so `takeException` catches it -- including the overflows
/// that only appear at a large text scale, which a size-only sweep misses
/// entirely. That is the whole point of the variant axis: most layouts break
/// because the text grew, not because the screen narrowed.
///
/// [build] is called fresh for each combination rather than reused, because
/// a screen that holds controllers must not carry state between sizes.
Future<void> expectScreenSurvivesLayoutMatrix(
  WidgetTester tester, {
  required Widget Function() build,
  List<TestDeviceProfile> devices = layoutMatrix,
  List<UiVariant> variants = layoutVariants,
  Duration settle = const Duration(milliseconds: 900),
}) async {
  for (final device in devices) {
    for (final variant in variants) {
      await tester.binding.setSurfaceSize(device.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: device.size,
            textScaler: TextScaler.linear(variant.textScale),
            platformBrightness: variant.brightness,
            viewPadding: variant.viewPadding,
            padding: variant.viewPadding,
          ),
          child: Builder(builder: (_) => build()),
        ),
      );
      await pumpForAsyncUi(tester, total: settle);

      expect(
        tester.takeException(),
        isNull,
        reason: '${device.name} at ${variant.name} '
            '(${device.size.width.toInt()}x${device.size.height.toInt()}, '
            'text ${variant.textScale}x, ${variant.brightness.name}) '
            'did not render cleanly',
      );
    }
  }
}

/// Runs Flutter's four built-in accessibility guidelines against whatever is
/// currently pumped.
///
/// Separate from [expectScreenSurvivesLayoutMatrix] on purpose: the sweep
/// answers "does this lay out", this answers "can someone use it". Bolting
/// them together would mean a contrast failure reported as a layout failure,
/// and a single screen failing would hide the rest of its matrix.
///
/// Apple and Google both reject on these, so they are not advisory.
Future<void> expectScreenMeetsAccessibilityGuidelines(
  WidgetTester tester,
) async {
  final handle = tester.ensureSemantics();
  try {
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  } finally {
    handle.dispose();
  }
}
