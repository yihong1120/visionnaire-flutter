import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/widgets/signer_picker.dart';

void main() {
  group('Signer picker helpers', () {
    test('buildSignerSubtitleLines includes only non-empty values', () {
      final lines = buildSignerSubtitleLines(
        <String, dynamic>{
          'family_name': 'EXAMPLE',
          'given_name': 'USER',
          'group_name': 'Safety',
          'email': 'qa@example.com',
        },
        groupLabel: 'Group',
      );

      expect(lines, <String>[
        'EXAMPLE USER',
        'Group: Safety',
        'qa@example.com',
      ]);
    });

    test('buildSignerSubtitleLines ignores site-related payload fields', () {
      final lines = buildSignerSubtitleLines(
        <String, dynamic>{
          'family_name': '範例',
          'given_name': '使用者',
          'group_name': 'Ops',
          'email': '',
          'site_names': <dynamic>['A', 'B', 'C'],
        },
        groupLabel: 'Group',
      );

      expect(lines, <String>[
        '範例使用者',
        'Group: Ops',
      ]);
    });

    test('hasSignerSelectionScope requires group selection', () {
      expect(hasSignerSelectionScope(), isFalse);
      expect(hasSignerSelectionScope(groupId: 10), isTrue);
    });

    test('buildSignerResultSummary reflects selection and loading state', () {
      expect(
        buildSignerResultSummary(
          isLoading: false,
          loaded: 0,
          total: 0,
          hasScope: false,
        ),
        'Select group to load signers',
      );

      expect(
        buildSignerResultSummary(
          isLoading: true,
          loaded: 0,
          total: 20,
          hasScope: true,
        ),
        'Loading signers...',
      );

      expect(
        buildSignerResultSummary(
          isLoading: false,
          loaded: 20,
          total: 42,
          hasScope: true,
        ),
        'Showing 20 / 42',
      );
    });
  });
}
