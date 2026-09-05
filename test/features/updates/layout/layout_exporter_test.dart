import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/layout/application/layout_exporter.dart';
import 'package:whatswave/features/updates/layout/data/layout_catalog.dart';

void main() {
  final outputDirectory = Directory(
    '${Directory.current.path}/test/.tmp_layout',
  )..createSync(recursive: true);
  final exporter = LayoutExporter(outputDirectory: outputDirectory);

  test('templateFor resolves the live catalog entry', () {
    final state = LayoutCatalog.initialState(templateId: 'hero_right');
    expect(exporter.templateFor(state).id, 'hero_right');
    expect(
      exporter.templateFor(
        LayoutCatalog.initialState(templateId: 'missing'),
      ).id,
      LayoutCatalog.templates.first.id,
    );
  });

  test('export throws when the canvas key is not mounted', () async {
    await expectLater(
      exporter.exportToTempFile(
        state: LayoutCatalog.initialState(),
        repaintBoundaryKey: GlobalKey(),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
