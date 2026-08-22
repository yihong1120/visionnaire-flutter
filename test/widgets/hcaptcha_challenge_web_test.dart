@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/widgets/hcaptcha_challenge_web.dart';

void main() {
  group('hCaptcha JavaScript string contract', () {
    test('accepts and trims only non-empty JavaScript strings', () {
      expect(
        hCaptchaNonEmptyStringFromJs('  response-token  '.toJS),
        'response-token',
      );
      expect(hCaptchaNonEmptyStringFromJs('   '.toJS), isNull);
      expect(hCaptchaNonEmptyStringFromJs(null), isNull);
      expect(hCaptchaNonEmptyStringFromJs(42.toJS), isNull);
      expect(hCaptchaNonEmptyStringFromJs(true.toJS), isNull);
      expect(hCaptchaNonEmptyStringFromJs(JSObject()), isNull);
    });

    test('does not guess token meaning from string prefixes', () {
      expect(hCaptchaNonEmptyStringFromJs('ES_response-token'.toJS),
          'ES_response-token');
      expect(hCaptchaNonEmptyStringFromJs('0xresponse-token'.toJS),
          '0xresponse-token');
    });
  });
}
