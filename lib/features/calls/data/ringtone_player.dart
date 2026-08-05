import 'dart:async';
import 'dart:io';

import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// Plays/stops the incoming-call ringtone. A seam so [CallsController] can
/// be unit tested without touching real platform audio, mirroring the
/// existing AppPermissionService/CallSignalingService injection pattern.
///
/// [play] is responsible for keeping the ringtone going continuously until
/// [stop] is called -- callers should not need to re-invoke [play] on a
/// timer themselves (see [SystemRingtonePlayer] for why that used to cut
/// the ringtone off after only a couple of seconds).
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
/// (API >= 28); on Android it plays the ringtone through to completion and
/// loops it natively, so a single `play()` call is enough. `looping` (and
/// `stop()`) aren't reliably honored on iOS, where the plugin instead plays
/// a short system sound effect -- there's no API here for looping a real,
/// full-length ringtone on iOS, so this approximates continuous ringing by
/// re-triggering that short effect on a repeating timer until [stop] is
/// called. Previously that repeat-timer approach was used on *both*
/// platforms, which on Android meant a fresh `play()` call (with
/// `looping: false`) restarted and cut off whatever was already sounding
/// every few seconds -- audibly choppy instead of a continuous ring.
class SystemRingtonePlayer implements RingtonePlayer {
  Timer? _iosRepeatTimer;

  @override
  void play() {
    _iosRepeatTimer?.cancel();
    _iosRepeatTimer = null;

    FlutterRingtonePlayer().play(
      android: AndroidSounds.ringtone,
      ios: IosSounds.electronic,
      looping: true,
      asAlarm: false,
    );

    if (!Platform.isAndroid) {
      _iosRepeatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        FlutterRingtonePlayer().play(
          ios: IosSounds.electronic,
          looping: true,
          asAlarm: false,
        );
      });
    }
  }

  @override
  void stop() {
    _iosRepeatTimer?.cancel();
    _iosRepeatTimer = null;
    FlutterRingtonePlayer().stop();
  }
}
