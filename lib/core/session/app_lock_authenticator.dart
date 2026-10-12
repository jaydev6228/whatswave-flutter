import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// How this device can prove it is really its owner.
enum AppLockMethod {
  faceId,
  fingerprint,
  biometric,
  devicePasscode,

  /// The device has no screen lock at all, so there is nothing to check
  /// against. See [AppLockAuthenticator] for what the app does then.
  unavailable;

  /// Label for the unlock affordance, e.g. "Unlock with Face ID".
  String get actionLabel => switch (this) {
        AppLockMethod.faceId => 'Unlock with Face ID',
        AppLockMethod.fingerprint => 'Unlock with fingerprint',
        AppLockMethod.biometric => 'Unlock with biometrics',
        AppLockMethod.devicePasscode => 'Unlock with device passcode',
        AppLockMethod.unavailable => 'Unlock app',
      };

  bool get isBiometric =>
      this == AppLockMethod.faceId ||
      this == AppLockMethod.fingerprint ||
      this == AppLockMethod.biometric;
}

/// Authenticates the person holding the device before the app lock opens.
///
/// An interface because the real implementation talks to a platform channel
/// that does not exist in a widget test, and because the lock screen's
/// behaviour -- auto-prompt, denial, retry -- is exactly the part worth
/// having tests for.
abstract class AppLockAuthenticator {
  /// What this device can actually check. Resolved per call rather than
  /// cached: the user can enrol or remove a biometric while the app is
  /// backgrounded, which is also when the lock engages.
  Future<AppLockMethod> availableMethod();

  /// True only on a positive, user-completed authentication. A cancel, a
  /// failure, a lockout or a missing platform all return false -- the app
  /// stays locked on anything short of success.
  Future<bool> authenticate({required String reason});
}

/// [AppLockAuthenticator] backed by the OS, via `local_auth`.
class LocalAuthAppLockAuthenticator implements AppLockAuthenticator {
  LocalAuthAppLockAuthenticator({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<AppLockMethod> availableMethod() async {
    try {
      if (!await _localAuth.isDeviceSupported()) {
        return AppLockMethod.unavailable;
      }
      if (!await _localAuth.canCheckBiometrics) {
        // A passcode/PIN/pattern with no enrolled biometric still counts --
        // authenticate() falls back to it because biometricOnly is false.
        return AppLockMethod.devicePasscode;
      }
      final enrolled = await _localAuth.getAvailableBiometrics();
      if (enrolled.contains(BiometricType.face)) {
        return AppLockMethod.faceId;
      }
      if (enrolled.contains(BiometricType.fingerprint)) {
        return AppLockMethod.fingerprint;
      }
      if (enrolled.isNotEmpty) {
        return AppLockMethod.biometric;
      }
      return AppLockMethod.devicePasscode;
    } on PlatformException {
      // Treated as "cannot check", never as "allow through".
      return AppLockMethod.unavailable;
    } on MissingPluginException {
      return AppLockMethod.unavailable;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // false so the device passcode is accepted as a fallback -- a user
          // whose finger is wet or who is wearing a mask must still be able
          // to get into their own messages.
          biometricOnly: false,
          // The lock engages when the app is backgrounded, and on iOS the
          // system prompt itself backgrounds the app. Without stickyAuth the
          // prompt is cancelled the moment it appears.
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
