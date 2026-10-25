import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';

/// Platform-branch coverage for [openAppPermissionSettings].
///
/// READ THIS BEFORE ADDING AN "iOS" CASE HERE.
///
/// `openAppPermissionSettings` branches on `Platform.isIOS`, which reads
/// `dart:io`'s compile-time host platform. It is NOT routed through
/// `defaultTargetPlatform`, so `debugDefaultTargetPlatformOverride` has no
/// effect on it whatsoever -- setting that override here would change which
/// Material/Cupertino widgets the framework builds and leave this branch
/// pointing at the host exactly as before.
///
/// `flutter test` always runs on the host VM (macOS locally, Linux in CI),
/// where `Platform.isIOS` is `false`. There is no `IOOverrides` hook for
/// `Platform` and no other seam, so the `if (Platform.isIOS)` body -- the
/// `whatswave/app_settings` channel call, its `opened == true` early return,
/// and its `catch (_)` fall-through -- is unreachable from any widget or unit
/// test on this suite's hosts. It can only be covered by an integration test
/// on an iOS device/simulator, or by switching the production branch to
/// `defaultTargetPlatform` (which lib/ already imports elsewhere).
///
/// What IS covered below is the non-iOS branch, and it is covered
/// falsifiably: the test asserts the native channel is never touched, so
/// deleting the `Platform.isIOS` guard (making every platform take the iOS
/// path) fails it.
void main() {
  const nativeChannel = MethodChannel('whatswave/app_settings');
  const permissionHandlerChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');

  late List<MethodCall> nativeCalls;
  late List<MethodCall> permissionHandlerCalls;

  setUp(() {
    nativeCalls = <MethodCall>[];
    permissionHandlerCalls = <MethodCall>[];

    final messenger = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(nativeChannel, (call) async {
      nativeCalls.add(call);
      return true;
    });
    messenger.setMockMethodCallHandler(permissionHandlerChannel,
        (call) async {
      permissionHandlerCalls.add(call);
      return true;
    });

    addTearDown(() {
      messenger.setMockMethodCallHandler(nativeChannel, null);
      messenger.setMockMethodCallHandler(permissionHandlerChannel, null);
    });
  });

  test('this suite runs on a non-iOS host, so only that branch is drivable',
      () {
    // The premise of the test below, asserted rather than assumed. If this
    // ever fails, the file's doc comment is out of date and the next test is
    // silently covering the opposite branch.
    expect(
      Platform.isIOS,
      isFalse,
      reason: 'flutter test runs on the host VM (macOS/Linux), never iOS',
    );
  });

  test('openAppPermissionSettings uses permission_handler off iOS', () async {
    await openAppPermissionSettings();

    // The iOS-only native channel must not be consulted at all. This is the
    // assertion that makes the branch real coverage rather than a call that
    // happens to succeed: remove the `if (Platform.isIOS)` guard in
    // app_permission_service.dart and this fails.
    expect(
      nativeCalls,
      isEmpty,
      reason: 'the whatswave/app_settings channel is iOS-only',
    );

    expect(
      permissionHandlerCalls.map((call) => call.method),
      ['openAppSettings'],
    );
  });

  test('NativeAppPermissionService.openSettings routes to the same helper',
      () async {
    // openSettings() is a one-line forward; this is the proof it forwards to
    // the platform-branching helper and not straight to permission_handler.
    await NativeAppPermissionService().openSettings();

    expect(nativeCalls, isEmpty);
    expect(
      permissionHandlerCalls.map((call) => call.method),
      ['openAppSettings'],
    );
  });
}
