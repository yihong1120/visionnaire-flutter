import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/utils/user_display_name.dart';

void main() {
  group('userDisplayName', () {
    test('uses direct family and given name before username', () {
      expect(
        userDisplayName(<String, dynamic>{
          'family_name': '範例',
          'given_name': '使用者',
          'username': 'ming',
        }),
        '範例使用者',
      );
    });

    test('uses whitespace between latin family and given names', () {
      expect(
        userDisplayName(<String, dynamic>{
          'family_name': 'Example',
          'given_name': 'User',
          'username': 'example.user',
        }),
        'Example User',
      );
    });

    test('uses nested signer profile before signer username', () {
      expect(
        userDisplayName(<String, dynamic>{
          'signer_name': 'test.user',
          'signer': <String, dynamic>{
            'profile': <String, dynamic>{
              'family_name': 'Test',
              'given_name': 'User',
            },
          },
        }),
        'Test User',
      );
    });

    test('uses signer family and given fields before signer account', () {
      expect(
        userDisplayName(<String, dynamic>{
          'signer_family_name': '範例',
          'signer_given_name': '使用者',
          'signer_name': 'test.user',
        }),
        '範例使用者',
      );
    });

    test('falls back to account value when no display name exists', () {
      expect(
        userDisplayName(<String, dynamic>{'signer_name': 'test.user'}),
        'test.user',
      );
    });

    test('can suppress account fallback for public comment labels', () {
      expect(
        userDisplayName(
          <String, dynamic>{'signer_name': 'test.user'},
          includeAccountFallback: false,
        ),
        isEmpty,
      );
    });
  });
}
