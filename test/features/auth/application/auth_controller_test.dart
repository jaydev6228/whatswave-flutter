import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/models/app_user.dart';
import 'package:whatswave/features/auth/application/auth_controller.dart';
import 'package:whatswave/features/auth/data/auth_repository.dart';
import 'package:whatswave/features/auth/data/country_dial_codes.dart';

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

    test('still clears local session state when the repository sign-out call fails',
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
    this.verifyResult = const AuthVerificationResult.profileRequired(),
  });

  final AppUser? restoredUser;
  final Object? restoreError;
  final AuthException? requestOtpError;
  final AuthException? verifyError;
  final AuthException? completeProfileError;
  final Object? signOutError;
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
  Future<void> signOut() async {
    if (signOutError != null) {
      throw signOutError!;
    }
    didSignOut = true;
  }
}
