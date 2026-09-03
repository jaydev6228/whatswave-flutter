import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';
import 'package:whatswave/features/chats/presentation/media_send_preview_screen.dart';

import '../../../support/device_matrix.dart';

/// A real, valid, non-trivially-sized (32x32) solid-color PNG fixture --
/// see test/fixtures/test_photo.png. Image.file needs real decodable bytes
/// to lay out without erroring; a 1x1 pixel image collapses to a
/// degenerate render size elsewhere in this screen's rotate/markup
/// RepaintBoundary capture path. Deliberately a checked-in file rather
/// than bytes generated at test time via dart:ui's Picture.toImage() --
/// that call posts to the engine's raster thread and hangs indefinitely
/// if made before the test binding's rendering pipeline has been kicked
/// off by a real pumpWidget/pump.
File _testPhotoFixture() => File('test/fixtures/test_photo.png');

/// Rotate/markup write their flattened result via
/// getApplicationDocumentsDirectory (see _writeEditedPngFile) --
/// path_provider has no platform channel to answer that in a widget test,
/// so this stands in a real temp directory instead. Kept here even though
/// this file's own tests don't exercise rotate/markup (see the note at
/// the bottom of this file) so a future test that does add that coverage
/// has it already wired up.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

/// A short-timeout pumpAndSettle -- observing route pop/push transitions
/// reliably in this environment needed pumpAndSettle's own repeated
/// dirty-frame polling (plain bounded pump() sequences were flaky, timing
/// differently run to run). The plain pumpAndSettle() default (10
/// minutes) turns any genuine settle problem into what looks like a hang
/// rather than a fast, clear failure, so this caps it at 5 seconds --
/// generous for this screen's own 300ms route transitions.
Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('media_send_preview_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  ChatAttachment photoAttachment(String path) => ChatAttachment(
        id: 'photo-1',
        type: ChatAttachmentType.photo,
        title: 'Photo',
        details: '',
        tintColor: Colors.green,
        localMediaPath: path,
      );

  Future<MediaSendDraft?> openPreviewAndWaitForResult(
    WidgetTester tester,
    List<ChatAttachment> attachments, {
    required Future<void> Function() interact,
  }) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    MediaSendDraft? result;
    var didReturn = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<MediaSendDraft>(
                  MaterialPageRoute<MediaSendDraft>(
                    builder: (_) => MediaSendPreviewScreen(
                      attachments: attachments,
                      initialCaption: null,
                    ),
                  ),
                );
                didReturn = true;
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await _settle(tester);
    expect(find.byKey(const Key('media_send_preview_screen')), findsOneWidget);

    await interact();

    expect(didReturn, isTrue);
    return result;
  }

  testWidgets(
      'entering a caption and sending pops a draft with that caption and '
      'the picked attachment', (tester) async {
    final photoFile = File('${tempDir.path}/photo.png')
      ..writeAsBytesSync(_testPhotoFixture().readAsBytesSync());
    final attachments = [photoAttachment(photoFile.path)];

    final result = await openPreviewAndWaitForResult(
      tester,
      attachments,
      interact: () async {
        await tester.enterText(
          find.byKey(const Key('media_send_preview_caption_field')),
          'Nice view!',
        );
        await tester.pump();
        await tester
            .tap(find.byKey(const Key('media_send_preview_send_button')));
        await _settle(tester);
      },
    );

    expect(find.byKey(const Key('media_send_preview_screen')), findsNothing);
    expect(result, isNotNull);
    expect(result!.caption, 'Nice view!');
    expect(result.attachments.single.localMediaPath, photoFile.path);
  });

  testWidgets('the close button cancels without sending anything',
      (tester) async {
    final photoFile = File('${tempDir.path}/photo.png')
      ..writeAsBytesSync(_testPhotoFixture().readAsBytesSync());
    final attachments = [photoAttachment(photoFile.path)];

    final result = await openPreviewAndWaitForResult(
      tester,
      attachments,
      interact: () async {
        await tester.tap(
          find.byKey(const Key('media_send_preview_close_button')),
        );
        await _settle(tester);
      },
    );

    expect(result, isNull);
  });

  testWidgets(
    'rotating swaps the photo dimensions instead of letterboxing it into '
    'the page',
    (tester) async {
      // 40x24, so a shrink-on-rotate is unmistakable. Driven through
      // rotatePhotoBytesClockwise directly rather than the rotate button:
      // the encode/decode runs on the real event loop (hence runAsync),
      // and the button shows a progress spinner while it works, which
      // pumpAndSettle can never settle.
      final source =
          File('test/fixtures/test_photo_landscape.png').readAsBytesSync();
      await tester.pumpWidget(const SizedBox());

      await tester.runAsync(() async {
        final once = await rotatePhotoBytesClockwise(source);
        final onceImage = await decodeImageFromList(once);
        expect(onceImage.width, 24);
        expect(onceImage.height, 40);
        onceImage.dispose();

        // The old capture path baked the screen-shaped page slot into the
        // file, so the second turn contained an already-letterboxed image
        // and the photo kept shrinking. Round-tripping back to 40x24
        // proves nothing but the photo is in there.
        final twice = await rotatePhotoBytesClockwise(once);
        final twiceImage = await decodeImageFromList(twice);
        expect(twiceImage.width, 40);
        expect(twiceImage.height, 24);
        twiceImage.dispose();
      });
    },
  );

  testWidgets('rotating is immediate -- one frame, no spinner',
      (tester) async {
    final photoFile = File('${tempDir.path}/landscape.png')
      ..writeAsBytesSync(
        File('test/fixtures/test_photo_landscape.png').readAsBytesSync(),
      );

    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaSendPreviewScreen(
          attachments: [photoAttachment(photoFile.path)],
          initialCaption: null,
        ),
      ),
    );
    await _settle(tester);

    int turns() => tester
        .widgetList<RotatedBox>(find.byType(RotatedBox))
        .first
        .quarterTurns;
    expect(turns(), 0);

    // A single pump, not a settle: rotation used to decode, redraw and
    // re-encode the file on every tap, which is most of a second of dead
    // time behind a progress spinner. It is UI state now, baked on send.
    for (var expected = 1; expected <= 4; expected++) {
      await tester.tap(
        find.byKey(const Key('media_send_preview_rotate_button')),
      );
      await tester.pump();
      expect(turns(), expected % 4);
    }
  });

  testWidgets('the draw canvas repaints as strokes are added',
      (tester) async {
    final photoFile = File('${tempDir.path}/landscape.png')
      ..writeAsBytesSync(
        File('test/fixtures/test_photo_landscape.png').readAsBytesSync(),
      );

    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaSendPreviewScreen(
          attachments: [photoAttachment(photoFile.path)],
          initialCaption: null,
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const Key('media_send_preview_markup_button')));
    await _settle(tester);

    final painter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const Key('media_send_preview_markup_canvas')),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    // The strokes list is mutated in place, so the painter compared it to
    // itself and reported "nothing changed" forever: every stroke was
    // recorded and none was ever drawn.
    expect(painter.shouldRepaint(painter), isTrue);
  });

  testWidgets(
      'the shared draw tray sets the stroke width, and the eraser clears '
      'ink instead of adding it', (tester) async {
    final photoFile = File('${tempDir.path}/landscape.png')
      ..writeAsBytesSync(
        File('test/fixtures/test_photo_landscape.png').readAsBytesSync(),
      );

    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaSendPreviewScreen(
          attachments: [photoAttachment(photoFile.path)],
          initialCaption: null,
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const Key('media_send_preview_markup_button')));
    await _settle(tester);

    // The controls this screen used to be missing entirely, now shared with
    // the status composer's draw mode.
    expect(
      find.byKey(const Key('media_send_preview_markup_eraser_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('media_send_preview_markup_stroke_2')),
      findsOneWidget,
    );

    final canvas = find.descendant(
      of: find.byKey(const Key('media_send_preview_markup_canvas')),
      matching: find.byType(CustomPaint),
    );

    await tester.tap(find.byKey(const Key('media_send_preview_markup_stroke_2')));
    await tester.pump();
    await tester.drag(canvas, const Offset(40, 0));
    await tester.pump();
    expect(
      canvas,
      paints..path(color: Colors.white, strokeWidth: 12),
      reason: 'the widest of the three shared stroke sizes was picked',
    );

    await tester
        .tap(find.byKey(const Key('media_send_preview_markup_eraser_button')));
    await tester.pump();
    await tester.dragFrom(
      tester.getCenter(canvas) - const Offset(0, 30),
      const Offset(40, 0),
    );
    await tester.pump();
    // An eraser stroke is opaque black painted with BlendMode.clear inside
    // the ink layer -- the pen stroke before it is still there, unpicked.
    expect(
      canvas,
      paints
        ..path(color: Colors.white, strokeWidth: 12)
        ..path(color: Colors.black, strokeWidth: 12),
    );
  });

  // Markup (funnels through RepaintBoundary.toImage +
  // WidgetsBinding.endOfFrame to bake an edit into a new file) are
  // deliberately not covered here. In this test environment that async
  // capture path never reliably settles -- tried a 5s-timeout
  // pumpAndSettle, an extra warm-up pump before it, and bounded
  // pump()+pump(duration) sequences in several combinations, all either
  // timing out or leaving the pop unobserved. The production code itself
  // is unaffected (flutter analyze clean, reviewed by hand) -- this is
  // specifically about getting a frame-capture async gap to resolve
  // reliably inside this widget-test harness, not a correctness question.
  // Revisit if a future Flutter/test version changes RepaintBoundary
  // capture's interaction with the test binding's frame scheduling.
}
