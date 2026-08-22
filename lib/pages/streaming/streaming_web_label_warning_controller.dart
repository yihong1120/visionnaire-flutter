part of 'streaming_web_label_page.dart';

const bool _warningSseDebugEnabled = bool.fromEnvironment(
  'WARNING_SSE_DEBUG',
  defaultValue: true,
);
const Duration _warningSseReconnectDelay = Duration(seconds: 3);

class _WarningSseController {
  _WarningSseController({
    required this.holdDuration,
    required this.onChanged,
    this.tokenProvider,
    this.onAccessDenied,
  });

  final Duration holdDuration;
  final VoidCallback onChanged;
  final WarningSseTokenProvider? tokenProvider;
  final ValueChanged<String>? onAccessDenied;

  final Map<String, WarningSseConnection> _connections =
      <String, WarningSseConnection>{};
  final Map<String, String> _streamIds = <String, String>{};
  final Map<String, Timer> _timers = <String, Timer>{};
  final Map<String, Timer> _reconnectTimers = <String, Timer>{};
  final Map<String, String> _forbiddenStreamIds = <String, String>{};
  final Set<String> _activeKeys = <String>{};
  Map<String, String> _expectedStreamIds = <String, String>{};
  String? _label;
  String? _baseUrl;
  var _generation = 0;
  var _disposed = false;

  bool isActive(String streamKey) => _activeKeys.contains(streamKey);

  Future<void> sync({
    required String label,
    required String baseUrl,
    required Map<String, String> streamIdsByKey,
  }) async {
    if (_disposed) return;

    final generation = ++_generation;
    _label = label;
    _baseUrl = baseUrl;
    _expectedStreamIds = Map<String, String>.from(streamIdsByKey);
    _clearForbiddenStreamsExcept(streamIdsByKey);
    _cancelReconnectsExcept(streamIdsByKey);
    _logWarningSse(
      'sync label=$label baseUrl=$baseUrl streamCount=${streamIdsByKey.length}',
    );
    await _closeStaleConnections(streamIdsByKey);
    if (_disposed || generation != _generation) return;

    for (final entry in streamIdsByKey.entries) {
      if (_connections.containsKey(entry.key)) continue;
      if (_forbiddenStreamIds[entry.key] == entry.value) {
        _logWarningSse(
          'skip forbidden streamKey=${entry.key} streamId=${entry.value}',
        );
        continue;
      }
      _reconnectTimers.remove(entry.key)?.cancel();
      await _openConnection(
        generation: generation,
        label: label,
        baseUrl: baseUrl,
        streamKey: entry.key,
        streamId: entry.value,
        expectedStreamIds: streamIdsByKey,
      );
    }
  }

  Future<void> closeConnections() async {
    _generation += 1;
    _label = null;
    _baseUrl = null;
    _expectedStreamIds = <String, String>{};
    _cancelReconnects();
    final connections = Map<String, WarningSseConnection>.from(_connections);
    _connections.clear();
    _streamIds.clear();
    _forbiddenStreamIds.clear();

    for (final entry in connections.entries) {
      await _closeConnection(entry.key, entry.value);
    }
  }

