import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:whatswave/features/updates/layout/models/layout_models.dart';
import 'package:whatswave/features/updates/layout/presentation/layout_status_composer_screen.dart';
import 'package:whatswave/features/updates/layout/presentation/widgets/layout_pickers.dart';
import 'package:whatswave/features/updates/presentation/status_system_chrome.dart';

import '../../../support/device_matrix.dart';
import '../../../support/fake_image_picker_platform.dart';

Future<void> _reveal(WidgetTester tester, Key key, {required Key rail}) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    80,
    scrollable: find.descendant(
      of: find.byKey(rail),
      matching: find.byType(Scrollable),
    ),
  );
}

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
  EdgeInsets padding = EdgeInsets.zero,
  FakeImagePickerPlatform? picker,
}) async {
  final platform = picker ?? FakeImagePickerPlatform();
  ImagePickerPlatform.instance = platform;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  if (padding != EdgeInsets.zero) {
    tester.view.padding = FakeViewPadding(
      left: padding.left,
      top: padding.top,
      right: padding.right,
      bottom: padding.bottom,
    );
    tester.view.viewPadding = FakeViewPadding(
      left: padding.left,
      top: padding.top,
      right: padding.right,
      bottom: padding.bottom,
    );
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
  }

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        padding: padding,
        viewPadding: padding,
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

  testWidgets('status-bar scrim stays a short top fade, not a canvas tint',
      (tester) async {
    await _pumpComposer(tester);

    final scrim = tester.getRect(find.byType(StatusStoryEdgeScrim));
    final canvas = tester.getRect(find.byKey(const Key('layout_composer_canvas')));
    expect(scrim.top, 0);
    expect(scrim.height, lessThan(canvas.height * 0.25));
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
    expect(find.byKey(const Key('layout_slot_look_rail')), findsOneWidget);

    await tester.tap(find.byKey(const Key('layout_slot_look_border')));
    await tester.pumpAndSettle();
    expect(_state(tester).debugState.slots.first.look, LayoutSlotLook.border);
    expect(find.byKey(const Key('layout_slot_color_rail')), findsOneWidget);
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

    await _reveal(
      tester,
      const Key('layout_shape_heart'),
      rail: const Key('layout_shape_picker'),
    );
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
    expect(_state(tester).debugBottomMode, LayoutBottomMode.layouts);
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

  testWidgets('background custom rail recolours the canvas without closing',
      (tester) async {
    await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_composer_background_color')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('layout_background_color_rail')), findsOneWidget);

    final before = _state(tester).debugState.backgroundColorValue;
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const Key('layout_background_color_bar'))) +
          const Offset(80, 8),
    );
    await tester.pumpAndSettle();

    expect(find.text('Background'), findsOneWidget);
    expect(_state(tester).debugState.backgroundColorValue, isNot(before));
  });

  testWidgets('background sheet offers extra light swatches and a shade rail',
      (tester) async {
    await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_composer_background_color')));
    await tester.pumpAndSettle();

    const mint = Color(0xFFCAFFBF);
    expect(
      find.byKey(Key('layout_background_swatch_${mint.toARGB32()}')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('layout_background_shade_rail')), findsOneWidget);

    final before = _state(tester).debugState.backgroundColorValue;
    final shadeBar = tester.getRect(
      find.byKey(const Key('layout_background_shade_bar')),
    );
    await tester.tapAt(Offset(shadeBar.right - 16, shadeBar.center.dy));
    await tester.pumpAndSettle();

    expect(find.text('Background'), findsOneWidget);
    expect(_state(tester).debugState.backgroundColorValue, isNot(before));
  });

  testWidgets('the shade rail does not move the hue thumb', (tester) async {
    await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_composer_background_color')));
    await tester.pumpAndSettle();

    final hueBar = tester.getRect(
      find.byKey(const Key('layout_background_color_bar')),
    );
    await tester.tapAt(Offset(hueBar.left + 80, hueBar.center.dy));
    await tester.pumpAndSettle();

    final hueThumbBefore = tester.getCenter(
      find.byKey(const Key('layout_background_color_thumb')),
    );
    final shadeBar = tester.getRect(
      find.byKey(const Key('layout_background_shade_bar')),
    );
    await tester.tapAt(Offset(shadeBar.right - 16, shadeBar.center.dy));
    await tester.pumpAndSettle();

    expect(
      tester.getCenter(find.byKey(const Key('layout_background_color_thumb'))),
      hueThumbBefore,
    );
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

    await _reveal(
      tester,
      const Key('layout_template_three_rows'),
      rail: const Key('layout_template_picker'),
    );
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

  testWidgets(
      'full screen stays above the dock while editing and fills in preview',
      (tester) async {
    const padding = EdgeInsets.only(top: 47, bottom: 34);
    await _pumpComposer(tester, padding: padding);

    await tester.tap(find.byKey(const Key('layout_composer_ratio')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('layout_ratio_fullScreen')), findsOneWidget);
    expect(find.byKey(const Key('layout_ratio_landscape')), findsOneWidget);
    await tester.tap(find.byKey(const Key('layout_ratio_fullScreen')));
    await tester.pumpAndSettle();

    expect(_state(tester).debugState.ratio, LayoutCanvasRatio.fullScreen);
    final editingHost = tester.getRect(
      find.byKey(const Key('layout_composer_canvas_host')),
    );
    final editingCanvas = tester.getRect(
      find.byKey(const Key('layout_composer_canvas')),
    );
    final dock = tester.getRect(find.byKey(const Key('layout_mode_layouts')));
    expect(editingHost.bottom, lessThan(dock.top - 4));
    expect(editingCanvas.bottom, lessThanOrEqualTo(editingHost.bottom + 1));
    expect(editingCanvas.width / editingCanvas.height, closeTo(390 / 763, 0.01));

    final editingScaffold = tester.widget<Scaffold>(
      find.byKey(const Key('layout_status_composer_screen')),
    );
    expect(editingScaffold.backgroundColor, Colors.black);

    await tester.tap(find.byKey(const Key('layout_composer_preview')));
    await tester.pumpAndSettle();

    final previewHost = tester.getRect(
      find.byKey(const Key('layout_composer_canvas_host')),
    );
    final previewCanvas = tester.getRect(
      find.byKey(const Key('layout_composer_canvas')),
    );
    expect(previewHost.top, closeTo(0, 1));
    expect(previewHost.bottom, closeTo(844, 1));
    expect(previewCanvas.top, closeTo(47, 1));
    expect(previewCanvas.bottom, closeTo(844 - 34, 1));
    expect(previewCanvas.width / previewCanvas.height, closeTo(390 / 763, 0.01));
    expect(
      tester
          .widget<Scaffold>(
            find.byKey(const Key('layout_status_composer_screen')),
          )
          .backgroundColor,
      Colors.black,
    );
    expect(
      tester.widget<ColoredBox>(
        find.descendant(
          of: find.byKey(const Key('layout_composer_canvas_host')),
          matching: find.byType(ColoredBox),
        ).first,
      ).color,
      _state(tester).debugState.backgroundColor,
    );
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

  testWidgets(
      'share reports the safe-area collage and its fill colour for full screen',
      (tester) async {
    LayoutStatusComposerDraft? draft;
    const padding = EdgeInsets.only(top: 47, bottom: 34);
    ImagePickerPlatform.instance = FakeImagePickerPlatform();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          padding: padding,
          viewPadding: padding,
        ),
        child: MaterialApp(
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
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(_slot(tester, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_composer_ratio')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_ratio_fullScreen')));
    await tester.pumpAndSettle();
    final fill = _state(tester).debugState.backgroundColorValue;
    await tester.tap(find.byKey(const Key('layout_composer_share')));
    await tester.pumpAndSettle();

    expect(draft?.aspectRatio, closeTo(390 / 763, 0.01));
    expect(draft?.backgroundColorValue, fill);
  });

  testWidgets('switching layout keeps all filled photos and resets masks',
      (tester) async {
    await _pumpComposer(tester);

    await _reveal(
      tester,
      const Key('layout_template_three_rows'),
      rail: const Key('layout_template_picker'),
    );
    await tester.tap(find.byKey(const Key('layout_template_three_rows')));
    await tester.pumpAndSettle();
    await tester.tap(_slot(tester, 0));
    await tester.pumpAndSettle();
    await tester.tap(_slot(tester, 1));
    await tester.pumpAndSettle();
    await tester.tap(_slot(tester, 2));
    await tester.pumpAndSettle();

    expect(_state(tester).debugState.slots.where((s) => s.hasImage).length, 3);
    expect(_state(tester).debugBottomMode, LayoutBottomMode.layouts);

    await tester.tap(find.byKey(const Key('layout_mode_shapes')));
    await tester.pumpAndSettle();
    await tester.tap(_slot(tester, 0));
    await tester.pumpAndSettle();
    await _reveal(
      tester,
      const Key('layout_shape_oval'),
      rail: const Key('layout_shape_picker'),
    );
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

  testWidgets('split handle slides a two-row layout and preview hides it',
      (tester) async {
    await _pumpComposer(tester);

    await tester.tap(find.byKey(const Key('layout_template_two_rows')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('layout_split_handle_0')), findsOneWidget);
    expect(find.byKey(const Key('layout_frame_slider')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('layout_split_handle_0')),
      const Offset(0, 80),
    );
    await tester.pumpAndSettle();

    final weights = _state(tester).debugState.splitWeights;
    expect(weights, isNotNull);
    expect(weights!.first, greaterThan(0.5));

    await tester.tap(find.byKey(const Key('layout_composer_preview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('layout_split_handle_0')), findsNothing);
  });

  testWidgets('2 / 1 layout has both a vertical and a horizontal split handle',
      (tester) async {
    await _pumpComposer(tester);

    await _reveal(
      tester,
      const Key('layout_template_two_over_one'),
      rail: const Key('layout_template_picker'),
    );
    await tester.tap(find.byKey(const Key('layout_template_two_over_one')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('layout_split_handle_0')), findsOneWidget);
    expect(
      find.byKey(const Key('layout_split_handle_cell_0_0')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const Key('layout_split_handle_cell_0_0')),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();

    final cells = _state(tester).debugState.cellWeights;
    expect(cells, isNotNull);
    expect(cells!.first.first, greaterThan(0.5));
  });

  testWidgets('border slider thickens the photo frame', (tester) async {
    await _pumpComposer(tester);

    expect(_state(tester).debugState.frame, kLayoutDefaultFrame);
    await tester.drag(
      find.byKey(const Key('layout_frame_slider')),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();
    expect(_state(tester).debugState.frame, greaterThan(kLayoutDefaultFrame));
  });
}
