import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/models/status_story.dart';

void main() {
  group('StatusDrawingStroke', () {
    test('round-trips through toJson/fromJson', () {
      const stroke = StatusDrawingStroke(
        points: <Offset>[Offset(0.1, 0.2), Offset(0.3, 0.4), Offset(0.5, 0.6)],
        colorValue: 0xFF00FF00,
        strokeWidth: 0.02,
      );

      final decoded = StatusDrawingStroke.fromJson(stroke.toJson());

      expect(decoded, isNotNull);
      expect(decoded!.points, stroke.points);
      expect(decoded.colorValue, stroke.colorValue);
      expect(decoded.strokeWidth, stroke.strokeWidth);
      expect(decoded.color, const Color(0xFF00FF00));
    });

    test('fromJson rejects malformed input', () {
      expect(StatusDrawingStroke.fromJson(null), isNull);
      expect(StatusDrawingStroke.fromJson(<String, Object?>{}), isNull);
      expect(
        StatusDrawingStroke.fromJson(<String, Object?>{
          'points': <Object?>[],
          'colorValue': 0xFFFFFFFF,
        }),
        isNull,
        reason: 'a stroke with no points is not a valid stroke',
      );
    });
  });

  group('StatusStorySegment.drawingStrokes', () {
    test('round-trips a segment carrying drawing strokes', () {
      final segment = StatusStorySegment(
        id: 'segment-1',
        type: StatusStoryType.photo,
        previewText: 'A doodled photo',
        localMediaPath: '/local/photo.jpg',
        drawingStrokes: const <StatusDrawingStroke>[
          StatusDrawingStroke(
            points: <Offset>[Offset(0, 0), Offset(1, 1)],
            colorValue: 0xFFFFFFFF,
            strokeWidth: 0.014,
          ),
        ],
      );

      final decoded = StatusStorySegment.fromJson(segment.toJson());

      expect(decoded, isNotNull);
      expect(decoded!.drawingStrokes, hasLength(1));
      expect(decoded.drawingStrokes.single.points, const <Offset>[
        Offset(0, 0),
        Offset(1, 1),
      ]);
      expect(decoded.drawingStrokes.single.colorValue, 0xFFFFFFFF);
    });

    test('defaults to no strokes when absent', () {
      const segment = StatusStorySegment(
        id: 'segment-2',
        type: StatusStoryType.text,
        previewText: 'No doodles here',
      );

      expect(segment.drawingStrokes, isEmpty);

      final decoded = StatusStorySegment.fromJson(segment.toJson());
      expect(decoded!.drawingStrokes, isEmpty);
    });
  });

  group('StatusMediaTransform.blurSigma', () {
    test('round-trips through toJson/fromJson', () {
      const transform = StatusMediaTransform(blurSigma: 6.5);

      final decoded = StatusMediaTransform.fromJson(transform.toJson());

      expect(decoded!.blurSigma, 6.5);
    });

    test('defaults to 0 (no blur)', () {
      const transform = StatusMediaTransform();
      expect(transform.blurSigma, 0);

      final decoded = StatusMediaTransform.fromJson(transform.toJson());
      expect(decoded!.blurSigma, 0);
    });

    test('copyWith updates only blurSigma', () {
      const transform = StatusMediaTransform(scale: 1.5, blurSigma: 2);
      final updated = transform.copyWith(blurSigma: 8);

      expect(updated.blurSigma, 8);
      expect(updated.scale, 1.5, reason: 'other fields must be preserved');
    });
  });

  group('StatusStorySegment.trimStartMillis', () {
    test('round-trips a trimmed video segment', () {
      const segment = StatusStorySegment(
        id: 'video-1',
        type: StatusStoryType.video,
        previewText: 'A trimmed clip',
        localMediaPath: '/local/video.mp4',
        durationMillis: 8000,
        trimStartMillis: 4000,
      );

      final decoded = StatusStorySegment.fromJson(segment.toJson());

      expect(decoded, isNotNull);
      expect(decoded!.trimStartMillis, 4000);
      expect(decoded.durationMillis, 8000);
    });

    test('defaults to 0 (no trim) when absent', () {
      const segment = StatusStorySegment(
        id: 'video-2',
        type: StatusStoryType.video,
        previewText: 'An untrimmed clip',
      );

      expect(segment.trimStartMillis, 0);

      final decoded = StatusStorySegment.fromJson(segment.toJson());
      expect(decoded!.trimStartMillis, 0);
    });
  });
}
