import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/models/app_user.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/core/permissions/device_location_service.dart';
import 'package:whatswave/features/auth/application/auth_controller.dart';
import 'package:whatswave/features/auth/data/auth_repository.dart';
import 'package:whatswave/features/auth/data/country_dial_codes.dart';
import 'package:whatswave/features/auth/data/device_country_lookup_service.dart';

void main() {
  group('AuthController', () {
    test('moves to phone entry when there is no restored session', () async {
      final controller = AuthController(repository: _TestAuthRepository());

      await controller.restoreSession();

      expect(controller.step, AuthStep.phoneEntry);
      expect(controller.statusMessage, 'No saved session on this device yet.');
      expect(controller.currentUser, isNull);
    });

    test('restores an existing session into the authenticated state', () async {
      const restoredUser = AppUser(
        name: 'Jay Devra',
        phoneNumber: '+819012345678',
        about: 'Ready to ship.',
        avatarLabel: 'JD',
        accentColor: Colors.green,
      );
      final repository = _TestAuthRepository(restoredUser: restoredUser);
      final controller = AuthController(repository: repository);

      await controller.restoreSession();

      expect(controller.isAuthenticated, isTrue);
      expect(controller.currentUser, restoredUser);
      expect(controller.statusMessage, 'Welcome back, Jay Devra.');
    });

    test('validates phone numbers before requesting OTP', () async {
      final repository = _TestAuthRepository();
      final controller = AuthController(
        repository: repository,
        localeCountryCode: 'JP',
      );
      controller.updatePhoneNumber('12345');

      await controller.requestOtp();

      expect(controller.step, AuthStep.splash);
      expect(
        controller.errorMessage,
        'Enter a full phone number for the selected country code.',
      );
      expect(repository.lastRequestedPhone, isNull);
    });

    test('auto-selects a country code from the provided locale', () {
      final controller = AuthController(
        repository: _TestAuthRepository(),
        localeCountryCode: 'JP',
      );

      expect(controller.selectedCountry.isoCode, 'JP');
      expect(controller.selectedCountry.dialCode, '+81');
    });

    test('requests OTP and transitions to verification', () async {
      final repository = _TestAuthRepository();
      final controller = AuthController(
        repository: repository,
        localeCountryCode: 'JP',
      );
      controller.updatePhoneNumber('90 1234 5678');

      await controller.requestOtp();

      expect(repository.lastRequestedPhone, '+819012345678');
      expect(controller.step, AuthStep.otpEntry);
      expect(controller.maskedPhoneNumber, '+81 •••• 5678');
    });

    test('shows repository request errors on the phone step', () async {
      final controller = AuthController(
        repository: _TestAuthRepository(
          requestOtpError:
              const AuthException('SMS delivery is paused right now.'),
        ),
        localeCountryCode: 'JP',
      )..updatePhoneNumber('90 1234 5678');

      await controller.requestOtp();

      expect(controller.step, AuthStep.splash);
      expect(controller.errorMessage, 'SMS delivery is paused right now.');
    });

    test('lets the user override the detected country code', () async {
      final repository = _TestAuthRepository();
      final controller = AuthController(
        repository: repository,
        localeCountryCode: 'JP',
      )
        ..updateCountryDialCode(countryDialCodeForIso('US'))
        ..updatePhoneNumber('415 555 1234');

      await controller.requestOtp();

      expect(controller.selectedCountry.isoCode, 'US');
      expect(repository.lastRequestedPhone, '+14155551234');
      expect(controller.maskedPhoneNumber, '+1 •••• 1234');
    });

    test('rejects short OTP values before hitting the repository', () async {
      final repository = _TestAuthRepository();
      final controller = AuthController(repository: repository)
        ..updatePhoneNumber('+819012345678')
        ..updateOtpCode('123');

      await controller.verifyOtp();

      expect(
        controller.errorMessage,
        'Enter the 6-digit code from your message.',
      );
      expect(repository.lastVerifiedCode, isNull);
    });

    test('routes known users straight into the authenticated state', () async {
      final repository = _TestAuthRepository(
        verifyResult: const AuthVerificationResult.authenticated(
          AppUser(
            name: 'Ava Patel',
            phoneNumber: '+14155551234',
            about: 'Designing calm products.',
            avatarLabel: 'AP',
            accentColor: Colors.blue,
          ),
        ),
      );
      final controller = AuthController(repository: repository)
        ..updateCountryDialCode(countryDialCodeForIso('US'))
        ..updatePhoneNumber('4155551234')
        ..updateOtpCode('123456');

      await controller.verifyOtp();

      expect(controller.isAuthenticated, isTrue);
      expect(controller.currentUser?.name, 'Ava Patel');
    });

    test('moves verified new users into profile setup', () async {
      final controller = AuthController(repository: _TestAuthRepository())
        ..updateCountryDialCode(countryDialCodeForIso('US'))
        ..updatePhoneNumber('4155551234')
        ..updateOtpCode('123456');

      await controller.verifyOtp();

      expect(controller.step, AuthStep.profileSetup);
      expect(
        controller.statusMessage,
        'Number verified. Finish your profile to continue.',
      );
    });

    test('shows repository verification errors on the OTP step', () async {
      final controller = AuthController(
        repository: _TestAuthRepository(
          verifyError:
              const AuthException('That code expired. Request a new one.'),
        ),
      )
        ..updateCountryDialCode(countryDialCodeForIso('US'))
        ..updatePhoneNumber('4155551234')
        ..updateOtpCode('123456');

      await controller.verifyOtp();

      expect(controller.step, AuthStep.splash);
      expect(controller.errorMessage, 'That code expired. Request a new one.');
    });

    test('validates profile fields and completes profile setup', () async {
      final repository = _TestAuthRepository();
      final controller = AuthController(repository: repository)
        ..updateCountryDialCode(countryDialCodeForIso('JP'))
        ..updatePhoneNumber('9012345678')
        ..updateOtpCode('123456');

      await controller.verifyOtp();
      controller
        ..updateDisplayName('J')
        ..updateAbout('Short');

      await controller.completeProfile();

      expect(
        controller.errorMessage,
        'Use at least 2 characters for your display name.',
      );

      controller
        ..updateDisplayName('Jay Devra')
        ..updateAbout('Building calm, reliable chat products.');

      await controller.completeProfile();

      expect(repository.completedName, 'Jay Devra');
      expect(controller.isAuthenticated, isTrue);
      expect(controller.currentUser?.name, 'Jay Devra');
    });

    test('surfaces restore and profile save errors from the repository',
        () async {
      final restoreController = AuthController(
        repository: _TestAuthRepository(
          restoreError: const AuthException('Restore failed.'),
        ),
      );

      await restoreController.restoreSession();

      expect(restoreController.step, AuthStep.phoneEntry);
      expect(restoreController.errorMessage, 'Restore failed.');

      final profileController = AuthController(
        repository: _TestAuthRepository(
          completeProfileError: const AuthException('Profile save failed.'),
        ),
      )
        ..updateCountryDialCode(countryDialCodeForIso('JP'))
        ..updatePhoneNumber('9012345678')
        ..updateOtpCode('123456');

      await profileController.verifyOtp();
      profileController
        ..updateDisplayName('Jay Devra')
        ..updateAbout('Building calm, reliable chat products.');

      await profileController.completeProfile();

      expect(profileController.step, AuthStep.profileSetup);
      expect(profileController.errorMessage, 'Profile save failed.');
    });

    test('updates the avatar and clears busy/error state on success', () async {
      const restoredUser = AppUser(
        name: 'Jay Devra',
        phoneNumber: '+819012345678',
        about: 'Ready to ship.',
        avatarLabel: 'JD',
        accentColor: Colors.green,
      );
      final controller = AuthController(
        repository: _TestAuthRepository(restoredUser: restoredUser),
      );
      await controller.restoreSession();
      expect(controller.currentUser?.avatarUrl, isNull);

      final didSucceed =
          await controller.updateAvatar(File('/fake/picked-photo.jpg'));

      expect(didSucceed, isTrue);
      expect(controller.isBusy, isFalse);
      expect(controller.errorMessage, isNull);
      expect(controller.currentUser?.avatarUrl, '/fake/picked-photo.jpg');
    });

    test(
        'surfaces a repository error and leaves the user unchanged on a '
        'failed avatar upload', () async {
      const restoredUser = AppUser(
        name: 'Jay Devra',
        phoneNumber: '+819012345678',
        about: 'Ready to ship.',
        avatarLabel: 'JD',
        accentColor: Colors.green,
      );
      final controller = AuthController(
        repository: _TestAuthRepository(
          restoredUser: restoredUser,
          updateAvatarError: const AuthException('Could not save that photo.'),
        ),
      );
      await controller.restoreSession();

      final didSucceed =
          await controller.updateAvatar(File('/fake/picked-photo.jpg'));

      expect(didSucceed, isFalse);
      expect(controller.isBusy, isFalse);
      expect(controller.errorMessage, 'Could not save that photo.');
      expect(controller.currentUser?.avatarUrl, isNull);
    });

    test('rejects an avatar update with nobody signed in', () async {
      final controller = AuthController(repository: _TestAuthRepository());

      final didSucceed =
          await controller.updateAvatar(File('/fake/picked-photo.jpg'));

      expect(didSucceed, isFalse);
      expect(
        controller.errorMessage,
        'Sign in again before editing your profile.',
      );
    });

    test('signs out and returns to phone entry', () async {
      const restoredUser = AppUser(
        name: 'Jay Devra',
        phoneNumber: '+819012345678',
        about: 'Ready to ship.',
        avatarLabel: 'JD',
        accentColor: Colors.green,
      );
      final repository = _TestAuthRepository(restoredUser: restoredUser);
      final controller = AuthController(repository: repository);
      await controller.restoreSession();
      expect(controller.isAuthenticated, isTrue);

      await controller.signOut();

      expect(repository.didSignOut, isTrue);
      expect(controller.isAuthenticated, isFalse);
      expect(controller.currentUser, isNull);
      expect(controller.step, AuthStep.phoneEntry);
      expect(controller.statusMessage, 'You have been signed out.');
    });

    test(
        'still clears local session state when the repository sign-out call fails',
        () async {
      const restoredUser = AppUser(
        name: 'Jay Devra',
        phoneNumber: '+819012345678',
        about: 'Ready to ship.',
        avatarLabel: 'JD',
        accentColor: Colors.green,
      );
      final repository = _TestAuthRepository(
        restoredUser: restoredUser,
        signOutError: const AuthException('Sign out failed.'),
      );
      final controller = AuthController(repository: repository);
      await controller.restoreSession();

      await controller.signOut();

      expect(controller.isAuthenticated, isFalse);
      expect(controller.currentUser, isNull);
      expect(controller.step, AuthStep.phoneEntry);
    });

    test('upgrades the locale-based country code with the GPS-detected one',
        () async {
      final controller = AuthController(
        repository: _TestAuthRepository(),
        localeCountryCode: 'US',
        permissionService: MemoryAppPermissionService(),
        locationService: const _FakeDeviceLocationService(
          fix: DeviceLocationFix(latitude: 35.6595, longitude: 139.7005),
        ),
        countryLookupService: const _FakeDeviceCountryLookupService(
          isoCode: 'JP',
        ),
      );
      expect(controller.selectedCountry.isoCode, 'US');

      await controller.detectCountryFromDeviceLocation();

      expect(controller.selectedCountry.isoCode, 'JP');
    });

    test('leaves the country code untouched when location permission is denied',
        () async {
      final controller = AuthController(
        repository: _TestAuthRepository(),
        localeCountryCode: 'US',
        permissionService:
            MemoryAppPermissionService(grantLocationOnRequest: false),
        locationService: const _FakeDeviceLocationService(
          fix: DeviceLocationFix(latitude: 35.6595, longitude: 139.7005),
        ),
        countryLookupService: const _FakeDeviceCountryLookupService(
          isoCode: 'JP',
        ),
      );

      await controller.detectCountryFromDeviceLocation();

      expect(controller.selectedCountry.isoCode, 'US');
      expect(controller.errorMessage, isNull);
    });

    test('does not override a country the user already picked themselves',
        () async {
      final controller = AuthController(
        repository: _TestAuthRepository(),
        localeCountryCode: 'US',
        permissionService: MemoryAppPermissionService(),
        locationService: const _FakeDeviceLocationService(
          fix: DeviceLocationFix(latitude: 35.6595, longitude: 139.7005),
        ),
        countryLookupService: const _FakeDeviceCountryLookupService(
          isoCode: 'JP',
        ),
      )..updateCountryDialCode(countryDialCodeForIso('GB'));

      await controller.detectCountryFromDeviceLocation();

      expect(controller.selectedCountry.isoCode, 'GB');
    });
  });
}

