import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../../providers/unified_auth_provider.dart';
import '../../services/playback_api.dart';
import '../../services/streaming_web_api_service.dart';
import '../../widgets/hls_video_player.dart';
import '../../widgets/responsive_scaffold.dart';

/// Displays a single backend-managed playback session through HLS.
class StreamingWebCameraPage extends StatefulWidget {
  final String label;
  final String streamId;
  final String cameraName;
  final String cameraKey;
  final String overlayLanguage;
  final bool initialShowOverlay;
  final VoidCallback? onBackPressed;

  const StreamingWebCameraPage({
    super.key,
    required this.label,
    required this.streamId,
    required this.cameraName,
    required this.cameraKey,
    required this.overlayLanguage,
    this.initialShowOverlay = true,
    this.onBackPressed,
  });

  @override
  State<StreamingWebCameraPage> createState() => _StreamingWebCameraPageState();
}

class _StreamingWebCameraPageState extends State<StreamingWebCameraPage> {
  late final PlaybackApi _playbackApi;

  PlaybackSession? _session;
  Timer? _renewTimer;
  Future<void>? _renewFuture;
  bool _isLoading = true;
  bool _isReconnecting = false;
  bool _disposed = false;
  String? _error;
  bool _showOverlay = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _showOverlay = widget.initialShowOverlay;
    _playbackApi = PlaybackApi(accessTokenProvider: _playbackAccessToken);
    _connectHlsStream();
  }

  @override
  void didUpdateWidget(covariant StreamingWebCameraPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label ||
        oldWidget.streamId != widget.streamId ||
        oldWidget.cameraKey != widget.cameraKey ||
        (oldWidget.overlayLanguage != widget.overlayLanguage && _showOverlay)) {
      unawaited(_connectHlsStream());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _renewTimer?.cancel();
    unawaited(_closeSession());
    super.dispose();
  }

  Future<String> _playbackAccessToken({bool force = false}) async {
    final auth = context.read<UnifiedAuthProvider>();
    await auth.refreshIfNeeded(force: force);
    final token = auth.requestToken;
    if (token == null || token.isEmpty) {
      throw const FormatException('Not logged in');
    }
    return token;
  }

  Future<void> _connectHlsStream() async {
    final generation = ++_generation;
    setState(() {
      _isLoading = true;
      _isReconnecting = false;
      _error = null;
    });

    try {
      final session = await _playbackApi.createSingle(
        site: widget.label,
        camera: _cameraForRequest,
        profile: _singleProfile,
        language: widget.overlayLanguage,
      );
      if (!mounted || _disposed || generation != _generation) {
        await _playbackApi.close(session.id);
        return;
      }

      await _replaceSession(session);
      setState(() {
        _isLoading = false;
        _isReconnecting = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || _disposed || generation != _generation) return;
      if (await _clearExpiredWebSession(error)) return;
      setState(() {
        _error = 'Failed to connect HLS stream: $error';
        _isLoading = false;
        _isReconnecting = false;
      });
    }
  }

  String get _singleProfile =>
      StreamingWebAPIService.playbackProfileForOverlay(_showOverlay);

  String get _cameraForRequest {
    final candidates = <String>[
      widget.cameraKey,
      widget.cameraName,
      widget.streamId,
    ];
    for (final candidate in candidates) {
      final value = candidate.trim();
      if (value.isNotEmpty) return value;
    }
    throw const FormatException('Camera is missing');
  }

  Future<void> _replaceSession(PlaybackSession next) async {
    final previous = _session;
    _session = next;
    _scheduleRenewal(next);
    if (previous != null && previous.id != next.id) {
      unawaited(_playbackApi.close(previous.id));
    }
  }

  void _scheduleRenewal(PlaybackSession session) {
    if (!mounted || _disposed || _session?.id != session.id) return;
    _renewTimer?.cancel();
    _renewTimer = Timer(
      Duration(seconds: playbackRenewalDelaySeconds(session.expiresIn)),
      () => unawaited(_renewSession()),
    );
  }

  Future<void> _renewSession() async {
    if (!mounted || _disposed) return;
    final active = _renewFuture;
    if (active != null) {
      await active;
      return;
    }

    final renewal = _performRenewal();
    _renewFuture = renewal;
    try {
      await renewal;
    } finally {
      if (identical(_renewFuture, renewal)) {
        _renewFuture = null;
      }
    }
  }

  Future<void> _performRenewal() async {
    final current = _session;
    if (current == null) return;

    try {
      final renewed = await _playbackApi.renew(current);
      if (!mounted || _disposed || _session?.id != current.id) {
        return;
      }
      if (!renewed.renewed || renewed.hlsUrlsChanged) {
        throw StateError('Unexpected playback session renewal response');
      }

      final nextSession = current.copyWithRenewal(renewed);
      setState(() {
        _session = nextSession;
        _isReconnecting = false;
        _error = null;
      });
      _scheduleRenewal(nextSession);
    } catch (error) {
      if (!mounted || _disposed || _session?.id != current.id) return;
      _renewTimer?.cancel();
      if (_shouldRecreatePlayback(error)) {
        Timer.run(() {
          if (mounted && !_disposed) unawaited(_connectHlsStream());
        });
        return;
      }
      _renewTimer = Timer(
        const Duration(seconds: 15),
        () => unawaited(_renewSession()),
      );
    }
  }

  bool _shouldRecreatePlayback(Object error) {
    if (error is PlaybackApiException) {
      return error.statusCode == 401 || error.statusCode == 404;
    }
    final message = error.toString().toLowerCase();
    return message.contains(' 401') ||
        message.contains('(401)') ||
        message.contains(' 404') ||
        message.contains('(404)');
  }

  Future<void> _closeSession() async {
    _renewTimer?.cancel();
    _renewTimer = null;
    final activeRenewal = _renewFuture;
    if (activeRenewal != null) await activeRenewal;

    final session = _session;
    _session = null;
    if (session == null) return;
    try {
      await _playbackApi.close(session.id);
    } catch (_) {
      // Playback sessions have a backend TTL; cleanup should not block routing.
    }
  }

  Future<bool> _clearExpiredWebSession(Object error) async {
    final expired = error is PlaybackApiException
        ? error.isAppSessionExpired
        : error.toString().toLowerCase().contains('app_session_expired');
    if (!expired) return false;
    await context.read<UnifiedAuthProvider>().logout(localOnly: true);
    return true;
  }

  Future<void> _handleHlsUnauthorized(String reason) async {
    if (!mounted || _disposed) return;
    setState(() {
      _isReconnecting = true;
      _error = null;
    });
    await _renewSession();
    if (!mounted || _disposed || _session == null) return;
    setState(() {
      _isReconnecting = false;
      _error = null;
    });
  }

  Future<void> _switchStream(bool showOverlay) async {
    if (_showOverlay == showOverlay || _disposed) return;
    final generation = ++_generation;
    final previousOverlay = _showOverlay;
    setState(() {
      _showOverlay = showOverlay;
      _isReconnecting = true;
      _error = null;
    });

    try {
      final session = await _playbackApi.createSingle(
        site: widget.label,
        camera: _cameraForRequest,
        profile: _singleProfile,
        language: widget.overlayLanguage,
      );
      if (!mounted || _disposed || generation != _generation) {
        await _playbackApi.close(session.id);
        return;
      }
      await _replaceSession(session);
      setState(() {
        _isLoading = false;
        _isReconnecting = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || _disposed || generation != _generation) return;
      if (await _clearExpiredWebSession(error)) return;
      setState(() {
        _showOverlay = previousOverlay;
        _error = 'Failed to switch HLS stream: $error';
        _isLoading = false;
        _isReconnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context)!;
    final title = '${widget.label} : ${widget.cameraName}';
    return ResponsiveScaffold(
      title: title,
      isFullscreen: true,
      onBackPressed: widget.onBackPressed,
      actions: [
        Row(
          children: [
            Text(local.showDetectionResults),
            Switch(
              value: _showOverlay,
              onChanged: (value) => unawaited(_switchStream(value)),
            ),
          ],
        ),
      ],
      body: _error != null
          ? Center(
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            )
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(local),
    );
  }

  Widget _buildBody(AppLocalizations local) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final containerWidth = maxWidth > 960 ? 960.0 : maxWidth * 0.95;

        return SingleChildScrollView(
          child: Center(
            child: Container(
              width: containerWidth,
              margin: const EdgeInsets.symmetric(vertical: 16),
              child: RepaintBoundary(
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 4,
                  clipBehavior: Clip.antiAlias,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _buildVideo(local),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideo(AppLocalizations local) {
    final session = _session;
    if (session == null || session.hlsUri.toString().isEmpty) {
      return Center(child: Text(local.noImage));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        HlsVideoPlayer(
          key: ValueKey(
              'camera-${widget.label}-${widget.streamId}-${session.id}'),
          playbackUri: session.hlsUri,
          httpHeaders: const <String, String>{},
          showControls: true,
          overlayTitle: widget.cameraName,
          overlayStatus: 'LIVE',
          overlayStatusColor: '#1FC77E',
          onPlaybackUnauthorized: _handleHlsUnauthorized,
        ),
        if (_isReconnecting) _buildReconnectBadge(),
      ],
    );
  }

  Widget _buildReconnectBadge() {
    return const Positioned(
      right: 12,
      bottom: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0x99000000),
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            '重新連線中...',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
