import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';

void main() {
  group('AppTheme input decoration', () {
    test('light theme keeps a visible unfocused input outline', () {
      final theme = AppTheme.lightTheme();
      final border = theme.inputDecorationTheme.enabledBorder;

      expect(border, isA<OutlineInputBorder>());
      expect(
        (border! as OutlineInputBorder).borderSide.width,
        greaterThan(0),
      );
      expect(theme.inputDecorationTheme.fillColor, isNotNull);
    });

    test('dark theme keeps a visible unfocused input outline', () {
      final theme = AppTheme.darkTheme();
      final border = theme.inputDecorationTheme.enabledBorder;

      expect(border, isA<OutlineInputBorder>());
      expect(
        (border! as OutlineInputBorder).borderSide.width,
        greaterThan(0),
      );
      expect(theme.inputDecorationTheme.fillColor, isNotNull);
    });
  });
}