  void clearHighlights() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    if (_activeKeys.isEmpty) return;
    _activeKeys.clear();
    _notifyChanged();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    clearHighlights();
    await closeConnections();
  }

  Future<void> _closeStaleConnections(Map<String, String> expected) async {
    final staleKeys = _connections.keys
        .where(
            (key) => expected[key] == null || _streamIds[key] != expected[key])
        .toList(growable: false);

    for (final key in staleKeys) {
      _reconnectTimers.remove(key)?.cancel();
      final connection = _connections.remove(key);
      _streamIds.remove(key);
      if (connection != null) await _closeConnection(key, connection);
    }
  }

  void _clearForbiddenStreamsExcept(Map<String, String> expected) {
    final staleKeys = _forbiddenStreamIds.keys
        .where((key) => expected[key] != _forbiddenStreamIds[key])
        .toList(growable: false);
    for (final key in staleKeys) {
      _forbiddenStreamIds.remove(key);
    }
  }

  Future<void> _openConnection({
    required int generation,
    required String label,
    required String baseUrl,
    required String streamKey,
    required String streamId,
    required Map<String, String> expectedStreamIds,
  }) async {
    try {
      _logWarningSse(
        'opening streamKey=$streamKey streamId=$streamId label=$label',
      );
      final connection = await connectWarningSse(
        baseUrl: baseUrl,
        label: label,
        streamId: streamId,
        streamKey: streamKey,
        tokenProvider: tokenProvider,
        onMetadata: _handleMetadata,
        onError: _handleError,
      );

      if (_disposed ||
          generation != _generation ||
          expectedStreamIds[streamKey] != streamId) {
        await connection.close();
        return;
      }

      _connections[streamKey] = connection;
      _streamIds[streamKey] = streamId;
      _forbiddenStreamIds.remove(streamKey);
      _logWarningSse(
        'connected streamKey=$streamKey streamId=$streamId label=$label',
      );
    } catch (error) {
      debugPrint('Warning SSE connection failed for $streamKey: $error');
    }
  }

  void _handleMetadata(String streamKey, Map<String, dynamic> data) {
    if (_disposed || !_streamIds.containsKey(streamKey)) {
      _logWarningSse(
        'metadata ignored stale streamKey=$streamKey disposed=$_disposed',
      );
      return;
    }
    final hasWarning = sseMetadataHasWarning(data);
    _logWarningSse(
      'metadata streamKey=$streamKey hasWarning=$hasWarning data=$data',
    );
    if (!hasWarning) return;

    final wasInactive = _activeKeys.add(streamKey);
    _timers[streamKey]?.cancel();
    _timers[streamKey] = Timer(holdDuration, () {
      _timers.remove(streamKey);
      if (_activeKeys.remove(streamKey)) {
        _logWarningSse('highlight expired streamKey=$streamKey');
        _notifyChanged();
      }
    });

    _logWarningSse(
      'highlight ${wasInactive ? 'enabled' : 'reset'} '
      'streamKey=$streamKey hold=${holdDuration.inSeconds}s',
    );
    if (wasInactive) _notifyChanged();
  }

  void _handleError(String streamKey, Object error) {
    _logWarningSse('error streamKey=$streamKey error=$error');
    final connection = _connections.remove(streamKey);
    final streamId = _streamIds.remove(streamKey);
    if (connection != null) {
      unawaited(_closeConnection(streamKey, connection));
    }
    if (streamId == null ||
        _disposed ||
        _expectedStreamIds[streamKey] != streamId) {
      return;
    }

    if (error is WarningSseHttpException && error.isForbidden) {
      _forbiddenStreamIds[streamKey] = streamId;
      _logWarningSse(
        'access denied streamKey=$streamKey streamId=$streamId; '
        'reconnect stopped',
      );
      onAccessDenied?.call(streamKey);
      return;
    }

    _scheduleReconnect(streamKey: streamKey, streamId: streamId);
  }

  void _scheduleReconnect({
    required String streamKey,
    required String streamId,
  }) {
    if (_reconnectTimers.containsKey(streamKey)) return;
    final label = _label;
    final baseUrl = _baseUrl;
    if (label == null || baseUrl == null) return;

    _logWarningSse(
      'reconnect scheduled streamKey=$streamKey '
      'delay=${_warningSseReconnectDelay.inSeconds}s',
    );
    _reconnectTimers[streamKey] = Timer(_warningSseReconnectDelay, () {
      _reconnectTimers.remove(streamKey);
      if (_disposed ||
          _connections.containsKey(streamKey) ||
          _expectedStreamIds[streamKey] != streamId) {
        return;
      }

      _logWarningSse('reconnect opening streamKey=$streamKey');
      unawaited(_openConnection(
        generation: _generation,
        label: label,
        baseUrl: baseUrl,
        streamKey: streamKey,
        streamId: streamId,
        expectedStreamIds: Map<String, String>.from(_expectedStreamIds),
      ));
    });
  }

  void _cancelReconnectsExcept(Map<String, String> expected) {
    final staleKeys = _reconnectTimers.keys
        .where(
            (key) => expected[key] == null || _streamIds[key] != expected[key])
        .toList(growable: false);
    for (final key in staleKeys) {
      _reconnectTimers.remove(key)?.cancel();
    }
  }

  void _cancelReconnects() {
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();
  }

  Future<void> _closeConnection(
    String streamKey,
    WarningSseConnection connection,
  ) async {
    try {
      await connection.close();
    } catch (error) {
      debugPrint('Warning SSE close failed for $streamKey: $error');
    }
  }

  void _notifyChanged() {
    if (!_disposed) onChanged();
  }

  void _logWarningSse(String message) {
    if (_warningSseDebugEnabled) {
      debugPrint('[WarningSSE][controller] $message');
    }
  }
}
