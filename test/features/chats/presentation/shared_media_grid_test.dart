import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';
import 'package:whatswave/features/chats/presentation/shared_media_screen.dart';

import '../../../support/device_matrix.dart';

List<ChatAttachment> _attachments(int count) {
  return List.generate(count, (index) {
    // Alternating so the video assertions have a real neighbour to sit
    // next to, the way a mixed thread's media actually arrives.
    final isVideo = index.isOdd;
    return ChatAttachment(
      id: 'media-$index',
      type: isVideo ? ChatAttachmentType.video : ChatAttachmentType.photo,
      title: isVideo ? 'Video $index' : 'Photo $index',
      details: 'Yesterday',
      tintColor: const Color(0xFF128C7E),
    );
  });
}

Future<void> _pumpGrid(
  WidgetTester tester, {
  required Size surfaceSize,
  int count = 24,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: SharedMediaScreen(
        attachments: _attachments(count),
        threadName: 'Ava',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _tile(int index) => find.byKey(Key('shared_media_media-$index'));

void main() {
  testWidgets('shared media tiles are flush squares with no corner radius',
      (tester) async {
    await _pumpGrid(tester, surfaceSize: iphoneProProfile.size);

    expect(
      find.descendant(
        of: find.byType(SharedMediaThumbnail).first,
        matching: find.byWidgetPredicate(
          (widget) => widget is ClipRRect || widget is ClipPath,
        ),
      ),
      findsNothing,
      reason: 'a shared-media tile must not round or clip its corners',
    );

    // Flush: neighbouring tiles touch, no gutter between them.
    final first = tester.getRect(_tile(0));
    final second = tester.getRect(_tile(1));
    expect(second.left, first.right);
    expect(first.left, 0);
  });

  testWidgets('more tiles fit a phone width than the old three-column grid',
      (tester) async {
    for (final device in <TestDeviceProfile>[
      iphoneSeProfile,
      iphoneProProfile,
      androidSmallProfile,
      androidMediumProfile,
    ]) {
      await _pumpGrid(tester, surfaceSize: device.size);

      final tileWidth = tester.getSize(_tile(0)).width;
      final columns = (device.size.width / tileWidth).round();
      expect(
        columns,
        greaterThan(3),
        reason: '${device.name} should fit more than the old 3 columns',
      );
      // The old layout: (width - 8 padding - 8 spacing) / 3.
      final oldTileWidth = (device.size.width - 16) / 3;
      expect(
        tileWidth,
        lessThan(oldTileWidth),
        reason: '${device.name} tiles must be smaller than they used to be',
      );

      // Square tiles, so a smaller tile also means more rows on screen.
      expect(tester.getSize(_tile(0)).height, tileWidth);
    }
  });

  testWidgets('a video without a path shows only the type icon',
      (tester) async {
    await _pumpGrid(tester, surfaceSize: iphoneProProfile.size);

    final videoTile = _tile(1);
    final icons = find.descendant(of: videoTile, matching: find.byType(Icon));
    expect(
      icons,
      findsOneWidget,
      reason: 'missing media must not stack a play badge on the type icon',
    );
    expect(tester.widget<Icon>(icons).icon, Icons.videocam_outlined);
    expect(
      tester.getCenter(icons),
      tester.getCenter(videoTile),
    );

    // The photo tile next to it still reads as a photo.
    final photoIcons = find.descendant(
      of: _tile(0),
      matching: find.byType(Icon),
    );
    expect(photoIcons, findsOneWidget);
    expect(tester.widget<Icon>(photoIcons).icon, Icons.photo_outlined);
  });
}
