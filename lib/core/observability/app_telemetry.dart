import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum AppTelemetryEventType { screenView, interaction, error }

class AppTelemetryEvent {
  const AppTelemetryEvent({
    required this.type,
    required this.name,
    required this.timestamp,
    this.attributes = const <String, Object?>{},
  });

  final AppTelemetryEventType type;
  final String name;
  final DateTime timestamp;
  final Map<String, Object?> attributes;
}

abstract class AppTelemetry {
  UnmodifiableListView<AppTelemetryEvent> get breadcrumbs;

  void recordScreenView(
    String screenName, {
    Map<String, Object?> attributes = const <String, Object?>{},
  });

  void recordInteraction(
    String name, {
    Map<String, Object?> attributes = const <String, Object?>{},
  });

  void recordError(
    Object error,
    StackTrace stackTrace, {
    String source = 'app',
    bool fatal = false,
    Map<String, Object?> attributes = const <String, Object?>{},
  });

  void dispose() {}
}

class NoopAppTelemetry implements AppTelemetry {
  const NoopAppTelemetry();

  static const NoopAppTelemetry instance = NoopAppTelemetry();

  @override
  UnmodifiableListView<AppTelemetryEvent> get breadcrumbs =>
      UnmodifiableListView<AppTelemetryEvent>(const <AppTelemetryEvent>[]);

  @override
  void recordError(
    Object error,
    StackTrace stackTrace, {
    String source = 'app',
    bool fatal = false,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {}

  @override
  void recordInteraction(
    String name, {
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {}

  @override
  void recordScreenView(
    String screenName, {
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {}

  @override
  void dispose() {}
}

class LocalAppTelemetry extends ChangeNotifier implements AppTelemetry {
  LocalAppTelemetry({
    this.maxBreadcrumbs = 60,
    DateTime Function()? nowProvider,
    this.debugSink,
  }) : _now = nowProvider ?? DateTime.now;

  final int maxBreadcrumbs;
  final DateTime Function() _now;
  final void Function(AppTelemetryEvent event)? debugSink;
  final List<AppTelemetryEvent> _breadcrumbs = <AppTelemetryEvent>[];

  @override
  UnmodifiableListView<AppTelemetryEvent> get breadcrumbs =>
      UnmodifiableListView<AppTelemetryEvent>(_breadcrumbs);

  @override
  void recordScreenView(
    String screenName, {
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    _record(
      AppTelemetryEvent(
        type: AppTelemetryEventType.screenView,
        name: screenName,
        timestamp: _now(),
        attributes: _sanitizeAttributes(attributes),
      ),
    );
  }

  @override
  void recordInteraction(
    String name, {
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    _record(
      AppTelemetryEvent(
        type: AppTelemetryEventType.interaction,
        name: name,
        timestamp: _now(),
        attributes: _sanitizeAttributes(attributes),
      ),
    );
  }

  @override
  void recordError(
    Object error,
    StackTrace stackTrace, {
    String source = 'app',
    bool fatal = false,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    _record(
      AppTelemetryEvent(
        type: AppTelemetryEventType.error,
        name: fatal ? 'fatal_error' : 'error',
        timestamp: _now(),
        attributes: _sanitizeAttributes(
          <String, Object?>{
            'source': source,
            'fatal': fatal,
            'error': error.toString(),
            'stack': _summarizeStackTrace(stackTrace),
            ...attributes,
          },
        ),
      ),
    );
  }

  void _record(AppTelemetryEvent event) {
    if (_breadcrumbs.length == maxBreadcrumbs) {
      _breadcrumbs.removeAt(0);
    }
    _breadcrumbs.add(event);

    if (debugSink != null) {
      debugSink!(event);
    } else if (kDebugMode) {
      debugPrint(
        '[telemetry] ${event.type.name}:${event.name} ${event.attributes}',
      );
    }

    notifyListeners();
  }
}

class AppTelemetryScope extends InheritedWidget {
  const AppTelemetryScope({
    required this.telemetry,
    required super.child,
    super.key,
  });

  final AppTelemetry telemetry;

  static AppTelemetry? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppTelemetryScope>()
        ?.telemetry;
  }

  static AppTelemetry of(BuildContext context) {
    return maybeOf(context) ?? NoopAppTelemetry.instance;
  }

  @override
  bool updateShouldNotify(AppTelemetryScope oldWidget) {
    return oldWidget.telemetry != telemetry;
  }
}

Map<String, Object?> _sanitizeAttributes(Map<String, Object?> attributes) {
  return Map<String, Object?>.unmodifiable(
    attributes.map((key, value) => MapEntry(key, value?.toString())),
  );
}

String _summarizeStackTrace(StackTrace stackTrace) {
  final lines = stackTrace
      .toString()
      .trim()
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .take(5)
      .toList(growable: false);
  return lines.join(' | ');
}
