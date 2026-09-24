import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/auth/data/country_dial_codes.dart';

void main() {
  test('uses the platform locale region when the language has no country', () {
    final country = countryDialCodeForDeviceLocale(
      localeCountryCodes: const [],
      platformLocaleName: 'en_JP',
    );

    expect(country.isoCode, 'JP');
    expect(country.dialCode, '+81');
  });

  test('prefers an explicit country code over a language-only locale', () {
    final country = countryDialCodeForDeviceLocale(
      preferredCountryCode: 'AR',
      localeCountryCodes: const ['US'],
      platformLocaleName: 'en_US',
    );

    expect(country.isoCode, 'AR');
    expect(country.dialCode, '+54');
  });

  test('parses hyphenated platform locale names', () {
    expect(isoCountryFromLocaleName('ja-JP'), 'JP');
    expect(isoCountryFromLocaleName('en'), isNull);
  });

  test('uses the Unicode region override as the device location', () {
    final country = countryDialCodeForDeviceLocale(
      preferredCountryCode: 'GB',
      localeCountryCodes: const ['GB'],
      platformLocaleName: 'en_GB@rg=jpzzzz',
    );

    expect(country.isoCode, 'JP');
    expect(country.dialCode, '+81');
    expect(isoCountryFromUnicodeRegionOverride('en-GB-u-rg-jpzzzz'), 'JP');
  });
}
