class CountryDialCode {
  const CountryDialCode({
    required this.isoCode,
    required this.name,
    required this.dialCode,
  });

  final String isoCode;
  final String name;
  final String dialCode;

  String get dialDigits => dialCode.replaceAll('+', '');
}

const countryDialCodes = <CountryDialCode>[
  CountryDialCode(isoCode: 'US', name: 'United States', dialCode: '+1'),
  CountryDialCode(isoCode: 'CA', name: 'Canada', dialCode: '+1'),
  CountryDialCode(isoCode: 'AR', name: 'Argentina', dialCode: '+54'),
  CountryDialCode(isoCode: 'AU', name: 'Australia', dialCode: '+61'),
  CountryDialCode(isoCode: 'AT', name: 'Austria', dialCode: '+43'),
  CountryDialCode(isoCode: 'BD', name: 'Bangladesh', dialCode: '+880'),
  CountryDialCode(isoCode: 'BE', name: 'Belgium', dialCode: '+32'),
  CountryDialCode(isoCode: 'BR', name: 'Brazil', dialCode: '+55'),
  CountryDialCode(isoCode: 'CL', name: 'Chile', dialCode: '+56'),
  CountryDialCode(isoCode: 'CN', name: 'China', dialCode: '+86'),
  CountryDialCode(isoCode: 'CO', name: 'Colombia', dialCode: '+57'),
  CountryDialCode(isoCode: 'CZ', name: 'Czech Republic', dialCode: '+420'),
  CountryDialCode(isoCode: 'DK', name: 'Denmark', dialCode: '+45'),
  CountryDialCode(isoCode: 'EG', name: 'Egypt', dialCode: '+20'),
  CountryDialCode(isoCode: 'FI', name: 'Finland', dialCode: '+358'),
  CountryDialCode(isoCode: 'FR', name: 'France', dialCode: '+33'),
  CountryDialCode(isoCode: 'DE', name: 'Germany', dialCode: '+49'),
  CountryDialCode(isoCode: 'GR', name: 'Greece', dialCode: '+30'),
  CountryDialCode(isoCode: 'HK', name: 'Hong Kong', dialCode: '+852'),
  CountryDialCode(isoCode: 'HU', name: 'Hungary', dialCode: '+36'),
  CountryDialCode(isoCode: 'IN', name: 'India', dialCode: '+91'),
  CountryDialCode(isoCode: 'ID', name: 'Indonesia', dialCode: '+62'),
  CountryDialCode(isoCode: 'IE', name: 'Ireland', dialCode: '+353'),
  CountryDialCode(isoCode: 'IL', name: 'Israel', dialCode: '+972'),
  CountryDialCode(isoCode: 'IT', name: 'Italy', dialCode: '+39'),
  CountryDialCode(isoCode: 'JP', name: 'Japan', dialCode: '+81'),
  CountryDialCode(isoCode: 'KE', name: 'Kenya', dialCode: '+254'),
  CountryDialCode(isoCode: 'KR', name: 'South Korea', dialCode: '+82'),
  CountryDialCode(isoCode: 'MY', name: 'Malaysia', dialCode: '+60'),
  CountryDialCode(isoCode: 'MX', name: 'Mexico', dialCode: '+52'),
  CountryDialCode(isoCode: 'NL', name: 'Netherlands', dialCode: '+31'),
  CountryDialCode(isoCode: 'NZ', name: 'New Zealand', dialCode: '+64'),
  CountryDialCode(isoCode: 'NG', name: 'Nigeria', dialCode: '+234'),
  CountryDialCode(isoCode: 'NO', name: 'Norway', dialCode: '+47'),
  CountryDialCode(isoCode: 'PK', name: 'Pakistan', dialCode: '+92'),
  CountryDialCode(isoCode: 'PH', name: 'Philippines', dialCode: '+63'),
  CountryDialCode(isoCode: 'PL', name: 'Poland', dialCode: '+48'),
  CountryDialCode(isoCode: 'PT', name: 'Portugal', dialCode: '+351'),
  CountryDialCode(isoCode: 'RU', name: 'Russia', dialCode: '+7'),
  CountryDialCode(isoCode: 'SA', name: 'Saudi Arabia', dialCode: '+966'),
  CountryDialCode(isoCode: 'SG', name: 'Singapore', dialCode: '+65'),
  CountryDialCode(isoCode: 'ZA', name: 'South Africa', dialCode: '+27'),
  CountryDialCode(isoCode: 'ES', name: 'Spain', dialCode: '+34'),
  CountryDialCode(isoCode: 'SE', name: 'Sweden', dialCode: '+46'),
  CountryDialCode(isoCode: 'CH', name: 'Switzerland', dialCode: '+41'),
  CountryDialCode(isoCode: 'TH', name: 'Thailand', dialCode: '+66'),
  CountryDialCode(isoCode: 'TR', name: 'Turkey', dialCode: '+90'),
  CountryDialCode(
      isoCode: 'AE', name: 'United Arab Emirates', dialCode: '+971'),
  CountryDialCode(isoCode: 'GB', name: 'United Kingdom', dialCode: '+44'),
  CountryDialCode(isoCode: 'UA', name: 'Ukraine', dialCode: '+380'),
  CountryDialCode(isoCode: 'VN', name: 'Vietnam', dialCode: '+84'),
];

CountryDialCode countryDialCodeForIso(String? isoCode) {
  final normalizedIsoCode = isoCode?.trim().toUpperCase();
  if (normalizedIsoCode == null || normalizedIsoCode.isEmpty) {
    return countryDialCodes.first;
  }

  return countryDialCodes.firstWhere(
    (country) => country.isoCode == normalizedIsoCode,
    orElse: () => countryDialCodes.first,
  );
}

CountryDialCode countryDialCodeForPhoneDigits(
  String digits, {
  CountryDialCode? fallbackCountry,
}) {
  final matches = countryDialCodes
      .where((country) => digits.startsWith(country.dialDigits))
      .toList(growable: false);

  if (matches.isEmpty) {
    return fallbackCountry ?? countryDialCodes.first;
  }

  if (fallbackCountry != null &&
      matches
          .any((country) => country.dialDigits == fallbackCountry.dialDigits)) {
    return fallbackCountry;
  }

  matches.sort(
    (left, right) => right.dialDigits.length.compareTo(left.dialDigits.length),
  );
  return matches.first;
}
