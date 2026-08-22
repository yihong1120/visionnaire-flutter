import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/utils/overlay_language.dart';

void main() {
  test('maps application locales to backend overlay language values', () {
    expect(
      OverlayLanguage.forLocale(const Locale('zh', 'TW')),
      'zh-TW',
    );
    expect(
      OverlayLanguage.forLocale(const Locale('zh', 'CN')),
      'zh-CN',
    );
    expect(OverlayLanguage.forLocale(const Locale('en', 'GB')), 'en');
  });

  test('canonicalizes supported route language values', () {
    expect(OverlayLanguage.requireSupported('zh_tw'), 'zh-TW');
    expect(OverlayLanguage.normalizeOrFallback('not-supported'), 'zh-TW');
  });
}
