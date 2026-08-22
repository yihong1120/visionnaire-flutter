@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/services/warning_sse_service.dart';

void main() {
  test('warning SSE facade compiles on web', () {
    final uri = warningSseUri(
      baseUrl: '/bff/streaming_web',
      label: 'site-a',
      streamId: 'cam-1',
    );

    expect(uri.path, '/bff/streaming_web/metadata/stream-id/site-a/cam-1');
  });
}
