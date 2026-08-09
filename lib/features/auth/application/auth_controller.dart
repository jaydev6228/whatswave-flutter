import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/models/app_user.dart';
import '../../../core/permissions/app_permission_service.dart';
import '../../../core/permissions/device_location_service.dart';
import '../../calls/domain/call_permissions.dart';
import '../data/auth_repository.dart';
import '../data/country_dial_codes.dart';
import '../data/device_country_lookup_service.dart';

enum AuthStep { splash, phoneEntry, otpEntry, profileSetup, authenticated }

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    this.defaultAbout = 'Available on WhatsWave.',
    String? localeCountryCode,
    AppPermissionService? permissionService,
    DeviceLocationService? locationService,
    DeviceCountryLookupService? countryLookupService,
  })  : _repository = repository,
        _selectedCountry = countryDialCodeForIso(localeCountryCode),
        _permissionService = permissionService ?? MemoryAppPermissionService(),
        _locationService = locationService ?? GeolocatorDeviceLocationService(),
        _countryLookupService =
            countryLookupService ?? NativeDeviceCountryLookupService();

  final AuthRepository _repository;
  final String defaultAbout;
  final AppPermissionService _permissionService;
  final DeviceLocationService _locationService;
  final DeviceCountryLookupService _countryLookupService;
  bool _hasUserPickedCountry = false;

  AuthStep _step = AuthStep.splash;
  bool _isBusy = false;
  String? _statusMessage;
  String? _errorMessage;
  String _phoneNumber = '';
  String _otpCode = '';
  String _displayName = '';
  String _about = 'Available on WhatsWave.';
  AppUser? _currentUser;
  bool _hasRestoredSession = false;
  CountryDialCode _selectedCountry;

  AuthStep get step => _step;
  bool get isBusy => _isBusy;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  String get phoneNumber => _phoneNumber;
  CountryDialCode get selectedCountry => _selectedCountry;
  List<CountryDialCode> get availableCountries => countryDialCodes;
  String get normalizedPhoneNumber =>
      _normalizePhoneNumber(_phoneNumber, _selectedCountry);
  String get otpCode => _otpCode;
  String get displayName => _displayName;
  String get about => _about;
  AppUser? get currentUser => _currentUser;

  String get maskedPhoneNumber => _maskPhoneNumber(normalizedPhoneNumber);
  bool get isAuthenticated =>
      _step == AuthStep.authenticated && _currentUser != null;

  String get profilePreviewLabel {
    final trimmedName = _displayName.trim();
    if (trimmedName.isEmpty) {
      final digits = normalizedPhoneNumber.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 2) {
        return digits.substring(digits.length - 2);
      }
      return 'WW';
    }

    final parts = trimmedName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length == 1) {
      final token = parts.first.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      return token.isEmpty
          ? 'WW'
          : token.substring(0, token.length >= 2 ? 2 : 1).toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<void> restoreSession() async {
    if (_hasRestoredSession) return;
    _hasRestoredSession = true;

    _setBusy(true);
    _clearFeedback(notify: false);
    notifyListeners();

    try {
      final restoredUser = await _repository.restoreSession();
      if (restoredUser != null) {
        _currentUser = restoredUser;
        _step = AuthStep.authenticated;
        _statusMessage = 'Welcome back, ${restoredUser.name}.';
      } else {
        _step = AuthStep.phoneEntry;
        _statusMessage = 'No saved session on this device yet.';
      }
    } on AuthException catch (error) {
      _step = AuthStep.phoneEntry;
      _errorMessage = error.message;
    } catch (_) {
      _step = AuthStep.phoneEntry;
      _errorMessage =
          'We could not restore your session. Please sign in again.';
    }

    _setBusy(false);
    notifyListeners();
  }

  void updatePhoneNumber(String value) {
    final parsed = _parsePhoneNumberInput(value);
    final didCountryChange = _selectedCountry != parsed.country;
    final hadFeedback = _errorMessage != null || _statusMessage != null;
    if (value.trim().startsWith('+')) {
      // Typing a number with an explicit "+<code>" prefix is itself a
      // country choice -- stop GPS detection from overriding it later.
      _hasUserPickedCountry = true;
    }
    if (!didCountryChange && _phoneNumber == parsed.nationalNumber) return;

    _phoneNumber = parsed.nationalNumber;
    _selectedCountry = parsed.country;
    _clearFeedback(notify: false);
    if (didCountryChange || hadFeedback) {
      notifyListeners();
    }
  }

  void updateCountryDialCode(CountryDialCode country) {
    _hasUserPickedCountry = true;
    if (_selectedCountry == country) return;
    _selectedCountry = country;
    _clearFeedback(notify: false);
    notifyListeners();
  }

  /// Upgrades the locale-based default set in the constructor with the
  /// device's actual GPS country, if the user hasn't already picked one
  /// themselves. Silent on any failure -- permission denied, GPS off, no
  /// geocoding result -- since this is a convenience default, not a
  /// required step; the locale-based guess (or the user's own choice)
  /// stands untouched if it fails.
  Future<void> detectCountryFromDeviceLocation() async {
    if (_hasUserPickedCountry) return;
    try {
      var status = await _permissionService.locationAccessStatus();
      if (status != CallPermissionStatus.granted) {
        status = await _permissionService.requestLocationAccess();
      }
      if (status != CallPermissionStatus.granted || _hasUserPickedCountry) {
        return;
      }

      final fix = await _locationService.getCurrentLocation();
      if (_hasUserPickedCountry) return;

      final isoCode = await _countryLookupService.isoCountryCodeFor(
        fix.latitude,
        fix.longitude,
      );
      if (isoCode == null || _hasUserPickedCountry) return;

      final detected = countryDialCodeForIso(isoCode);
      if (detected == _selectedCountry) return;
      _selectedCountry = detected;
      notifyListeners();
    } catch (_) {
      // Best-effort only -- keep whichever default is already in place.
    }
  }

  void updateOtpCode(String value) {
    if (_otpCode == value) return;
    _otpCode = value;
    _clearFeedback();
  }

  void updateDisplayName(String value) {
    if (_displayName == value) return;
    _displayName = value;
    _clearFeedback();
  }

  void updateAbout(String value) {
    if (_about == value) return;
    _about = value;
    _clearFeedback();
  }

  Future<void> requestOtp() async {
    final validationMessage = _validatePhoneNumber(_phoneNumber);
    if (validationMessage != null) {
      _errorMessage = validationMessage;
      notifyListeners();
      return;
    }

    final normalizedPhoneNumber = this.normalizedPhoneNumber;
    _setBusy(true);
    _clearFeedback(notify: false);
    notifyListeners();

    try {
      await _repository.requestOtp(normalizedPhoneNumber);
      _otpCode = '';
      _step = AuthStep.otpEntry;
      _statusMessage =
          'We sent a 6-digit code to ${_maskPhoneNumber(normalizedPhoneNumber)}.';
    } on AuthException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not send a code right now. Please try again.';
    }

    _setBusy(false);
    notifyListeners();
  }

  Future<void> resendOtp() async {
    if (_phoneNumber.trim().isEmpty) {
      _step = AuthStep.phoneEntry;
      _errorMessage = 'Enter your phone number first.';
      notifyListeners();
      return;
    }

    _setBusy(true);
    _clearFeedback(notify: false);
    notifyListeners();

    try {
      await _repository.requestOtp(normalizedPhoneNumber);
      _statusMessage = 'A new code was sent to $maskedPhoneNumber.';
    } on AuthException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not resend a code right now. Please try again.';
    }

    _setBusy(false);
    notifyListeners();
  }

  void editPhoneNumber() {
    _step = AuthStep.phoneEntry;
    _otpCode = '';
    _statusMessage = 'Update your number if needed.';
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> verifyOtp() async {
    final sanitizedCode = _otpCode.replaceAll(RegExp(r'\D'), '');
    if (sanitizedCode.length != 6) {
      _errorMessage = 'Enter the 6-digit code from your message.';
      notifyListeners();
      return;
    }

    _setBusy(true);
    _clearFeedback(notify: false);
    notifyListeners();

    try {
      final result = await _repository.verifyOtp(
        phoneNumber: normalizedPhoneNumber,
        code: sanitizedCode,
      );
      _otpCode = sanitizedCode;
      if (result.user != null) {
        _currentUser = result.user;
        _step = AuthStep.authenticated;
        _statusMessage = 'Welcome back, ${result.user!.name}.';
      } else {
        _step = AuthStep.profileSetup;
        _displayName = _displayName.trim();
        if (_about.trim().isEmpty) {
          _about = defaultAbout;
        }
        _statusMessage = 'Number verified. Finish your profile to continue.';
      }
    } on AuthException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not verify that code. Please try again.';
    }

    _setBusy(false);
    notifyListeners();
  }

  Future<void> completeProfile() async {
    final nameValidationMessage = _validateDisplayName(_displayName);
    if (nameValidationMessage != null) {
      _errorMessage = nameValidationMessage;
      notifyListeners();
      return;
    }

    final aboutValidationMessage = _validateAbout(_about);
    if (aboutValidationMessage != null) {
      _errorMessage = aboutValidationMessage;
      notifyListeners();
      return;
    }

    _setBusy(true);
    _clearFeedback(notify: false);
    notifyListeners();

    try {
      final user = await _repository.completeProfile(
        phoneNumber: normalizedPhoneNumber,
        name: _displayName.trim(),
        about: _about.trim(),
      );
      _currentUser = user;
      _step = AuthStep.authenticated;
      _statusMessage = 'Profile ready. Welcome to WhatsWave, ${user.name}.';
    } on AuthException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage =
          'We could not finish setting up your profile. Please try again.';
    }

    _setBusy(false);
    notifyListeners();
  }

  Future<bool> updateCurrentProfile({
    required String name,
    required String about,
  }) async {
    if (_currentUser == null) {
      _errorMessage = 'Sign in again before editing your profile.';
      notifyListeners();
      return false;
    }

    final nameValidationMessage = _validateDisplayName(name);
    if (nameValidationMessage != null) {
      _errorMessage = nameValidationMessage;
      notifyListeners();
      return false;
    }

    final aboutValidationMessage = _validateAbout(about);
    if (aboutValidationMessage != null) {
      _errorMessage = aboutValidationMessage;
      notifyListeners();
      return false;
    }

    _setBusy(true);
    _clearFeedback(notify: false);
    notifyListeners();

    var didSucceed = false;
    try {
      final user = await _repository.updateCurrentProfile(
        name: name.trim(),
        about: about.trim(),
      );
      _currentUser = user;
      _statusMessage = 'Profile updated.';
      didSucceed = true;
    } on AuthException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage =
          'We could not save your profile changes. Please try again.';
    }

    _setBusy(false);
    notifyListeners();
    return didSucceed;
  }

  Future<bool> updateAvatar(File photo) async {
    if (_currentUser == null) {
      _errorMessage = 'Sign in again before editing your profile.';
      notifyListeners();
      return false;
    }

    _setBusy(true);
    _clearFeedback(notify: false);
    notifyListeners();

    var didSucceed = false;
    try {
      final user = await _repository.updateAvatar(photo);
      _currentUser = user;
      _statusMessage = 'Profile photo updated.';
      didSucceed = true;
    } on AuthException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not update your profile photo. Please try again.';
    }

    _setBusy(false);
    notifyListeners();
    return didSucceed;
  }

  Future<void> signOut() async {
    _setBusy(true);
    _clearFeedback(notify: false);
    notifyListeners();

    try {
      await _repository.signOut();
    } catch (_) {
      // Sign-out is a local, effectively infallible operation -- even if the
      // repository call fails, still drop local session state so the user
      // isn't stuck signed in on this device.
    }

    _currentUser = null;
    _phoneNumber = '';
    _otpCode = '';
    _displayName = '';
    _about = defaultAbout;
    _step = AuthStep.phoneEntry;
    _statusMessage = 'You have been signed out.';
    _setBusy(false);
    notifyListeners();
  }

  void clearFeedback() {
    _clearFeedback();
  }

  void _setBusy(bool value) {
    _isBusy = value;
  }

  void _clearFeedback({bool notify = true}) {
    final hadFeedback = _errorMessage != null || _statusMessage != null;
    _errorMessage = null;
    _statusMessage = null;
    if (notify && hadFeedback) {
      notifyListeners();
    }
  }

  String? _validatePhoneNumber(String value) {
    final trimmed = value.trim();
    final localDigits = trimmed.replaceAll(RegExp(r'\D'), '');
    final totalDigits = _selectedCountry.dialDigits.length + localDigits.length;
    if (trimmed.isEmpty) {
      return 'Enter your phone number to continue.';
    }
    if (totalDigits < 10 || localDigits.length < 6) {
      return 'Enter a full phone number for the selected country code.';
    }
    if (totalDigits > 15) {
      return 'That phone number looks too long. Check the digits and try again.';
    }
    return null;
  }

  String? _validateDisplayName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Add a display name so people know who is messaging them.';
    }
    if (trimmed.length < 2) {
      return 'Use at least 2 characters for your display name.';
    }
    return null;
  }

  String? _validateAbout(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Add a short about line for your profile.';
    }
    if (trimmed.length < 8) {
      return 'Make the about line a bit more descriptive.';
    }
    return null;
  }

  String _normalizePhoneNumber(String value, CountryDialCode country) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return '+${country.dialDigits}$digits';
  }

  String _maskPhoneNumber(String value) {
    if (value.isEmpty) return '';
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) {
      return value;
    }

    final visibleTail = digits.substring(digits.length - 4);
    final countryCodeLength = digits.length > 10 ? digits.length - 10 : 1;
    final maskedCountry = digits.substring(0, countryCodeLength);
    return '+$maskedCountry ${'•' * 4} $visibleTail';
  }

  ({CountryDialCode country, String nationalNumber}) _parsePhoneNumberInput(
    String value,
  ) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('+')) {
      return (country: _selectedCountry, nationalNumber: value);
    }

    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return (country: _selectedCountry, nationalNumber: '');
    }

    final country = countryDialCodeForPhoneDigits(
      digits,
      fallbackCountry: _selectedCountry,
    );
    final nationalNumber = digits.length > country.dialDigits.length
        ? digits.substring(country.dialDigits.length)
        : '';

    return (
      country: country,
      nationalNumber: nationalNumber,
    );
  }
}
