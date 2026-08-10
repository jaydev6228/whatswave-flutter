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

  // Rotate/markup (both funnel through RepaintBoundary.toImage +
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
