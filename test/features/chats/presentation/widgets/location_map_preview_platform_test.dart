import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/chats/presentation/widgets/location_map_preview.dart';

/// Platform-branch coverage for [LocationMapCanvas]'s "Open in Maps" action.
///
/// `_handleOpenInMapsTap` used to branch on `dart:io`'s `Platform.isIOS`,
/// the compile-time host platform. `flutter test` runs on macOS or Linux
/// and `dart:io` offers no override seam for platform identity, so the iOS
/// side -- the provider sheet, the `maps.apple.com` URL, and the
/// dismissed-without-choosing path -- was unreachable from here at all. It
/// now branches on `defaultTargetPlatform`, which
/// `debugDefaultTargetPlatformOverride` drives, so both sides are covered.
///
/// Both directions are falsifiable: the Android tests assert no sheet
/// appears, the iOS tests assert it does.
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
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(urlLauncherChannel, null),
    );
  });

  /// Runs [body] as [platform], clearing the override before returning.
  ///
  /// It cannot be an addTearDown: testWidgets asserts that every foundation
  /// debug variable is unset at the end of the test *body*, and tearDown
  /// callbacks run after that check.
  Future<void> onPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

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

  Future<void> tapOpenInMaps(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const Key('attachment_viewer_open_in_maps_button')),
    );
    await tester.pumpAndSettle();
  }

  String? launchedUrl() {
    final launch = launchCalls.where((call) => call.method == 'launch');
    if (launch.isEmpty) {
      return null;
    }
    return (launch.last.arguments as Map)['url'] as String?;
  }

  testWidgets('Open in Maps goes straight to Google Maps off iOS',
      (tester) async {
    await onPlatform(TargetPlatform.android, () async {
      await pumpCanvas(tester);
      await tapOpenInMaps(tester);

      // No provider choice: that sheet is the iOS branch. These two
      // assertions are what make this branch coverage -- drop the platform
      // early return and the sheet appears here.
      expect(find.byKey(const Key('open_in_apple_maps_option')), findsNothing);
      expect(find.byKey(const Key('open_in_google_maps_option')), findsNothing);

      expect(
        launchedUrl(),
        'https://www.google.com/maps/search/?api=1&query=19.076,72.8777',
      );
    });
  });

  testWidgets('a refused launch surfaces the error dialog', (tester) async {
    await onPlatform(TargetPlatform.android, () async {
      launchSucceeds = false;
      await pumpCanvas(tester);
      await tapOpenInMaps(tester);

      expect(launchedUrl(), isNotNull);
      expect(
        find.text('We could not open Maps for that location.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('on iOS Open in Maps offers a provider choice first',
      (tester) async {
    await onPlatform(TargetPlatform.iOS, () async {
      await pumpCanvas(tester);
      await tapOpenInMaps(tester);

      expect(
          find.byKey(const Key('open_in_apple_maps_option')), findsOneWidget);
      expect(
          find.byKey(const Key('open_in_google_maps_option')), findsOneWidget);
      expect(
        launchCalls,
        isEmpty,
        reason: 'nothing opens until the user picks a provider',
      );
    });
  });

  testWidgets('on iOS picking Apple Maps launches maps.apple.com',
      (tester) async {
    await onPlatform(TargetPlatform.iOS, () async {
      await pumpCanvas(tester);
      await tapOpenInMaps(tester);
      await tester.tap(find.byKey(const Key('open_in_apple_maps_option')));
      await tester.pumpAndSettle();

      // The label is encoded rather than interpolated raw: it carries
      // spaces and a comma, which would otherwise break the query.
      expect(
        launchedUrl(),
        'https://maps.apple.com/?ll=19.076,72.8777'
        '&q=Bandra%20Kurla%20Complex%2C%20Mumbai',
      );
    });
  });

  testWidgets('on iOS picking Google Maps launches the Google URL',
      (tester) async {
    await onPlatform(TargetPlatform.iOS, () async {
      await pumpCanvas(tester);
      await tapOpenInMaps(tester);
      await tester.tap(find.byKey(const Key('open_in_google_maps_option')));
      await tester.pumpAndSettle();

      expect(
        launchedUrl(),
        'https://www.google.com/maps/search/?api=1&query=19.076,72.8777',
      );
    });
  });

  testWidgets('on iOS dismissing the sheet opens nothing', (tester) async {
    await onPlatform(TargetPlatform.iOS, () async {
      await pumpCanvas(tester);
      await tapOpenInMaps(tester);

      // The barrier above the sheet, not an option.
      await tester.tapAt(const Offset(196, 20));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('open_in_apple_maps_option')), findsNothing);
      expect(
        launchCalls,
        isEmpty,
        reason: 'selected == null must not fall through to a provider',
      );
    });
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
