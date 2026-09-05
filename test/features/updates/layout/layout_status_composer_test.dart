import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:whatswave/features/updates/layout/models/layout_models.dart';
import 'package:whatswave/features/updates/layout/presentation/layout_status_composer_screen.dart';
import 'package:whatswave/features/updates/layout/presentation/widgets/layout_pickers.dart';

import '../../../support/device_matrix.dart';
import '../../../support/fake_image_picker_platform.dart';

Finder _slot(WidgetTester tester, int index) {
  final templateId = _state(tester).debugState.templateId;
  return find.byKey(ValueKey<String>('layout_slot_${templateId}_$index'));
}

LayoutStatusComposerScreenState _state(WidgetTester tester) {
  return tester.state<LayoutStatusComposerScreenState>(
    find.byType(LayoutStatusComposerScreen),
  );
}

Future<FakeImagePickerPlatform> _pumpComposer(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  FakeImagePickerPlatform? picker,
}) async {
  final platform = picker ?? FakeImagePickerPlatform();
  ImagePickerPlatform.instance = platform;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: const MaterialApp(
        home: LayoutStatusComposerScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return platform;
}

void main() {
  testWidgets('layout composer exposes template and mode controls', (tester) async {
    await _pumpComposer(tester);

    expect(find.byKey(const Key('layout_status_composer_screen')), findsOneWidget);
    expect(find.byKey(const Key('layout_template_picker')), findsOneWidget);
    expect(find.byKey(const Key('layout_mode_layouts')), findsOneWidget);
    expect(find.byKey(const Key('layout_mode_shapes')), findsOneWidget);
    expect(find.byKey(const Key('layout_composer_back')), findsOneWidget);
    expect(find.byKey(const Key('layout_composer_background_color')), findsOneWidget);
    expect(find.byKey(const Key('layout_composer_share')), findsOneWidget);
    expect(_state(tester).debugState.templateId, 'single');
    expect(_state(tester).debugBottomMode, LayoutBottomMode.layouts);
  });

  testWidgets('switching to shapes mode shows the shape rail and selects slot 0',
      (tester) async {
    await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_mode_shapes')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('layout_shape_picker')), findsOneWidget);
    expect(find.byKey(const Key('layout_template_picker')), findsNothing);
    expect(_state(tester).debugBottomMode, LayoutBottomMode.shapes);
    expect(_state(tester).debugState.selectedSlotIndex, 0);
  });

  testWidgets('tapping a layout only updates the canvas and never opens the gallery',
      (tester) async {
    final picker = await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_template_two_columns')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('layout_status_composer_screen')), findsOneWidget);
    expect(_state(tester).debugState.templateId, 'two_columns');
    expect(_state(tester).debugState.slots.length, 2);
    expect(_slot(tester,0), findsOneWidget);
    expect(_slot(tester,1), findsOneWidget);
    expect(picker.imageFromSourceCallCount, 0);
    expect(picker.multiImageCallCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera slot opens a single-photo picker, never multi-select',
      (tester) async {
    final picker = await _pumpComposer(tester);

    await tester.tap(_slot(tester,0));
    await tester.pumpAndSettle();

    expect(picker.imageFromSourceCallCount, 1);
    expect(picker.multiImageCallCount, 0);
    expect(_state(tester).debugState.slots.first.hasImage, isTrue);
    expect(_state(tester).debugState.slots.first.imagePath, '/fake/test-photo.jpg');
    expect(_state(tester).debugState.canShare, isTrue);
    expect(find.byKey(const Key('layout_slot_replace')), findsOneWidget);
    expect(find.byKey(const Key('layout_slot_remove')), findsOneWidget);
    expect(find.text('Drag to move · Pinch to zoom'), findsOneWidget);
  });

  testWidgets('replace uses single pick again and remove clears the slot',
      (tester) async {
    final picker = await _pumpComposer(tester);

    await tester.tap(_slot(tester,0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_slot_replace')));
    await tester.pumpAndSettle();

    expect(picker.imageFromSourceCallCount, 2);
    expect(picker.multiImageCallCount, 0);

    await tester.tap(find.byKey(const Key('layout_slot_remove')));
    await tester.pumpAndSettle();

    expect(_state(tester).debugState.slots.first.hasImage, isFalse);
    expect(_state(tester).debugState.canShare, isFalse);
    expect(find.byKey(const Key('layout_slot_replace')), findsNothing);
    expect(_state(tester).debugBottomMode, LayoutBottomMode.layouts);
  });

  testWidgets(
      'shapes mode opens gallery for empty slots and selects filled ones',
      (tester) async {
    final picker = await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_template_two_columns')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_mode_shapes')));
    await tester.pumpAndSettle();

    await tester.tap(_slot(tester,0));
    await tester.pumpAndSettle();
    await tester.tap(_slot(tester,1));
    await tester.pumpAndSettle();
    expect(picker.imageFromSourceCallCount, 2);
    expect(_state(tester).debugState.slots[1].hasImage, isTrue);

    await tester.tap(_slot(tester,0));
    await tester.pumpAndSettle();
    expect(picker.imageFromSourceCallCount, 2);
    expect(_state(tester).debugState.selectedSlotIndex, 0);

    await tester.tap(find.byKey(const Key('layout_shape_heart')));
    await tester.pumpAndSettle();
    expect(_state(tester).debugState.slots[0].shape, LayoutShapeId.heart);
    expect(_state(tester).debugState.slots[1].shape, LayoutShapeId.rectangle);
  });

  testWidgets('tapping a shape applies it without first adding a photo',
      (tester) async {
    final picker = await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_mode_shapes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_shape_circle')));
    await tester.pumpAndSettle();

    expect(_state(tester).debugState.slots.first.shape, LayoutShapeId.circle);
    expect(picker.imageFromSourceCallCount, 0);
    expect(picker.multiImageCallCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two-column layout fills the second slot after the first photo',
      (tester) async {
    final picker = await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_template_two_columns')));
    await tester.pumpAndSettle();

    await tester.tap(_slot(tester,0));
    await tester.pumpAndSettle();
    expect(_state(tester).debugState.slots[0].hasImage, isTrue);
    expect(_state(tester).debugState.slots[1].hasImage, isFalse);
    // Still on layouts so the user can keep filling the template.
    expect(_state(tester).debugBottomMode, LayoutBottomMode.layouts);

    await tester.tap(_slot(tester,1));
    await tester.pumpAndSettle();

    expect(picker.imageFromSourceCallCount, 2);
    expect(picker.multiImageCallCount, 0);
    expect(_state(tester).debugState.slots[1].hasImage, isTrue);
    expect(_state(tester).debugBottomMode, LayoutBottomMode.shapes);
  });

  testWidgets('canvas stays between top chrome and bottom dock', (tester) async {
    await _pumpComposer(tester);

    final screen = tester.getRect(
      find.byKey(const Key('layout_status_composer_screen')),
    );
    final host = tester.getRect(
      find.byKey(const Key('layout_composer_canvas_host')),
    );
    final canvas = tester.getRect(
      find.byKey(const Key('layout_composer_canvas')),
    );
    final dock = tester.getRect(find.byKey(const Key('layout_mode_layouts')));

    expect(host.top, greaterThan(screen.top + 40));
    expect(host.bottom, lessThan(dock.top - 4));
    expect(canvas.top, greaterThanOrEqualTo(host.top - 1));
    expect(canvas.bottom, lessThanOrEqualTo(host.bottom + 1));
  });

  testWidgets('share stays on the composer until a photo is in a slot',
      (tester) async {
    await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_composer_share')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('layout_status_composer_screen')), findsOneWidget);
    expect(_state(tester).debugState.canShare, isFalse);
  });

  testWidgets('share exports and pops a layout draft after a photo is added',
      (tester) async {
    late LayoutStatusComposerDraft? draft;
    final platform = FakeImagePickerPlatform();
    ImagePickerPlatform.instance = platform;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                draft = await Navigator.of(context).push<LayoutStatusComposerDraft>(
                  MaterialPageRoute<LayoutStatusComposerDraft>(
                    builder: (_) => LayoutStatusComposerScreen(
                      exportOverride: () async => '/tmp/layout_export.png',
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(_slot(tester,0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_composer_share')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('layout_status_composer_screen')), findsNothing);
    expect(draft, isNotNull);
    expect(draft!.exportedImagePath, '/tmp/layout_export.png');
  });

  testWidgets('background color sheet updates the canvas fill', (tester) async {
    await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_composer_background_color')));
    await tester.pumpAndSettle();
    expect(find.text('Background'), findsOneWidget);

    const black = Color(0xFF111111);
    await tester.tap(
      find.byKey(Key('layout_background_swatch_${black.toARGB32()}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Background'), findsNothing);
    expect(_state(tester).debugState.backgroundColorValue, black.toARGB32());
  });

  testWidgets('back leaves the composer', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ImagePickerPlatform.instance = FakeImagePickerPlatform();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const LayoutStatusComposerScreen(),
                  ),
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_composer_back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('layout_status_composer_screen')), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('layout and shape rails show the first catalog items',
      (tester) async {
    await _pumpComposer(tester, size: iphoneSeProfile.size);

    expect(find.byKey(const Key('layout_template_single')), findsOneWidget);
    expect(find.byKey(const Key('layout_template_two_columns')), findsOneWidget);

    await tester.tap(find.byKey(const Key('layout_mode_shapes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('layout_shape_rectangle')), findsOneWidget);
    expect(find.byKey(const Key('layout_shape_circle')), findsOneWidget);
  });

  testWidgets('narrow screen plus large text does not overflow the composer',
      (tester) async {
    await _pumpComposer(
      tester,
      size: iphoneSeProfile.size,
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('layout_status_composer_screen')), findsOneWidget);
    expect(find.byKey(const Key('layout_template_picker')), findsOneWidget);

    await tester.tap(find.byKey(const Key('layout_mode_shapes')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('layout_shape_picker')), findsOneWidget);

    await tester.tap(find.byKey(const Key('layout_composer_ratio')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('layout_ratio_square')), findsOneWidget);
  });

  testWidgets('switching back to layouts restores the template rail', (tester) async {
    await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_mode_shapes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_mode_layouts')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('layout_template_picker')), findsOneWidget);
    expect(find.byKey(const Key('layout_shape_picker')), findsNothing);
    expect(_state(tester).debugBottomMode, LayoutBottomMode.layouts);
  });

  testWidgets('preview mode hides chrome and tap restores it', (tester) async {
    await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_composer_preview')));
    await tester.pumpAndSettle();

    expect(_state(tester).debugChromeVisible, isFalse);
    expect(find.byKey(const Key('layout_composer_preview_overlay')), findsOneWidget);

    await tester.tap(find.byKey(const Key('layout_composer_preview_overlay')));
    await tester.pumpAndSettle();

    expect(_state(tester).debugChromeVisible, isTrue);
    expect(find.byKey(const Key('layout_template_picker')), findsOneWidget);
  });

  testWidgets('drag pans a filled slot even when another slot is selected',
      (tester) async {
    await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_template_three_rows')));
    await tester.pumpAndSettle();
    await tester.tap(_slot(tester,0));
    await tester.pumpAndSettle();
    await tester.tap(_slot(tester,1));
    await tester.pumpAndSettle();

    expect(_state(tester).debugState.slots[0].hasImage, isTrue);
    expect(_state(tester).debugState.selectedSlotIndex, 1);

    final beforeFocal = (
      _state(tester).debugState.slots[0].focalDx,
      _state(tester).debugState.slots[0].focalDy,
    );

    final gesture = await tester.startGesture(tester.getCenter(_slot(tester,0)));
    await tester.pump();
    await gesture.moveBy(const Offset(-50, 30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final after = _state(tester).debugState.slots[0];
    expect(
      after.focalDx != beforeFocal.$1 || after.focalDy != beforeFocal.$2,
      isTrue,
    );
    expect(_state(tester).debugState.selectedSlotIndex, 0);
  });

  testWidgets('vertical drag works on a short slot row', (tester) async {
    await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_template_two_rows')));
    await tester.pumpAndSettle();
    await tester.tap(_slot(tester,0));
    await tester.pumpAndSettle();

    final beforeDy = _state(tester).debugState.slots[0].focalDy;

    final gesture = await tester.startGesture(tester.getCenter(_slot(tester,0)));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      _state(tester).debugState.slots[0].focalDy,
      isNot(equals(beforeDy)),
    );
  });

  testWidgets('pinch zoom updates scale on a filled slot', (tester) async {
    await _pumpComposer(tester);

    await tester.tap(_slot(tester,0));
    await tester.pumpAndSettle();
    expect(_state(tester).debugState.slots[0].scale, 1);

    final center = tester.getCenter(_slot(tester,0));
    final gesture1 = await tester.startGesture(center - const Offset(20, 0));
    final gesture2 = await tester.startGesture(center + const Offset(20, 0));
    await tester.pump();
    await gesture1.moveBy(const Offset(-30, 0));
    await gesture2.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture1.up();
    await gesture2.up();
    await tester.pumpAndSettle();

    expect(_state(tester).debugState.slots[0].scale, greaterThan(1));
  });

  testWidgets('preview hides the empty-slot hints so it matches the post',
      (tester) async {
    await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_template_two_columns')));
    await tester.pumpAndSettle();
    await tester.tap(_slot(tester, 0));
    await tester.pumpAndSettle();

    expect(find.text('Tap to add'), findsOneWidget);

    await tester.tap(find.byKey(const Key('layout_composer_preview')));
    await tester.pumpAndSettle();

    expect(_state(tester).debugChromeVisible, isFalse);
    expect(find.text('Tap to add'), findsNothing);
  });

  testWidgets('canvas ratio picker reshapes the canvas and keeps photos',
      (tester) async {
    await _pumpComposer(tester);

    await tester.tap(_slot(tester, 0));
    await tester.pumpAndSettle();
    expect(_state(tester).debugState.ratio, LayoutCanvasRatio.story);

    final storySize = tester.getSize(
      find.byKey(const Key('layout_composer_canvas')),
    );
    expect(storySize.width / storySize.height, closeTo(9 / 16, 0.01));

    await tester.tap(find.byKey(const Key('layout_composer_ratio')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_ratio_square')));
    await tester.pumpAndSettle();

    expect(_state(tester).debugState.ratio, LayoutCanvasRatio.square);
    expect(_state(tester).debugState.slots.first.hasImage, isTrue);

    final squareSize = tester.getSize(
      find.byKey(const Key('layout_composer_canvas')),
    );
    expect(squareSize.width / squareSize.height, closeTo(1, 0.01));
  });

  testWidgets('share reports the chosen ratio so the viewer can match it',
      (tester) async {
    LayoutStatusComposerDraft? draft;
    ImagePickerPlatform.instance = FakeImagePickerPlatform();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                draft =
                    await Navigator.of(context).push<LayoutStatusComposerDraft>(
                  MaterialPageRoute<LayoutStatusComposerDraft>(
                    builder: (_) => LayoutStatusComposerScreen(
                      exportOverride: () async => '/tmp/layout_export.png',
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(_slot(tester, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_composer_ratio')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_ratio_portrait')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_composer_share')));
    await tester.pumpAndSettle();

    expect(draft?.aspectRatio, LayoutCanvasRatio.portrait.value);
  });

  testWidgets('switching layout keeps all filled photos and resets masks',
      (tester) async {
    await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_template_three_rows')));
    await tester.pumpAndSettle();
    await tester.tap(_slot(tester, 0));
    await tester.pumpAndSettle();
    await tester.tap(_slot(tester, 1));
    await tester.pumpAndSettle();
    await tester.tap(_slot(tester, 2));
    await tester.pumpAndSettle();

    expect(_state(tester).debugState.slots.where((s) => s.hasImage).length, 3);
    expect(_state(tester).debugBottomMode, LayoutBottomMode.shapes);

    await tester.tap(_slot(tester, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_shape_oval')));
    await tester.pumpAndSettle();
    expect(_state(tester).debugState.slots[0].shape, LayoutShapeId.oval);

    await tester.tap(find.byKey(const Key('layout_mode_layouts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_template_two_columns')));
    await tester.pumpAndSettle();

    final state = _state(tester).debugState;
    expect(state.templateId, 'two_columns');
    expect(state.slots.where((slot) => slot.hasImage).length, 2);
    expect(state.slots.every((slot) => slot.shape == LayoutShapeId.rectangle),
        isTrue);
    expect(_state(tester).debugBottomMode, LayoutBottomMode.layouts);
  });
}
