import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'warning_sse_service_common.dart';

Future<WarningSseConnection> connectWarningSse({
  required String baseUrl,
  required String label,
  required String streamId,
  required String streamKey,
  WarningSseTokenProvider? tokenProvider,
  required WarningSseMetadataCallback onMetadata,
  WarningSseErrorCallback? onError,
}) async {
  final connection = _NativeWarningSseConnection(
    uri: warningSseUri(
      baseUrl: baseUrl,
      label: label,
      streamId: streamId,
    ),
    streamKey: streamKey,
    tokenProvider: tokenProvider,
    onMetadata: onMetadata,
    onError: onError,
  );
  connection.open();
  return connection;
}

class _NativeWarningSseConnection implements WarningSseConnection {
  _NativeWarningSseConnection({
    required this.uri,
    required this.streamKey,
    required this.tokenProvider,
    required this.onMetadata,
    required this.onError,
  });

  final Uri uri;
  final String streamKey;
  final WarningSseTokenProvider? tokenProvider;
  final WarningSseMetadataCallback onMetadata;
  final WarningSseErrorCallback? onError;

  final HttpClient _client = HttpClient();
  StreamSubscription<String>? _subscription;
  Timer? _reconnectTimer;
  bool _closed = false;
  int _reconnectAttempt = 0;

  void open() {
    unawaited(_connect());
  }

  Future<void> _connect({bool retryAfterUnauthorized = true}) async {
    if (_closed) return;

    try {
      final request = await _client.getUrl(uri);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'text/event-stream')
        ..set(HttpHeaders.cacheControlHeader, 'no-cache');

      final authToken = (await tokenProvider?.call(force: false))?.trim();
      if (authToken != null && authToken.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $authToken',
        );
      }

      final response = await request.close();
      if (_closed) {
        unawaited(response.drain<void>());
        return;
      }

      if (response.statusCode == 401 &&
          retryAfterUnauthorized &&
          tokenProvider != null) {
        await response.drain<void>();
        final refreshedToken = (await tokenProvider!(force: true))?.trim();
        if (refreshedToken == null || refreshedToken.isEmpty) {
          throw WarningSseHttpException(
            statusCode: response.statusCode,
            uri: uri,
          );
        }
        if (_closed) return;
        return await _connect(retryAfterUnauthorized: false);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        unawaited(response.drain<void>());
        throw WarningSseHttpException(
          statusCode: response.statusCode,
          uri: uri,
        );
      }

      _reconnectAttempt = 0;
      final parser = SseChunkParser();
      _subscription = response.transform(utf8.decoder).listen(
            (chunk) => _handleChunk(parser, chunk),
            onError: _handleError,
            onDone: _scheduleReconnect,
            cancelOnError: true,
          );
    } catch (error) {
      _handleError(error);
    }
  }

  void _handleChunk(SseChunkParser parser, String chunk) {
    for (final event in parser.add(chunk)) {
      if (isRedisErrorSseEvent(event)) {
        try {
          final data = decodeSseJsonMap(event.data);
          _handleError(
            WarningSseServerException(data ?? <String, dynamic>{}),
          );
        } catch (error) {
          _handleError(error);
        }
        return;
      }
      if (!isMetadataSseEvent(event)) continue;

      try {
        final data = decodeSseJsonMap(event.data);
        if (data != null) onMetadata(streamKey, data);
      } catch (error) {
        onError?.call(streamKey, error);
      }
    }
  }

  void _handleError(Object error, [StackTrace? stackTrace]) {
    if (_closed) return;
    onError?.call(streamKey, error);
    if (error is WarningSseHttpException && error.isForbidden) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed) return;

    unawaited(_subscription?.cancel());
    _subscription = null;
    _reconnectTimer?.cancel();

    const delays = <int>[3, 6, 10, 15];
    final delaySeconds = delays[math.min(
      _reconnectAttempt,
      delays.length - 1,
    )];
    _reconnectAttempt += 1;

    _reconnectTimer = Timer(
      Duration(seconds: delaySeconds),
      () => unawaited(_connect()),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _reconnectTimer?.cancel();
    _client.close(force: true);
    await _subscription?.cancel();
  }
}
