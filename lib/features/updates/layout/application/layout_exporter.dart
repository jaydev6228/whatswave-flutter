import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

import '../data/layout_catalog.dart';
import '../models/layout_models.dart';

/// Flattens the editable layout into a single JPEG ready for the existing
/// photo-status upload path.
class LayoutExporter {
  const LayoutExporter({this.outputDirectory});

  /// When set, export writes here instead of the system temp directory.
  final Directory? outputDirectory;

  Future<String> exportToTempFile({
    required LayoutComposerState state,
    required GlobalKey repaintBoundaryKey,
  }) async {
    final boundary = repaintBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null ||
        boundary.size.width <= 0 ||
        boundary.size.height <= 0) {
      throw StateError('Layout canvas is not ready to export.');
    }

    // Give [Image.file] slots a couple of frames to finish decoding before
    // we rasterize the canvas — exporting too early has thrown on device.
    await SchedulerBinding.instance.endOfFrame;
    await SchedulerBinding.instance.endOfFrame;

    final pixelRatio = kLayoutExportWidth / boundary.size.width;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Could not encode the layout image.');
      }

      final directory = outputDirectory ?? await getTemporaryDirectory();
      await directory.create(recursive: true);
      final file = File(
        '${directory.path}/layout_status_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        flush: true,
      );
      return file.path;
    } finally {
      image.dispose();
    }
  }

  /// Builds a fresh [LayoutComposerState] for export-time validation.
  LayoutTemplate templateFor(LayoutComposerState state) {
    return LayoutCatalog.templateById(state.templateId);
  }
}
