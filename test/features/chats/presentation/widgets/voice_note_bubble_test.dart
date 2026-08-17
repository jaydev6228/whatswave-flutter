import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/chats/presentation/widgets/voice_note_bubble.dart';

void main() {
  // These only exercise the at-rest state (before the play button is ever
  // tapped): tapping it would initialize a real VideoPlayerController,
  // which needs the video_player plugin's platform channel and isn't
  // available in this widget-test environment.
  group('VoiceNoteBubble (at rest)', () {
    Future<void> pumpBubble(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VoiceNoteBubble(
              localMediaPath: '/does/not/exist.m4a',
              fallbackLabel: '0:07',
              contentColor: Colors.black,
            ),
          ),
        ),
      );
    }

    testWidgets('shows the play button and the fallback duration label',
        (tester) async {
      await pumpBubble(tester);

      expect(
        find.byKey(const Key('voice_note_play_pause_button')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('0:07'), findsOneWidget);
    });

    testWidgets(
        'shows the speed button from the start, defaulted to 1x',
        (tester) async {
      await pumpBubble(tester);

      expect(
        find.byKey(const Key('voice_note_speed_button')),
        findsOneWidget,
      );
      expect(find.text('1x'), findsOneWidget);
    });
  });
}
