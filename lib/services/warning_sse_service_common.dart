import 'dart:convert';

typedef WarningSseMetadataCallback = void Function(
  String streamKey,
  Map<String, dynamic> data,
);

typedef WarningSseErrorCallback = void Function(
  String streamKey,
  Object error,
);

typedef WarningSseTokenProvider = Future<String?> Function({bool force});

abstract interface class WarningSseConnection {
  Future<void> close();
}

class WarningSseHttpException implements Exception {
  const WarningSseHttpException({
    required this.statusCode,
    required this.uri,
  });

  final int statusCode;
  final Uri uri;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;

  @override
  String toString() => 'WarningSseHttpException($statusCode, $uri)';
}

class WarningSseServerException implements Exception {
  const WarningSseServerException(this.data);

  final Map<String, dynamic> data;

  @override
  String toString() => 'WarningSseServerException($data)';
}

class SseEvent {
  const SseEvent({
    required this.event,
    required this.data,
  });

  final String? event;
  final String data;
}

class SseChunkParser {
  String _buffer = '';

  List<SseEvent> add(String chunk) {
    if (chunk.isEmpty) return const <SseEvent>[];

    _buffer += chunk.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final events = <SseEvent>[];

    while (true) {
      final separator = _buffer.indexOf('\n\n');
      if (separator < 0) break;

      final rawEvent = _buffer.substring(0, separator);
      _buffer = _buffer.substring(separator + 2);

      final event = parseSseEvent(rawEvent);
      if (event != null) events.add(event);
    }

    return events;
  }
}

Uri warningSseUri({
  required String baseUrl,
  required String label,
  required String streamId,
}) {
  final baseUri = Uri.parse(baseUrl.replaceFirst(RegExp(r'/+$'), ''));
  final segments = <String>[
    ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
    'metadata',
    'stream-id',
    label,
    streamId,
  ];
  final encodedPath = Uri(pathSegments: segments).path;
  final path = baseUri.hasAuthority || baseUri.path.startsWith('/')
      ? '/$encodedPath'
      : encodedPath;

  return baseUri.replace(
    path: path,
    query: null,
    fragment: null,
  );
}

SseEvent? parseSseEvent(String rawEvent) {
  String? eventName;
  final dataLines = <String>[];

  for (final line in rawEvent.split('\n')) {
    if (line.isEmpty || line.startsWith(':')) continue;

    final separator = line.indexOf(':');
    final field = separator < 0 ? line : line.substring(0, separator);
    var value = separator < 0 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'event':
        eventName = value;
      case 'data':
        dataLines.add(value);
    }
  }

  if (dataLines.isEmpty) return null;

  return SseEvent(
    event: eventName,
    data: dataLines.join('\n'),
  );
}

Map<String, dynamic>? decodeSseJsonMap(String data) {
  final decoded = jsonDecode(data);
  if (decoded is Map) {
    return Map<String, dynamic>.from(decoded);
  }
  return null;
}

bool sseMetadataHasWarning(Map<String, dynamic> data) {
  final value = data['has_warning'] ?? data['hasWarning'];
  if (value is bool) return value;

  final text = value?.toString().trim().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes';
}

bool isMetadataSseEvent(SseEvent event) {
  final eventName = event.event?.trim();
  return eventName == null ||
      eventName.isEmpty ||
      eventName == 'metadata' ||
      eventName == 'stream_metadata';
}

bool isRedisErrorSseEvent(SseEvent event) =>
    event.event?.trim() == 'redis_error';