class _TestAuthRepository implements AuthRepository {
  _TestAuthRepository({
    this.restoredUser,
    this.restoreError,
    this.requestOtpError,
    this.verifyError,
    this.completeProfileError,
    this.signOutError,
    this.updateAvatarError,
    this.verifyResult = const AuthVerificationResult.profileRequired(),
  });

  final AppUser? restoredUser;
  final Object? restoreError;
  final AuthException? requestOtpError;
  final AuthException? verifyError;
  final AuthException? completeProfileError;
  final Object? signOutError;
  final AuthException? updateAvatarError;
  final AuthVerificationResult verifyResult;

  String? lastRequestedPhone;
  String? lastVerifiedPhone;
  String? lastVerifiedCode;
  String? completedPhone;
  String? completedName;
  String? completedAbout;
  bool didSignOut = false;

  @override
  Future<AppUser> completeProfile({
    required String phoneNumber,
    required String name,
    required String about,
  }) async {
    if (completeProfileError != null) {
      throw completeProfileError!;
    }

    completedPhone = phoneNumber;
    completedName = name;
    completedAbout = about;
    return AppUser(
      name: name,
      phoneNumber: phoneNumber,
      about: about,
      avatarLabel: 'JD',
      accentColor: Colors.green,
    );
  }

  @override
  Future<void> requestOtp(String phoneNumber) async {
    if (requestOtpError != null) {
      throw requestOtpError!;
    }
    lastRequestedPhone = phoneNumber;
  }

