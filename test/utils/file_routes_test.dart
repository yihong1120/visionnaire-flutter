import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/utils/file_routes.dart';

void main() {
  group('file route helpers', () {
    test('builds document routes with an opaque document reference', () {
      expect(
        filePreviewLocation(docRef: 'DOC-2026-0001'),
        '/files?doc=DOC-2026-0001',
      );
      expect(
        fileEditLocation(docRef: 'DOC-2026-0001'),
        '/files?doc=DOC-2026-0001&view=edit',
      );
      expect(
        fileEditLocation(
          docRef: 'DOC-2026-0001',
          freshlyCreated: true,
          clientDraftId: 'client-abc',
        ),
        '/files?doc=DOC-2026-0001&view=edit&fresh=1&draft=client-abc',
      );
      expect(
        fileVersionsLocation(docRef: 'DOC-2026-0001'),
        '/files?doc=DOC-2026-0001&view=versions',
      );
    });

    test('rejects missing document references instead of falling back to ids',
        () {
      expect(
        () => filePreviewLocation(docRef: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('extracts route references from direct and nested document payloads',
        () {
      expect(
        documentRouteRefFromMap(<String, dynamic>{
          'public_id': 'public-abc',
          'full_file_code': 'DOC-2026-0001',
        }),
        'public-abc',
      );
      expect(
        documentRouteRefFromMap(<String, dynamic>{
          'main_document': <String, dynamic>{
            'full_file_code': 'DOC-2026-0002',
          },
        }),
        'DOC-2026-0002',
      );
    });
  });
}
