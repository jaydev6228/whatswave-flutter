import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/observability/app_telemetry.dart';

void main() {
  test('stringifies telemetry attributes for safe local breadcrumbs', () {
    final telemetry = LocalAppTelemetry(debugSink: (_) {});

    telemetry.recordInteraction(
      'call_speaker_toggled',
      attributes: <String, Object?>{
        'enabled': true,
        'attempts': 2,
      },
    );

    final event = telemetry.breadcrumbs.single;
    expect(event.name, 'call_speaker_toggled');
    expect(event.attributes['enabled'], 'true');
    expect(event.attributes['attempts'], '2');
  });

  test('keeps only the most recent breadcrumbs up to the configured cap', () {
    final telemetry = LocalAppTelemetry(
      maxBreadcrumbs: 2,
      debugSink: (_) {},
    );

    telemetry.recordScreenView('tab_chats');
    telemetry.recordInteraction('navigation_tab_selected');
    telemetry.recordError(
      StateError('boom'),
      StackTrace.fromString('line1\nline2\nline3\nline4\nline5\nline6'),
      source: 'test',
    );

    final breadcrumbs = telemetry.breadcrumbs;
    expect(breadcrumbs, hasLength(2));
    expect(
      breadcrumbs.map((event) => event.name).toList(growable: false),
      <String>['navigation_tab_selected', 'error'],
    );
    expect(breadcrumbs.last.attributes['source'], 'test');
  });
}
