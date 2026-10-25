import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/chats/presentation/widgets/location_map_preview.dart';

/// Platform-branch coverage for [LocationMapCanvas]'s "Open in Maps" action.
///
/// READ THIS BEFORE ADDING AN "iOS" CASE HERE.
///
/// `_handleOpenInMapsTap` branches on `Platform.isIOS` -- `dart:io`'s
/// compile-time host platform, not `defaultTargetPlatform`. That distinction
/// matters: `debugDefaultTargetPlatformOverride` steers
/// `defaultTargetPlatform` and nothing else, so wrapping these tests in it
/// would swap Material for Cupertino page transitions and leave this branch
/// reading the host platform exactly as before -- a test that looks like
/// two-branch coverage while only ever running one branch.
///
/// `flutter test` runs on the host VM (macOS locally, Linux in CI), where
/// `Platform.isIOS` is `false`. `dart:io` exposes no override seam for
/// `Platform` (`IOOverrides` covers the file system and sockets, not the
/// platform identity), so the iOS side of this branch is unreachable here:
///
///   * the `showModalBottomSheet` provider choice (`_MapProviderSheet`,
///     `open_in_apple_maps_option` / `open_in_google_maps_option`),
///   * the `maps.apple.com/?ll=...&q=...` URL built by
///     `_launchProvider(_MapProvider.apple)`,
///   * the "sheet dismissed without a choice" path (`selected == null`).
///
/// Those need an integration test on an iOS simulator, or a switch to
/// `defaultTargetPlatform` in the widget itself.
///
/// Everything below is the Android/host branch plus the shared failure path,
/// and it is falsifiable: the tests assert no provider sheet appears, so
/// deleting the `if (!Platform.isIOS)` early return fails them.
void main() {
  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

  late List<MethodCall> launchCalls;
  late bool launchSucceeds;

  setUp(() {
    launchCalls = <MethodCall>[];
    launchSucceeds = true;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, (call) async {
      launchCalls.add(call);
      return switch (call.method) {
        'launch' => launchSucceeds,
        'canLaunch' => true,
        _ => null,
      };
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(urlLauncherChannel, null),
    );
  });

  /// The canvas needs a real viewport: `FlutterMap` sizes itself from its
  /// constraints, and the button is positioned against the bottom edge.
  ///
  /// Tiles are never fetched successfully -- `flutter_test` answers every
  /// HTTP request with a 400 -- which is fine, and deliberate: this is about
  /// the button's platform branch, not about tile decoding.
  Future<void> pumpCanvas(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(
          body: LocationMapCanvas(
            latitude: 19.076,
            longitude: 72.8777,
            label: 'Bandra Kurla Complex, Mumbai',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  String? launchedUrl() {
    final launch = launchCalls.where((call) => call.method == 'launch');
    if (launch.isEmpty) {
      return null;
    }
    return (launch.last.arguments as Map)['url'] as String?;
  }

  test('this suite runs on a non-iOS host, so only that branch is drivable',
      () {
    // The premise of every test below, asserted rather than assumed.
    expect(
      Platform.isIOS,
      isFalse,
      reason: 'flutter test runs on the host VM (macOS/Linux), never iOS',
    );
  });

  testWidgets('Open in Maps goes straight to Google Maps off iOS',
      (tester) async {
    await pumpCanvas(tester);

    await tester.tap(
      find.byKey(const Key('attachment_viewer_open_in_maps_button')),
    );
    await tester.pumpAndSettle();

    // No provider choice: that sheet is the iOS branch. These two assertions
    // are what make this branch coverage -- drop the `if (!Platform.isIOS)`
    // early return and the sheet appears here.
    expect(find.byKey(const Key('open_in_apple_maps_option')), findsNothing);
    expect(find.byKey(const Key('open_in_google_maps_option')), findsNothing);

    expect(
      launchedUrl(),
      'https://www.google.com/maps/search/?api=1&query=19.076,72.8777',
    );
  });

  testWidgets('a refused launch surfaces the error dialog', (tester) async {
    launchSucceeds = false;
    await pumpCanvas(tester);

    await tester.tap(
      find.byKey(const Key('attachment_viewer_open_in_maps_button')),
    );
    await tester.pumpAndSettle();

    expect(launchedUrl(), isNotNull);
    expect(find.text('We could not open Maps for that location.'),
        findsOneWidget);
  });

  testWidgets('the snippet preview has no platform branch to drive',
      (tester) async {
    // Included so the file covers the whole widget library it is named for:
    // LocationMapSnippet is the other export here and is pointedly
    // platform-agnostic -- it renders the same tree on every host.
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(
          body: SizedBox(
            width: 240,
            height: 140,
            child: LocationMapSnippet(latitude: 19.076, longitude: 72.8777),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(LocationMapSnippet), findsOneWidget);
    expect(launchCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
