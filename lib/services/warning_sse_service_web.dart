import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'warning_sse_service_common.dart';

const bool _warningSseDebugEnabled = bool.fromEnvironment(
  'WARNING_SSE_DEBUG',
  defaultValue: true,
);
const Duration _eventSourceFallbackDelay = Duration(seconds: 12);
const Duration _fetchOpenTimeout = Duration(seconds: 15);
const Duration _fetchChunkWarningDelay = Duration(seconds: 10);

Future<WarningSseConnection> connectWarningSse({
  required String baseUrl,
  required String label,
  required String streamId,
  required String streamKey,
  WarningSseTokenProvider? tokenProvider,
  required WarningSseMetadataCallback onMetadata,
  WarningSseErrorCallback? onError,
}) async {
  final uri = warningSseUri(
    baseUrl: baseUrl,
    label: label,
    streamId: streamId,
  );
  _logWarningSse(
    'connect streamKey=$streamKey label=$label streamId=$streamId url=$uri',
  );

  final connection = _WebWarningSseConnection(
    uri: uri,
    streamKey: streamKey,
    onMetadata: onMetadata,
    onError: onError,
  );
  connection.open();
  return connection;
}

const List<String> _metadataEventNames = <String>[
  'metadata',
  'stream_metadata',
];
const String _redisErrorEventName = 'redis_error';

void _handleMessageEvent({
  required web.Event event,
  required String streamKey,
  required WarningSseMetadataCallback onMetadata,
  required WarningSseErrorCallback? onError,
}) {
  final eventType = event.type;
  try {
    final message = event as web.MessageEvent;
    _handleDataText(
      streamKey: streamKey,
      eventType: eventType,
      dataText: _messageData(message),
      onMetadata: onMetadata,
      onError: onError,
    );
  } catch (error) {
    _logWarningSse(
      'metadata parse failed streamKey=$streamKey event=$eventType error=$error',
    );
    onError?.call(streamKey, error);
  }
}

void _handleDataText({
  required String streamKey,
  required String eventType,
  required String? dataText,
  required WarningSseMetadataCallback onMetadata,
  required WarningSseErrorCallback? onError,
}) {
  try {
    _logWarningSse(
      'metadata raw streamKey=$streamKey event=$eventType data=$dataText',
    );
    if (dataText == null || dataText.isEmpty) {
      _logWarningSse(
        'metadata ignored empty payload streamKey=$streamKey event=$eventType',
      );
      return;
    }

    final decoded = jsonDecode(dataText);
    if (decoded is Map) {
      final data = Map<String, dynamic>.from(decoded);
      _logWarningSse(
        'metadata decoded streamKey=$streamKey event=$eventType '
        'hasWarning=${sseMetadataHasWarning(data)} data=$data',
      );
      onMetadata(streamKey, data);
    } else {
      _logWarningSse(
        'metadata ignored non-map payload streamKey=$streamKey '
        'event=$eventType decodedType=${decoded.runtimeType}',
      );
    }
  } catch (error) {
    _logWarningSse(
      'metadata parse failed streamKey=$streamKey event=$eventType error=$error',
    );
    onError?.call(streamKey, error);
  }
}

void _handleRedisErrorEvent({
  required web.Event event,
  required String streamKey,
  required WarningSseErrorCallback? onError,
}) {
  try {
    final message = event as web.MessageEvent;
    final dataText = _messageData(message);
    final data = dataText == null || dataText.isEmpty
        ? <String, dynamic>{}
        : decodeSseJsonMap(dataText) ?? <String, dynamic>{};
    _logWarningSse('redis error streamKey=$streamKey data=$data');
    onError?.call(streamKey, WarningSseServerException(data));
  } catch (error) {
    _logWarningSse(
        'redis error parse failed streamKey=$streamKey error=$error');
    onError?.call(streamKey, error);
  }
}

void _logWarningSse(String message) {
  if (_warningSseDebugEnabled) {
    debugPrint('[WarningSSE][web] $message');
  }
}

String _readyStateLabel(web.EventSource source) {
  return switch (source.readyState) {
    web.EventSource.CONNECTING => 'CONNECTING(0)',
    web.EventSource.OPEN => 'OPEN(1)',
    web.EventSource.CLOSED => 'CLOSED(2)',
    final value => 'UNKNOWN($value)',
  };
}

String? _messageData(web.MessageEvent message) {
  final rawData = message.data;
  if (rawData == null || !rawData.isA<JSString>()) return null;
  return (rawData as JSString).toDart;
}

String _preview(String value) {
  const maxLength = 300;
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength)}...';
}

