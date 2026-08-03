/// Reduces a phone number to a best-effort matching key: digits only, and
/// just the trailing [trailingDigits] of them.
///
/// This is an approximation, not a proper E.164 parse -- it exists so a
/// device contact saved as "090-1234-5678" (no country code) can still
/// match a registered account stored as "+819012345678". The tradeoff is a
/// theoretical (very unlikely at 8+ digits) collision between two different
/// numbers that happen to share the same trailing digits. A production app
/// would want a real phone-number parsing library and country-aware
/// normalization instead.
String phoneMatchKey(String phoneNumber, {int trailingDigits = 8}) {
  final digitsOnly = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.length <= trailingDigits) {
    return digitsOnly;
  }
  return digitsOnly.substring(digitsOnly.length - trailingDigits);
}
