import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_media_source.dart';

void main() {
  late Directory tempDir;
  late File photo;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('decode_budget_test_');
    photo = File('${tempDir.path}/photo.png')
      ..writeAsBytesSync(
        File('test/fixtures/test_photo_landscape.png').readAsBytesSync(),
      );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('a thumbnail decodes at the size it is painted, not the camera\'s',
      () {
    // A phone-camera JPEG decoded at its full ~12 megapixels into a 125pt
    // bubble tile is roughly 48MB of ARGB for one thumbnail. A thread
    // showing a couple of albums did that a dozen times over, and the
    // decode work froze the UI thread long enough that the bubbles sat
    // empty and drags on the message list did nothing for seconds after
    // opening it.
    final thumbnail = imageProviderForStatusMediaPath(
      photo.path,
      maxDecodeWidth: 250,
    );
    expect(thumbnail, isA<ResizeImage>());
    expect((thumbnail! as ResizeImage).width, 250);
    // Never scaled up: a photo already smaller than the budget is left
    // exactly as it is.
    expect((thumbnail as ResizeImage).allowUpscaling, isFalse);
  });

  test('the full-size path is untouched', () {
    // The viewer and the status canvas show the real image -- downsampling
    // there would be a visible regression, not an optimisation.
    expect(imageProviderForStatusMediaPath(photo.path), isA<FileImage>());
  });

  test('real dimensions are read from the file header', () async {
    // The fixture is 40x24. Without this, ChatAttachment.aspectRatio keeps
    // its 1.25 default for every photo ever picked, so a portrait photo is
    // laid out in a landscape slot and cropped to it.
    expect(await encodedImageAspectRatio(photo.path), closeTo(40 / 24, 0.001));
    expect(await encodedImageAspectRatio('${tempDir.path}/nope.png'), isNull);
  });
}
