import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// Plays/stops the incoming-call ringtone. A seam so [CallsController] can
/// be unit tested without touching real platform audio, mirroring the
/// existing AppPermissionService/CallSignalingService injection pattern.
abstract class RingtonePlayer {
  void play();
  void stop();
}

/// Does nothing -- the default when no player is injected, exactly like
/// NoopAppTelemetry/MemoryAppPermissionService default CallsController's
/// other dependencies to something safe rather than the real platform-
/// touching implementation. whatswave_app.dart explicitly wires
/// [SystemRingtonePlayer] in for the real app; tests and any other
/// composition root that doesn't care about ringing get silence instead
/// of a MethodChannel call with no platform binding behind it.
class NoopRingtonePlayer implements RingtonePlayer {
  const NoopRingtonePlayer();

  @override
  void play() {}

  @override
  void stop() {}
}

/// Plays the device's own system ringtone -- respects the user's silent
/// mode/volume/vibrate settings automatically, unlike bundling a fixed
/// custom sound file that would always play at a hardcoded volume
/// regardless of those settings.
///
/// flutter_ringtone_player's `looping` option only takes effect on Android
/// (API >= 28), and its `stop()` is documented as Android-only too -- so
/// this can't just fire one looping play() call and trust stop() to cut it
/// off cross-platform. Instead CallsController re-triggers play() on a
/// repeating timer for as long as the call keeps ringing (see
/// _startRinging/_stopRinging) and simply stops scheduling further plays
/// once it's done; whatever's already sounding finishes naturally within a
/// couple of seconds on either platform.
class SystemRingtonePlayer implements RingtonePlayer {
  @override
  void play() {
    FlutterRingtonePlayer().play(
      android: AndroidSounds.ringtone,
      ios: IosSounds.electronic,
      looping: false,
      asAlarm: false,
    );
  }

  @override
  void stop() {
    FlutterRingtonePlayer().stop();
  }
}
