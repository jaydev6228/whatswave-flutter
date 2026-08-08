import 'package:geocoding/geocoding.dart';

abstract class DeviceCountryLookupService {
  Future<String?> isoCountryCodeFor(double latitude, double longitude);
}

/// Reverse-geocodes a GPS fix to an ISO country code via the platform's
/// native geocoder (CLGeocoder on iOS, the system Geocoder on Android).
/// Returns null on any failure -- this only ever feeds a best-effort
/// default, never a required step, so callers should treat null the same
/// as "no opinion" and keep whatever default they already had.
class NativeDeviceCountryLookupService implements DeviceCountryLookupService {
  @override
  Future<String?> isoCountryCodeFor(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return null;
      return placemarks.first.isoCountryCode;
    } catch (_) {
      return null;
    }
  }
}
