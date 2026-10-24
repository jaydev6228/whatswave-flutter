import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/chats/presentation/widgets/emoji_reaction_picker_screen.dart';

import '../../support/device_matrix.dart';

void main() {
  setUp(() {
    // emoji_picker_flutter keeps its "recent" list in SharedPreferences.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('EmojiReactionPickerSheet survives the layout matrix',
      (tester) async {
    await expectScreenSurvivesLayoutMatrix(
      tester,
      // Pumped where it actually lives -- a bottom sheet pinned to the
      // bottom edge, 90% of the viewport tall.
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: EmojiReactionPickerSheet(),
          ),
        ),
      ),
    );
  });
}
