import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/providers/locale_provider.dart';

void main() {
  group('LocaleProvider Tests', () {
    late LocaleProvider localeProvider;

    setUp(() {
      localeProvider = LocaleProvider();
    });

    group('Locale Management', () {
      test('should have default locale', () {
        expect(localeProvider.locale, isNotNull);
        expect(localeProvider.locale.languageCode, equals('zh'));
        expect(localeProvider.locale.countryCode, equals('TW'));
      });

      test('should change locale correctly', () {
        const newLocale = Locale('en', 'US');

        localeProvider.setLocale(newLocale);

        expect(localeProvider.locale.languageCode, equals('en'));
        expect(localeProvider.locale.countryCode, equals('US'));
        expect(localeProvider.locale, equals(newLocale));
      });

      test('should not change if same locale is set', () {
        const sameLocale = Locale('zh', 'TW');
        final initialLocale = localeProvider.locale;

        localeProvider.setLocale(sameLocale);

        expect(localeProvider.locale, equals(initialLocale));
      });
    });

    group('Supported Locales', () {
      test('should support Chinese Traditional', () {
        const zhTWLocale = Locale('zh', 'TW');
        localeProvider.setLocale(zhTWLocale);

        expect(localeProvider.locale.languageCode, equals('zh'));
        expect(localeProvider.locale.countryCode, equals('TW'));
      });

      test('should support English', () {
        const enUSLocale = Locale('en', 'US');
        localeProvider.setLocale(enUSLocale);

        expect(localeProvider.locale.languageCode, equals('en'));
        expect(localeProvider.locale.countryCode, equals('US'));
      });

      test('should handle locale without country code', () {
        const enLocale = Locale('en');
        localeProvider.setLocale(enLocale);

        expect(localeProvider.locale.languageCode, equals('en'));
        expect(localeProvider.locale.countryCode, isNull);
      });

      test('should support Japanese', () {
        const jaJPLocale = Locale('ja', 'JP');
        localeProvider.setLocale(jaJPLocale);

        expect(localeProvider.locale.languageCode, equals('ja'));
        expect(localeProvider.locale.countryCode, equals('JP'));
      });
    });

    group('Notifications', () {
      test('should notify listeners on locale change', () {
        bool notified = false;
        localeProvider.addListener(() {
          notified = true;
        });

        const newLocale = Locale('en', 'US');
        localeProvider.setLocale(newLocale);

        expect(notified, isTrue);
      });

      test('should not notify if locale unchanged', () {
        const sameLocale = Locale('zh', 'TW'); // Default locale

        bool notified = false;
        localeProvider.addListener(() {
          notified = true;
        });

        // Set same locale again
        localeProvider.setLocale(sameLocale);
        expect(notified, isFalse);
      });

      test('should notify multiple listeners', () {
        bool listener1Notified = false;
        bool listener2Notified = false;

        localeProvider.addListener(() {
          listener1Notified = true;
        });

        localeProvider.addListener(() {
          listener2Notified = true;
        });

        const newLocale = Locale('fr', 'FR');
        localeProvider.setLocale(newLocale);

        expect(listener1Notified, isTrue);
        expect(listener2Notified, isTrue);
      });
    });

    group('Locale Equality', () {
      test('should correctly compare locales', () {
        const locale1 = Locale('en', 'US');
        const locale2 = Locale('en', 'US');
        const locale3 = Locale('zh', 'TW');

        expect(locale1, equals(locale2));
        expect(locale1, isNot(equals(locale3)));
      });

      test('should handle locale equality without country code', () {
        const locale1 = Locale('en');
        const locale2 = Locale('en');
        const locale3 = Locale('zh');

        expect(locale1, equals(locale2));
        expect(locale1, isNot(equals(locale3)));
      });
    });

    group('Edge Cases', () {
      test('should handle unusual but valid locale codes', () {
        const unusualLocale = Locale('x-piglatin');
        localeProvider.setLocale(unusualLocale);

        expect(localeProvider.locale.languageCode, equals('x-piglatin'));
        expect(localeProvider.locale.countryCode, isNull);
      });

      test('should handle script codes', () {
        const scriptLocale = Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'CN',
        );
        localeProvider.setLocale(scriptLocale);

        expect(localeProvider.locale.languageCode, equals('zh'));
        expect(localeProvider.locale.scriptCode, equals('Hans'));
        expect(localeProvider.locale.countryCode, equals('CN'));
      });

      test('should maintain object consistency', () {
        const newLocale = Locale('de', 'DE');
        localeProvider.setLocale(newLocale);

        // Verify the locale is the same object reference
        expect(identical(localeProvider.locale, newLocale), isTrue);
      });
    });

    group('ChangeNotifier Behavior', () {
      test('should properly dispose', () {
        // This test ensures dispose doesn't throw
        expect(() => localeProvider.dispose(), returnsNormally);
      });

      test('should handle multiple rapid changes', () {
        int notificationCount = 0;
        localeProvider.addListener(() {
          notificationCount++;
        });

        const locales = [
          Locale('en', 'US'),
          Locale('fr', 'FR'),
          Locale('de', 'DE'),
          Locale('ja', 'JP'),
        ];

        for (final locale in locales) {
          localeProvider.setLocale(locale);
        }

        expect(notificationCount, equals(locales.length));
        expect(localeProvider.locale, equals(locales.last));
      });
    });
  });
}
