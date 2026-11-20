import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xtremflow/core/theme/app_theme.dart';

void main() {
  group('AppTheme.font', () {
    test('always uses Figtree', () {
      expect(AppTheme.font().fontFamily, 'Figtree');
      expect(AppTheme.font(fontSize: 14).fontFamily, 'Figtree');
    });

    test('weights above 600 come back to 600', () {
      expect(
        AppTheme.font(fontWeight: FontWeight.w700).fontWeight,
        FontWeight.w600,
      );
      expect(
        AppTheme.font(fontWeight: FontWeight.w800).fontWeight,
        FontWeight.w600,
      );
      expect(
        AppTheme.font(fontWeight: FontWeight.bold).fontWeight,
        FontWeight.w600,
      );
    });

    test('lighter weights are kept', () {
      expect(
        AppTheme.font(fontWeight: FontWeight.w500).fontWeight,
        FontWeight.w500,
      );
      expect(
        AppTheme.font(fontWeight: FontWeight.w400).fontWeight,
        FontWeight.w400,
      );
      expect(AppTheme.font().fontWeight, isNull);
    });

    test('negative tracking comes back to 0', () {
      expect(AppTheme.font(letterSpacing: -0.5).letterSpacing, 0);
      expect(AppTheme.font(letterSpacing: 1.2).letterSpacing, 1.2);
    });

    test('merges textStyle, including its weight and tracking', () {
      const base = TextStyle(
        fontSize: 20,
        color: Colors.red,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
        fontFamily: 'Karla',
      );
      final s = AppTheme.font(textStyle: base, height: 1.4);
      expect(s.fontFamily, 'Figtree');
      expect(s.fontSize, 20);
      expect(s.color, Colors.red);
      expect(s.height, 1.4);
      expect(s.fontWeight, FontWeight.w600);
      expect(s.letterSpacing, 0);
    });
  });
}
