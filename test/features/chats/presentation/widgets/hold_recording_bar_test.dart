import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/chats/presentation/widgets/composer_voice_button.dart';
import 'package:whatswave/features/chats/presentation/widgets/voice_note_recorder_sheet.dart';
import 'package:whatswave/features/shared/widgets/liquid_glass.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_chrome.dart';

Future<void> _pumpBar(
  WidgetTester tester, {
  required double width,
  required double textScale,
  required bool cancelPending,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: HoldRecordingBar(
                samples: List<double>.filled(48, 0.6),
                elapsed: const Duration(minutes: 1, seconds: 23),
                cancelPending: cancelPending,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // An Android display set to a zoomed size reports both a smaller logical
  // width and a larger text scale. The hint used to be a plain Row sibling,
  // taking its full natural width and pushing the bar past its bounds --
  // the black-and-yellow overflow stripes over the composer.
  for (final cancelPending in [false, true]) {
    testWidgets(
      'the hold-to-record bar survives a zoomed display '
      '(cancelPending: $cancelPending)',
      (tester) async {
        await _pumpBar(
          tester,
          width: 320,
          textScale: 1.6,
          cancelPending: cancelPending,
        );

        expect(tester.takeException(), isNull);
        expect(
          find.text(cancelPending ? 'Release to cancel' : 'Release to send'),
          findsOneWidget,
        );
        expect(find.text('1:23'), findsOneWidget);
      },
    );
  }

  testWidgets('it lays out normally at a standard width', (tester) async {
    await _pumpBar(
      tester,
      width: 390,
      textScale: 1,
      cancelPending: false,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Release to send'), findsOneWidget);
  });

  // Both recording modes are chrome floating over the conversation, so both
  // are drawn on the app's glass. They used to be opaque panels -- an
  // elevated surface Material here, the themed opaque sheet there -- which
  // read as a different design from everything around them.
  testWidgets('the hold bar is drawn on glass, not an opaque panel',
      (tester) async {
    await _pumpBar(
      tester,
      width: 390,
      textScale: 1,
      cancelPending: false,
    );

    expect(
      find.descendant(
        of: find.byType(HoldRecordingBar),
        matching: find.byType(LiquidGlassSurface),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the recorder sheet is drawn on glass, not an opaque panel',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showVoiceNoteRecorderSheet(
                  context,
                  threadId: 'thread-1',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // There is no microphone in a widget test, so the sheet settles on its
    // permission-denied stage -- which is fine: the shell under test is the
    // same one every stage renders into.
    expect(find.byType(StatusChromeSheet), findsOneWidget);
  });
}
