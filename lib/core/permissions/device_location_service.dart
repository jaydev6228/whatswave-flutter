import 'package:geolocator/geolocator.dart';

class DeviceLocationFix {
  const DeviceLocationFix({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class DeviceLocationException implements Exception {
  const DeviceLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class DeviceLocationService {
  Future<DeviceLocationFix> getCurrentLocation();
}

/// Real device GPS fix via `geolocator`. Permission is handled separately by
/// [AppPermissionService] before this is ever called -- this only fails on
/// genuinely device-level problems (location services turned off, timeout).
class GeolocatorDeviceLocationService implements DeviceLocationService {
  @override
  Future<DeviceLocationFix> getCurrentLocation() async {
    final servicesEnabled = await Geolocator.isLocationServiceEnabled();
    if (!servicesEnabled) {
      throw const DeviceLocationException(
        'Turn on location services to share your current location.',
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return DeviceLocationFix(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on LocationServiceDisabledException {
      throw const DeviceLocationException(
        'Turn on location services to share your current location.',
      );
    } catch (_) {
      throw const DeviceLocationException(
        'We could not get your current location. Try again in a moment.',
      );
    }
  }
}
