import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/services/warning_sse_service_common.dart';

void main() {
  test('builds metadata stream URL under service base path', () {
    final uri = warningSseUri(
      baseUrl: 'https://example.test/hazard/api/',
      label: 'Site A',
      streamId: 'Cam 1',
    );

    expect(
      uri.toString(),
      'https://example.test/hazard/api/metadata/stream-id/Site%20A/Cam%201',
    );
  });

  test('parses SSE metadata across chunk boundaries', () {
    final parser = SseChunkParser();

    expect(parser.add('event: metadata\ndata: {"has_'), isEmpty);

    final events = parser.add('warning":true,"id":"1"}\n\n');

    expect(events, hasLength(1));
    expect(events.single.event, 'metadata');
    expect(
      decodeSseJsonMap(events.single.data),
      <String, dynamic>{'has_warning': true, 'id': '1'},
    );
  });

  test('recognises truthy has_warning payloads', () {
    expect(
        sseMetadataHasWarning(<String, dynamic>{'has_warning': true}), isTrue);
    expect(
        sseMetadataHasWarning(<String, dynamic>{'has_warning': '1'}), isTrue);
    expect(
      sseMetadataHasWarning(<String, dynamic>{'has_warning': 'true'}),
      isTrue,
    );
    expect(
      sseMetadataHasWarning(<String, dynamic>{'has_warning': false}),
      isFalse,
    );
  });

  test('accepts backend metadata event aliases', () {
    expect(
      isMetadataSseEvent(
        const SseEvent(event: 'metadata', data: '{"has_warning":true}'),
      ),
      isTrue,
    );
    expect(
      isMetadataSseEvent(
        const SseEvent(event: 'stream_metadata', data: '{"has_warning":true}'),
      ),
      isTrue,
    );
    expect(
      isMetadataSseEvent(
        const SseEvent(event: 'heartbeat', data: '{}'),
      ),
      isFalse,
    );
    expect(
      isRedisErrorSseEvent(
        const SseEvent(event: 'redis_error', data: '{"detail":"lost"}'),
      ),
      isTrue,
    );
  });

  test('classifies SSE authorization responses', () {
    final unauthorized = WarningSseHttpException(
      statusCode: 401,
      uri: Uri.parse('https://example.test/metadata'),
    );
    final forbidden = WarningSseHttpException(
      statusCode: 403,
      uri: Uri.parse('https://example.test/metadata'),
    );

    expect(unauthorized.isUnauthorized, isTrue);
    expect(unauthorized.isForbidden, isFalse);
    expect(forbidden.isUnauthorized, isFalse);
    expect(forbidden.isForbidden, isTrue);
  });
}
