import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/pages/file/file_edit_page.dart';

void main() {
  group('file_edit_page date helpers', () {
    test('looksLikeDateValue detects common date formats', () {
      expect(looksLikeDateValue('2026/03/29'), isTrue);
      expect(looksLikeDateValue('2026-3-9'), isTrue);
      expect(looksLikeDateValue('2026年03月29日'), isTrue);
      expect(looksLikeDateValue('年 月 日'), isFalse);
      expect(looksLikeDateValue('不是日期'), isFalse);
    });

    test('looksLikeDatePlaceholder detects empty and placeholder values', () {
      expect(looksLikeDatePlaceholder(''), isTrue);
      expect(looksLikeDatePlaceholder('年 月 日'), isTrue);
      expect(looksLikeDatePlaceholder('yyyy/MM/dd'), isTrue);
      expect(looksLikeDatePlaceholder('2026/03/29'), isFalse);
    });

    test('shouldTreatFieldAsDate detects date fields from description', () {
      expect(
        shouldTreatFieldAsDate(description: '複查日期', raw: ''),
        isTrue,
      );
      expect(
        shouldTreatFieldAsDate(description: 'Review Date', raw: ''),
        isTrue,
      );
      expect(
        shouldTreatFieldAsDate(description: '備註', raw: ''),
        isFalse,
      );
    });

    test('shouldTreatFieldAsDate detects existing date values from payload',
        () {
      expect(
        shouldTreatFieldAsDate(description: '備註', raw: '2026/03/29'),
        isTrue,
      );
      expect(
        shouldTreatFieldAsDate(description: '備註', raw: '年 月 日'),
        isTrue,
      );
    });

    test('isProjectNameField detects project and site name fields', () {
      expect(isProjectNameField('工程名稱'), isTrue);
      expect(isProjectNameField('工地名稱'), isTrue);
      expect(isProjectNameField('Project Name'), isTrue);
      expect(isProjectNameField('分項工程名稱'), isFalse);
      expect(isProjectNameField('備註'), isFalse);
    });

    test('findTableProjectNameAutofillTargets fills only exact project rows',
        () {
      final fields = <dynamic>[
        <String, dynamic>{
          'field_id': 1,
          'is_table': true,
          'table_index': 0,
          'row_index': 0,
          'description': '',
          'original_text': '工程名稱',
        },
        <String, dynamic>{
          'field_id': 2,
          'is_table': true,
          'table_index': 0,
          'row_index': 0,
          'description': '',
          'original_text': '',
        },
        <String, dynamic>{
          'field_id': 3,
          'is_table': true,
          'table_index': 0,
          'row_index': 1,
          'description': '',
          'original_text': '分項工程名稱',
        },
        <String, dynamic>{
          'field_id': 4,
          'is_table': true,
          'table_index': 0,
          'row_index': 1,
          'description': '',
          'original_text': '',
        },
      ];

      expect(findTableProjectNameAutofillTargets(fields), <int>[2]);
    });

    test('isReviewDateField matches only review-related date fields', () {
      expect(
        isReviewDateField(description: '複查日期', raw: ''),
        isTrue,
      );
      expect(
        isReviewDateField(description: '複查', raw: 'yyyy/MM/dd'),
        isTrue,
      );
      expect(
        isReviewDateField(description: '日期', raw: 'yyyy/MM/dd'),
        isFalse,
      );
    });

    test(
        'resolveInitialFieldText keeps review date empty unless auto-fill is enabled',
        () {
      expect(
        resolveInitialFieldText(
          description: '複查日期',
          raw: 'yyyy/MM/dd',
          todayDateText: '2026/03/29',
          autoFillReviewDate: false,
        ),
        '',
      );

      expect(
        resolveInitialFieldText(
          description: '複查日期',
          raw: 'yyyy/MM/dd',
          todayDateText: '2026/03/29',
          autoFillReviewDate: true,
        ),
        '2026/03/29',
      );

      expect(
        resolveInitialFieldText(
          description: '日期',
          raw: 'yyyy/MM/dd',
          todayDateText: '2026/03/29',
        ),
        '2026/03/29',
      );
    });
  });
}