class _WebWarningSseConnection implements WarningSseConnection {
  _WebWarningSseConnection({
    required this.uri,
    required this.streamKey,
    required this.onMetadata,
    required this.onError,
  });

  final Uri uri;
  final String streamKey;
  final WarningSseMetadataCallback onMetadata;
  final WarningSseErrorCallback? onError;

  web.EventSource? _source;
  web.EventListener? _messageListener;
  web.EventListener? _redisErrorListener;
  StreamSubscription<web.Event>? _openSubscription;
  StreamSubscription<web.MessageEvent>? _messageSubscription;
  StreamSubscription<web.Event>? _errorSubscription;
  BrowserClient? _fetchClient;
  StreamSubscription<String>? _fetchSubscription;
  Timer? _diagnosticsTimer;
  Timer? _fallbackTimer;
  Timer? _fetchChunkTimer;
  DateTime? _startedAt;
  bool _closed = false;
  bool _sawOpen = false;
  bool _sawMessage = false;
  bool _usingFetchFallback = false;
  bool _fetchProbeActive = false;

  void open() {
    if (_closed) return;
    _openEventSource();
  }

  void _openEventSource() {
    final source = web.EventSource(
      uri.toString(),
      web.EventSourceInit(withCredentials: true),
    );
    _source = source;
    _startedAt = DateTime.now();
    _sawOpen = false;
    _sawMessage = false;

    _diagnosticsTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_closed || _usingFetchFallback || _sawOpen || _sawMessage) {
        timer.cancel();
        return;
      }
      final startedAt = _startedAt;
      _logWarningSse(
        'waiting streamKey=$streamKey readyState=${_readyStateLabel(source)} '
        'elapsed=${startedAt == null ? 0 : DateTime.now().difference(startedAt).inSeconds}s '
        'url=$uri',
      );
    });

    _fallbackTimer = Timer(_eventSourceFallbackDelay, () {
      if (_closed || _usingFetchFallback || _sawOpen || _sawMessage) return;
      _logWarningSse(
        'probe fetch fallback streamKey=$streamKey '
        'readyState=${_readyStateLabel(source)} url=$uri',
      );
      unawaited(_openFetchStream());
    });

    _openSubscription = source.onOpen.listen((event) {
      _sawOpen = true;
      _fallbackTimer?.cancel();
      _logWarningSse(
        'open streamKey=$streamKey readyState=${_readyStateLabel(source)}',
      );
    });

    late final web.EventListener messageListener;
    messageListener = ((web.Event event) {
      _sawMessage = true;
      _fallbackTimer?.cancel();
      _handleMessageEvent(
        event: event,
        streamKey: streamKey,
        onMetadata: onMetadata,
        onError: onError,
      );
    }).toJS;
    _messageListener = messageListener;

    for (final eventName in _metadataEventNames) {
      source.addEventListener(eventName, messageListener);
    }
    late final web.EventListener redisErrorListener;
    redisErrorListener = ((web.Event event) {
      _handleRedisErrorEvent(
        event: event,
        streamKey: streamKey,
        onError: onError,
      );
    }).toJS;
    _redisErrorListener = redisErrorListener;
    source.addEventListener(_redisErrorEventName, redisErrorListener);
    _messageSubscription = source.onMessage.listen((event) {
      _sawMessage = true;
      _fallbackTimer?.cancel();
      _handleMessageEvent(
        event: event,
        streamKey: streamKey,
        onMetadata: onMetadata,
        onError: onError,
      );
    });
    _errorSubscription = source.onError.listen((event) {
      if (_closed || _usingFetchFallback) return;
      _logWarningSse(
        'error streamKey=$streamKey readyState=${_readyStateLabel(source)} '
        'url=$uri',
      );
      onError?.call(streamKey, 'warning_sse_error');
    });
  }

  Future<void> _openFetchStream() async {
    if (_closed || _fetchProbeActive || _usingFetchFallback) return;
    _fetchProbeActive = true;
    _fetchClient = BrowserClient()..withCredentials = true;
    final request = http.Request('GET', _sameOriginRelativeUri(uri))
      ..headers.addAll(const <String, String>{
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
      });

    try {
      final response =
          await _fetchClient!.send(request).timeout(_fetchOpenTimeout);
      _fetchProbeActive = false;
      if (_closed) {
        await response.stream.drain<void>();
        return;
      }

      final contentType = response.headers['content-type'] ?? '';
      _logWarningSse(
        'fetch open streamKey=$streamKey status=${response.statusCode} '
        'contentType=$contentType url=${response.request?.url ?? uri}',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
            'Warning SSE fetch failed HTTP ${response.statusCode}');
      }
      _usingFetchFallback = true;
      await _closeEventSource();
      if (!contentType.toLowerCase().contains('text/event-stream')) {
        _logWarningSse(
          'fetch unexpected content-type streamKey=$streamKey '
          'contentType=$contentType',
        );
      }

      final parser = SseChunkParser();
      _fetchChunkTimer = Timer(_fetchChunkWarningDelay, () {
        if (_closed || _sawMessage) return;
        _logWarningSse(
          'fetch waiting chunk streamKey=$streamKey '
          'elapsed=${_fetchChunkWarningDelay.inSeconds}s url=$uri',
        );
      });
      _fetchSubscription = response.stream.transform(utf8.decoder).listen(
        (chunk) {
          if (_closed) return;
          _sawMessage = true;
          _fetchChunkTimer?.cancel();
          _logWarningSse(
            'fetch chunk streamKey=$streamKey '
            'length=${chunk.length} preview=${_preview(chunk)}',
          );
          for (final event in parser.add(chunk)) {
            if (isRedisErrorSseEvent(event)) {
              final data = decodeSseJsonMap(event.data) ?? <String, dynamic>{};
              _logWarningSse(
                  'fetch redis error streamKey=$streamKey data=$data');
              onError?.call(streamKey, WarningSseServerException(data));
              return;
            }
            if (!isMetadataSseEvent(event)) {
              _logWarningSse(
                'fetch ignored event streamKey=$streamKey event=${event.event}',
              );
              continue;
            }
            _handleDataText(
              streamKey: streamKey,
              eventType: event.event ?? 'message',
              dataText: event.data,
              onMetadata: onMetadata,
              onError: onError,
            );
          }
        },
        onError: (Object error) {
          if (_closed) return;
          _logWarningSse('fetch error streamKey=$streamKey error=$error');
          onError?.call(streamKey, error);
        },
        onDone: () {
          if (_closed) return;
          _usingFetchFallback = false;
          _logWarningSse('fetch done streamKey=$streamKey');
          onError?.call(streamKey, 'warning_sse_fetch_done');
        },
        cancelOnError: true,
      );
    } catch (error) {
      if (_closed) return;
      _fetchProbeActive = false;
      if (!_usingFetchFallback) {
        await _closeFetchStream();
      }
      if (error is TimeoutException) {
        _logWarningSse(
          'fetch probe timed out streamKey=$streamKey '
          'after=${_fetchOpenTimeout.inSeconds}s; EventSource still waiting',
        );
        return;
      }
      _logWarningSse('fetch open failed streamKey=$streamKey error=$error');
      onError?.call(streamKey, error);
    }
  }

  Uri _sameOriginRelativeUri(Uri targetUri) {
    final location = web.window.location;
    final protocol = location.protocol.replaceFirst(':', '');
    final port = location.port;
    final authority =
        port.isEmpty ? location.hostname : '${location.hostname}:$port';

    if (targetUri.scheme == protocol && targetUri.authority == authority) {
      return Uri(
        path: targetUri.path,
        query: targetUri.hasQuery ? targetUri.query : null,
        fragment: targetUri.hasFragment ? targetUri.fragment : null,
      );
    }

    return targetUri;
  }

  Future<void> _closeEventSource() async {
    _diagnosticsTimer?.cancel();
    _fallbackTimer?.cancel();
    _diagnosticsTimer = null;
    _fallbackTimer = null;

    final source = _source;
    final messageListener = _messageListener;
    final redisErrorListener = _redisErrorListener;
    if (source != null && messageListener != null) {
      for (final eventName in _metadataEventNames) {
        source.removeEventListener(eventName, messageListener);
      }
    }
    if (source != null && redisErrorListener != null) {
      source.removeEventListener(_redisErrorEventName, redisErrorListener);
    }
    await _openSubscription?.cancel();
    await _messageSubscription?.cancel();
    await _errorSubscription?.cancel();
    source?.close();
    _source = null;
    _messageListener = null;
    _redisErrorListener = null;
    _openSubscription = null;
    _messageSubscription = null;
    _errorSubscription = null;
  }

  Future<void> _closeFetchStream() async {
    _fetchChunkTimer?.cancel();
    _fetchChunkTimer = null;
    await _fetchSubscription?.cancel();
    _fetchSubscription = null;
    _fetchClient?.close();
    _fetchClient = null;
    _fetchProbeActive = false;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _closeEventSource();
    await _closeFetchStream();
  }
}
