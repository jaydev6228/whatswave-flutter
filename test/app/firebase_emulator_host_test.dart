import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/bootstrap.dart';

void main() {
  test('Android reaches the host machine on 10.0.2.2, not loopback', () {
    // The emulator is a guest VM: 127.0.0.1 there is the guest, so this
    // getting flipped would leave the suite silently unreachable.
    expect(firebaseEmulatorHost(TargetPlatform.android), '10.0.2.2');
  });

  test('every other platform uses loopback', () {
    for (final platform in TargetPlatform.values) {
      if (platform == TargetPlatform.android) {
        continue;
      }
      expect(
        firebaseEmulatorHost(platform),
        '127.0.0.1',
        reason: platform.name,
      );
    }
  });
}