  @override
  Future<AppUser?> restoreSession() async {
    if (restoreError != null) {
      throw restoreError!;
    }
    return restoredUser;
  }

  @override
  Future<AuthVerificationResult> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    if (verifyError != null) {
      throw verifyError!;
    }
    lastVerifiedPhone = phoneNumber;
    lastVerifiedCode = code;
    return verifyResult;
  }

  @override
  Future<AppUser> updateCurrentProfile({
    required String name,
    required String about,
  }) async {
    return AppUser(
      name: name,
      phoneNumber: restoredUser?.phoneNumber ?? '+819012345678',
      about: about,
      avatarLabel: 'JD',
      accentColor: Colors.green,
    );
  }

  @override
  Future<AppUser> updateAvatar(File photo) async {
    if (updateAvatarError != null) {
      throw updateAvatarError!;
    }
    return AppUser(
      name: restoredUser?.name ?? 'JD',
      phoneNumber: restoredUser?.phoneNumber ?? '+819012345678',
      about: restoredUser?.about ?? '',
      avatarLabel: 'JD',
      accentColor: Colors.green,
      avatarUrl: photo.path,
    );
  }

  @override
  Future<AppUser> deleteAvatar() async {
    final currentUser = restoredUser ??
        AppUser(
          name: 'JD',
          phoneNumber: '+819012345678',
          about: '',
          avatarLabel: 'JD',
          accentColor: Colors.green,
        );
    return currentUser.copyWith(clearAvatarUrl: true);
  }

  @override
  Future<void> signOut() async {
    if (signOutError != null) {
      throw signOutError!;
    }
    didSignOut = true;
  }
}

class _FakeDeviceLocationService implements DeviceLocationService {
  const _FakeDeviceLocationService({this.fix});

  final DeviceLocationFix? fix;

  @override
  Future<DeviceLocationFix> getCurrentLocation() async => fix!;
}

class _FakeDeviceCountryLookupService implements DeviceCountryLookupService {
  const _FakeDeviceCountryLookupService({this.isoCode});

  final String? isoCode;

  @override
  Future<String?> isoCountryCodeFor(double latitude, double longitude) async {
    return isoCode;
  }
}
