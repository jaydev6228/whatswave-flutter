import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';

/// Platform-branch coverage for [openAppPermissionSettings].
///
/// This used to branch on `dart:io`'s `Platform.isIOS`, which reads the
/// compile-time host platform: `flutter test` always runs on macOS or
/// Linux, `dart:io` exposes no override seam, and the iOS body was
/// therefore unreachable from any test on this suite's hosts. It now
/// branches on `defaultTargetPlatform`, so
/// `debugDefaultTargetPlatformOverride` drives both sides and all four
/// paths below are real coverage rather than one branch plus a comment.
void main() {
  const nativeChannel = MethodChannel('whatswave/app_settings');
  const permissionHandlerChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');

  late List<MethodCall> nativeCalls;
  late List<MethodCall> permissionHandlerCalls;

  /// What the iOS-only native channel does when called: `true` means it
  /// opened Settings itself, `false` means it could not, and throwing
  /// stands for the channel being absent.
  late Object? Function() nativeBehaviour;

  setUp(() {
    nativeCalls = <MethodCall>[];
    permissionHandlerCalls = <MethodCall>[];
    nativeBehaviour = () => true;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(nativeChannel, (call) async {
      nativeCalls.add(call);
      return nativeBehaviour();
    });
    messenger.setMockMethodCallHandler(permissionHandlerChannel, (call) async {
      permissionHandlerCalls.add(call);
      return true;
    });

    addTearDown(() {
      messenger.setMockMethodCallHandler(nativeChannel, null);
      messenger.setMockMethodCallHandler(permissionHandlerChannel, null);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  test('off iOS it uses permission_handler and never the native channel',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await openAppPermissionSettings();

    // Deleting the platform guard makes every platform take the iOS path,
    // which fails this.
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

  test('on iOS a successful native call short-circuits permission_handler',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    nativeBehaviour = () => true;

    await openAppPermissionSettings();

    expect(nativeCalls.map((call) => call.method), ['openAppSettings']);
    expect(
      permissionHandlerCalls,
      isEmpty,
      reason: 'the native sheet already opened; falling through would open '
          'Settings twice',
    );
  });

  test('on iOS a refused native call falls through to permission_handler',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    nativeBehaviour = () => false;

    await openAppPermissionSettings();

    expect(nativeCalls, hasLength(1));
    expect(
      permissionHandlerCalls.map((call) => call.method),
      ['openAppSettings'],
      reason: 'a false return means the native side did not open anything',
    );
  });

  test('on iOS a throwing native channel still opens settings', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    nativeBehaviour = () => throw MissingPluginException('no handler');

    await openAppPermissionSettings();

    expect(nativeCalls, hasLength(1));
    expect(
      permissionHandlerCalls.map((call) => call.method),
      ['openAppSettings'],
      reason: 'the catch must not swallow the whole call -- the user still '
          'needs a way into Settings',
    );
  });

  test('NativeAppPermissionService.openSettings routes to the same helper',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

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
