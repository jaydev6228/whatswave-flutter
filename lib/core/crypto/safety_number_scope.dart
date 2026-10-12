import 'package:flutter/widgets.dart';

import 'safety_number_service.dart';
import 'signal_store.dart';

/// Makes safety numbers reachable from any screen without threading the
/// crypto stack through five widgets.
///
/// Modelled on `AppTelemetryScope`. Absent in a seeded local build and in
/// widget tests, where [of] returns null and callers simply show nothing --
/// which is also the right behaviour for a contact whose key is unknown.
class SafetyNumberScope extends InheritedWidget {
  const SafetyNumberScope({
    required this.service,
    required this.localUid,
    required super.child,
    this.store,
    super.key,
  });

  final SafetyNumberService? service;

  /// Consulted for whether a contact's identity key has changed.
  final WhatsWaveSignalStore? store;

  /// The signed-in user. Half of every safety number.
  final String? localUid;

  static SafetyNumberScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SafetyNumberScope>();

  /// The digits for [remoteUid], or null when they cannot be produced.
  static Future<String?> numberFor(BuildContext context, String remoteUid) {
    final scope = of(context);
    final service = scope?.service;
    final localUid = scope?.localUid;
    if (service == null || localUid == null || localUid.isEmpty) {
      return Future<String?>.value();
    }
    return service.safetyNumber(localUid: localUid, remoteUid: remoteUid);
  }

  /// Whether [remoteUid]'s safety number changed since this device last
  /// saw it -- a reinstall, or an impersonation attempt. Only the user
  /// comparing numbers can tell which, so the app says so rather than
  /// deciding for them.
  static bool identityChanged(BuildContext context, String remoteUid) =>
      of(context)?.store?.hasIdentityChanged(remoteUid) ?? false;

  @override
  bool updateShouldNotify(SafetyNumberScope oldWidget) =>
      oldWidget.service != service ||
      oldWidget.localUid != localUid ||
      oldWidget.store != store;
}
