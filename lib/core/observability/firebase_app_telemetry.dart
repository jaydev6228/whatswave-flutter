import 'dart:collection';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'app_telemetry.dart';

/// Firebase-backed [AppTelemetry].
///
/// A decorator around [LocalAppTelemetry], not a replacement for it: every
/// call still updates the local in-memory breadcrumb ring buffer (so
/// `AppTelemetryScope`-consuming debug UI keeps working identically), and
/// additionally forwards errors to Crashlytics and screen views/interactions
/// to Analytics.
///
/// Safe to construct before `Firebase.initializeApp()` resolves --
/// `FirebaseCrashlytics.instance`/`FirebaseAnalytics.instance` are lazy
/// singleton getters that don't touch native code until a method is
/// actually called, and by the time any error/event fires here, bootstrap()
/// has already awaited Firebase's initialization.
///
/// Not yet wired: tagging crashes with the signed-in user's uid via
/// `FirebaseCrashlytics.instance.setUserIdentifier` -- would need a hook
/// into AuthController's success path, out of scope for this slice.
///
/// Known gap: crash reports upload to Crashlytics successfully (verified
/// manually via the "Send test crash" debug button), but show as
/// "unprocessed" in the console -- automatic dSYM upload is disabled
/// (`uploadDebugSymbols: false` in the gitignored firebase.json) because
/// `flutterfire configure`'s generated Xcode build phase assumes Swift
/// Package Manager checkouts live under
/// `DerivedData/<target>/SourcePackages/checkouts/`, which didn't hold on
/// this machine/Xcode version -- the script failed with "No such file or
/// directory" and blocked builds entirely. Manual dSYM upload (`flutterfire
/// upload-crashlytics-symbols` run by hand, or the `upload-symbols` script
/// FlutterFire ships) remains a viable fallback if symbolicated stack
/// traces are needed later.
class FirebaseAppTelemetry implements AppTelemetry {
  FirebaseAppTelemetry({LocalAppTelemetry? local})
      : _local = local ?? LocalAppTelemetry();

  final LocalAppTelemetry _local;

  @override
  UnmodifiableListView<AppTelemetryEvent> get breadcrumbs => _local.breadcrumbs;

  @override
  void recordScreenView(
    String screenName, {
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    _local.recordScreenView(screenName, attributes: attributes);
    FirebaseAnalytics.instance
        .logScreenView(
          screenName: _sanitizedName(screenName),
          parameters: _sanitizedParameters(attributes),
        )
        .catchError((_) {});
  }

  @override
  void recordInteraction(
    String name, {
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    _local.recordInteraction(name, attributes: attributes);
    FirebaseAnalytics.instance
        .logEvent(
          name: _sanitizedName(name),
          parameters: _sanitizedParameters(attributes),
        )
        .catchError((_) {});
  }

  @override
  void recordError(
    Object error,
    StackTrace stackTrace, {
    String source = 'app',
    bool fatal = false,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    _local.recordError(
      error,
      stackTrace,
      source: source,
      fatal: fatal,
      attributes: attributes,
    );
    FirebaseCrashlytics.instance
        .recordError(
          error,
          stackTrace,
          reason: source,
          fatal: fatal,
          information: <String>[
            for (final entry in attributes.entries)
              '${entry.key}=${entry.value}',
          ],
        )
        .catchError((_) {});
  }

  @override
  void dispose() {
    _local.dispose();
  }

  /// Analytics event/screen names must be alphanumeric + underscores,
  /// start with a letter, and be at most 40 characters.
  String _sanitizedName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final withLetterStart =
        RegExp(r'^[A-Za-z]').hasMatch(cleaned) ? cleaned : 'event_$cleaned';
    return withLetterStart.length > 40
        ? withLetterStart.substring(0, 40)
        : withLetterStart;
  }

  /// Analytics parameters must be non-null Strings/nums -- our attributes
  /// are already stringified by LocalAppTelemetry's sanitizer, but this
  /// repeats that defensively since it's a distinct API surface.
  Map<String, Object> _sanitizedParameters(Map<String, Object?> attributes) {
    final result = <String, Object>{};
    for (final entry in attributes.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      result[_sanitizedName(entry.key)] = value.toString();
    }
    return result;
  }
}
