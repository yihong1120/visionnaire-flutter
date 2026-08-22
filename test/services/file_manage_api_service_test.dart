import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/models/document_draft.dart';
import 'package:visionnaire/services/file_manage_api_service.dart';

void main() {
  group('normalizeSignerResponse', () {
    test('accepts paginated map payloads', () {
      final result = normalizeSignerResponse(<String, dynamic>{
        'total': 42,
        'items': <dynamic>[
          <String, dynamic>{'id': 1, 'username': 'alice'},
        ],
      });

      expect(result['total'], 42);
      expect(result['items'], hasLength(1));
      expect((result['items'] as List).first['username'], 'alice');
    });

    test('rejects a malformed signer item instead of coercing it', () {
      expect(
        () => normalizeSignerResponse(<String, dynamic>{
          'items': <Object?>['not-a-signer'],
        }),
        throwsFormatException,
      );
    });
  });

  group('findUniqueDocumentByReference', () {
    test('scans once and returns the exact opaque reference', () {
      final Map<String, dynamic>? result = findUniqueDocumentByReference(
        <Object?>[
          <String, dynamic>{'full_file_code': 'DOC-2026-0001'},
          <String, dynamic>{'public_id': 'public-2'},
        ],
        'public-2',
      );

      expect(result, <String, dynamic>{'public_id': 'public-2'});
    });

    test('rejects duplicate references without allocating a match list', () {
      expect(
        () => findUniqueDocumentByReference(
          <Object?>[
            <String, dynamic>{'public_id': 'public-2'},
            <String, dynamic>{'uuid': 'public-2'},
          ],
          'public-2',
        ),
        throwsStateError,
      );
    });
  });

  group('draftBaseUrlFromFileManagementBase', () {
    test('uses the configured file_manage base unchanged', () {
      expect(
        draftBaseUrlFromFileManagementBase(
          'https://api.example.invalid/hazard/api/file_manage',
        ),
        'https://api.example.invalid/hazard/api/file_manage',
      );
    });

    test('keeps file_management base unchanged when explicitly configured', () {
      expect(
        draftBaseUrlFromFileManagementBase(
          'https://api.example.invalid/hazard/api/file_management',
        ),
        'https://api.example.invalid/hazard/api/file_management',
      );
    });

    test('normalizes a trailing slash without rewriting route names', () {
      expect(
        draftBaseUrlFromFileManagementBase(
          'https://api.example.invalid/hazard/api/file_manage/',
        ),
        'https://api.example.invalid/hazard/api/file_manage',
      );
    });
  });

  group('documentDraftUpsertBody', () {
    test('matches backend PUT payload contract without path-only draft key',
        () {
      final DateTime updatedAt = DateTime.utc(2026, 6, 19, 12);
      final DateTime expiresAt = DateTime.utc(2026, 7, 19, 12);
      final body = documentDraftUpsertBody(
        DocumentDraft(
          key: 'file_edit:user_1:file_638',
          type: 'file_edit',
          payload: <String, dynamic>{
            'fields': <String, dynamic>{},
            'checkboxes': <String, dynamic>{},
            'signers': <dynamic>[],
            'editor_state': <String, dynamic>{},
          },
          updatedAt: updatedAt,
          expiresAt: expiresAt,
        ),
      );

      expect(body, isNot(contains('draft_key')));
      expect(body['draft_type'], 'file_edit');
      expect(body['payload'], isA<Map<String, dynamic>>());
      expect(body['client_updated_at'], updatedAt.toIso8601String());
      expect(body['expires_at'], expiresAt.toIso8601String());
    });
  });

  group('documentDraftFromResponse', () {
    test('treats null draft response as no draft', () {
      expect(
        FileManageAPIService.documentDraftFromResponse(
          <String, dynamic>{'draft': null},
          fallbackKey: 'file_edit:create:client-abc',
        ),
        isNull,
      );
      expect(
        FileManageAPIService.documentDraftFromResponse(
          <String, dynamic>{'item': null},
          fallbackKey: 'file_edit:create:client-abc',
        ),
        isNull,
      );
    });

    test('parses wrapped draft response', () {
      final draft = FileManageAPIService.documentDraftFromResponse(
        <String, dynamic>{
          'draft': <String, dynamic>{
            'draft_key': 'file_edit:create:client-abc',
            'draft_type': 'file_edit',
            'payload': <String, dynamic>{'field': 'value'},
            'updated_at': '2026-06-19T12:00:00Z',
            'expires_at': '2026-07-19T12:00:00Z',
          },
        },
        fallbackKey: 'fallback',
      );

      expect(draft, isNotNull);
      expect(draft!.key, 'file_edit:create:client-abc');
      expect(draft.payload['field'], 'value');
    });
  });
}
