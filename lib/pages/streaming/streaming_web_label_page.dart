import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../../providers/unified_auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/playback_api.dart';
import '../../services/streaming_web_api_service.dart';
import '../../utils/overlay_language.dart';
import '../../services/warning_sse_service.dart';
import '../../widgets/app_transitions.dart';
import '../../widgets/hls_video_wall.dart';
import '../../widgets/responsive_scaffold.dart';
import 'streaming_web_camera_page.dart';

part 'streaming_web_label_wall_store.dart';
part 'streaming_web_label_warning_controller.dart';

class _MonitorWallLayout {
  final int crossAxisCount;
  final double aspectRatio;
  final double padding;
  final bool showCameraIndex;

  const _MonitorWallLayout({
    required this.crossAxisCount,
    required this.aspectRatio,
    required this.padding,
    required this.showCameraIndex,
  });
}

/// Opens one backend-managed playback wall for a site.
class StreamingWebLabelPage extends StatefulWidget {
  final String label;
  final String? siteName;
  final String? initialCameraName;
  final String? initialOverlayLanguage;
  final bool preferNavigatorBack;

  const StreamingWebLabelPage({
    super.key,
    required this.label,
    this.siteName,
    this.initialCameraName,
    this.initialOverlayLanguage,
    this.preferNavigatorBack = false,
  });

  @override
  State<StreamingWebLabelPage> createState() => _StreamingWebLabelPageState();
}

class _StreamingWebLabelPageState extends State<StreamingWebLabelPage> {
  static const Color _dividerColor = Color(0xFF4A4A4A);
  static const Color _warningDividerColor = Color(0xFFB3261E);
  static const Duration _warningHoldDuration = Duration(minutes: 5);

  late final PlaybackApi _playbackApi;
  final _wallStore = _WallStreamStore();
  late final _WarningSseController _warningSseController;
  LocaleProvider? _localeProvider;

  PlaybackWall? _wall;
  Timer? _wallRenewTimer;
  Timer? _wallRetryTimer;
  Future<void>? _wallRenewFuture;
  bool _isLoading = true;
  bool _showOverlay = true;
  String? _error;
  String? _openedInitialCameraKey;
  String _overlayLanguage = 'zh-TW';
  bool _hasLoadedInitialStreams = false;
  int _wallGeneration = 0;
  int _wallRetryFailures = 0;

  List<Map<String, dynamic>> get _streams => _wallStore.streams;

  @override
  void initState() {
    super.initState();
    _playbackApi = PlaybackApi(accessTokenProvider: _playbackAccessToken);
    _warningSseController = _WarningSseController(
      holdDuration: _warningHoldDuration,
      tokenProvider: kIsWeb
          ? null
          : ({bool force = false}) => _playbackAccessToken(force: force),
      onChanged: () {
        if (mounted) setState(() {});
      },
      onAccessDenied: (_) => _showWarningSseAccessDenied(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final localeProvider = context.read<LocaleProvider>();
    if (!identical(_localeProvider, localeProvider)) {
      _localeProvider?.removeListener(_handleLocaleChanged);
      _localeProvider = localeProvider;
      _localeProvider!.addListener(_handleLocaleChanged);
    }
    _syncOverlayLanguage(localeProvider.selectedOverlayLanguage);
  }

  void _handleLocaleChanged() {
    final localeProvider = _localeProvider;
    if (!mounted || localeProvider == null) return;
    _syncOverlayLanguage(localeProvider.selectedOverlayLanguage);
  }

  void _syncOverlayLanguage(String selectedOverlayLanguage) {
    final routeLanguage = widget.initialOverlayLanguage;
    final nextLanguage = routeLanguage == null || routeLanguage.trim().isEmpty
        ? selectedOverlayLanguage
        : OverlayLanguage.normalizeOrFallback(routeLanguage);
    final languageChanged = _overlayLanguage != nextLanguage;
    _overlayLanguage = nextLanguage;

    if (!_hasLoadedInitialStreams) {
      _hasLoadedInitialStreams = true;
      unawaited(_loadStreams());
    } else if (languageChanged) {
      // HLS embeds the overlay text, so the wall must receive fresh URLs when
      // the selected label language changes.
      unawaited(_loadStreams(resetCache: true));
    }
  }

  @override
  void didUpdateWidget(covariant StreamingWebLabelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label) {
      _warningSseController.clearHighlights();
    }
    if (oldWidget.label != widget.label ||
        oldWidget.initialCameraName != widget.initialCameraName) {
      _openedInitialCameraKey = null;
      unawaited(_loadStreams(resetCache: true));
    }
    if (oldWidget.initialOverlayLanguage != widget.initialOverlayLanguage) {
      _syncOverlayLanguage(
        _localeProvider?.selectedOverlayLanguage ??
            context.read<LocaleProvider>().selectedOverlayLanguage,
      );
    }
  }

  @override
  void dispose() {
    _localeProvider?.removeListener(_handleLocaleChanged);
    _wallRenewTimer?.cancel();
    _wallRetryTimer?.cancel();
    unawaited(_warningSseController.dispose());
    unawaited(_closeActiveWall(closeWarningSse: false));
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

  Future<void> _loadStreams({bool resetCache = false}) async {
    if (resetCache) _wallStore.clearPreparedCache();
    final generation = ++_wallGeneration;
    _wallRetryTimer?.cancel();
    _wallRetryTimer = null;
    final hasVisibleWall = _wall != null && _streams.isNotEmpty;
    setState(() {
      _isLoading = !hasVisibleWall;
      _error = null;
    });

    try {
      final wall = await _playbackApi.createWall(
        site: widget.label,
        profile: _wallProfile,
        language: _overlayLanguage,
        transport: 'hls',
      );
      if (!mounted || generation != _wallGeneration) {
        await _playbackApi.close(wall.id);
        return;
      }

      final previousWall = _wall;
      _wallRenewTimer?.cancel();
      setState(() {
        _wall = wall;
        _wallStore.replaceStreams(_streamsFromWall(wall));
        _isLoading = false;
        _error = null;
      });
      _wallRetryFailures = 0;
      _scheduleWallRenewal(wall);
      unawaited(_syncWarningSseConnections());
      if (previousWall != null && previousWall.id != wall.id) {
        unawaited(_closeWall(previousWall));
      }
      _openInitialCameraIfNeeded();
    } catch (error) {
      if (!mounted || generation != _wallGeneration) return;
      if (await _clearExpiredWebAppSession(error)) return;
      if (hasVisibleWall && _wall != null && _streams.isNotEmpty) {
        setState(() {
          _isLoading = false;
          _error = null;
        });
        _scheduleWallRetry(error);
        return;
      }
      setState(() {
        _error = 'Failed to fetch HLS streams: $error';
        _isLoading = false;
      });
      _scheduleWallRetry(error);
    }
  }

  String get _wallProfile =>
      StreamingWebAPIService.playbackProfileForOverlay(_showOverlay);

  List<Map<String, dynamic>> _streamsFromWall(PlaybackWall wall) {
    final streams = wall.items.map((item) {
      final cameraKey = item.cameraKey;
      final title = item.title.trim().isEmpty ? cameraKey : item.title;
      final streamId = item.stableStreamId;
      return <String, dynamic>{
        'key': cameraKey,
        'stream_name': title,
        'name': title,
        'stream_id': streamId,
        '_wall_warning_stream_id': item.streamId ?? '',
        'transport': 'hls',
        '_wall_playback_uri': item.previewHlsUri.toString(),
        '_wall_profile': _wallProfile,
        '_wall_overlay_pending': false,
        '_wall_overlay_ready': _showOverlay,
      };
    }).toList(growable: false);

    return _wallStore.sortedSlots(widget.label, streams);
  }

  void _scheduleWallRenewal(PlaybackWall wall) {
    if (!mounted || _wall?.id != wall.id) return;
    _wallRenewTimer?.cancel();
    _wallRenewTimer = Timer(
      Duration(seconds: playbackRenewalDelaySeconds(wall.expiresIn)),
      () => unawaited(_renewWall()),
    );
  }

  void _scheduleWallRetry(Object error) {
    if (!mounted || !isRetryablePlaybackError(error)) return;
    if (_wallRetryTimer != null) return;

    final delay = playbackRetryDelay(_wallRetryFailures);
    _wallRetryFailures += 1;
    debugPrint(
      'Playback wall retry scheduled for ${widget.label} '
      'in ${delay.inSeconds}s: $error',
    );
    _wallRetryTimer = Timer(delay, () {
      _wallRetryTimer = null;
      if (mounted) unawaited(_loadStreams(resetCache: true));
    });
  }

  Future<void> _renewWall() async {
    if (!mounted) return;
    final active = _wallRenewFuture;
    if (active != null) {
      await active;
      return;
    }

    final renewal = _performWallRenewal();
    _wallRenewFuture = renewal;
    try {
      await renewal;
    } finally {
      if (identical(_wallRenewFuture, renewal)) {
        _wallRenewFuture = null;
      }
    }
  }

  Future<void> _performWallRenewal() async {
    final current = _wall;
    if (current == null || !mounted) return;

    try {
      final renewed = await _playbackApi.renew(current);
      if (!mounted || _wall?.id != current.id) {
        return;
      }
      if (!renewed.renewed || renewed.hlsUrlsChanged) {
        throw StateError('Unexpected playback wall renewal response');
      }

      final nextWall = current.copyWithRenewal(renewed);
      setState(() {
        _wall = nextWall;
        _error = null;
      });
      _scheduleWallRenewal(nextWall);
    } catch (error) {
      if (!mounted || _wall?.id != current.id) return;
      _wallRenewTimer?.cancel();
      if (_shouldRecreatePlayback(error)) {
        Timer.run(() {
          if (mounted) unawaited(_loadStreams(resetCache: true));
        });
        return;
      }
      _wallRenewTimer = Timer(
        const Duration(seconds: 15),
        () => unawaited(_renewWall()),
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

  Future<void> _closeActiveWall({bool closeWarningSse = true}) async {
    if (closeWarningSse) await _warningSseController.closeConnections();
    _wallRetryTimer?.cancel();
    _wallRetryTimer = null;
    _wallRenewTimer?.cancel();
    _wallRenewTimer = null;
    final activeRenewal = _wallRenewFuture;
    if (activeRenewal != null) await activeRenewal;

    final wall = _wall;
    _wall = null;
    if (wall == null) return;
    await _closeWall(wall);
  }

  Future<void> _closeWall(PlaybackWall wall) async {
    try {
      await _playbackApi.close(wall.id);
    } catch (_) {
      // Playback sessions have a backend TTL; cleanup should not block routing.
    }
  }

  Future<void> _syncWarningSseConnections() async {
    try {
      if (!await _ensureWarningSseSession()) {
        debugPrint('Warning SSE setup skipped: inactive BFF session');
        return;
      }
      await _warningSseController.sync(
        label: widget.label,
        baseUrl: await StreamingWebAPIService.baseUrl,
        streamIdsByKey: _warningStreamIdsByKey(),
      );
    } catch (error) {
      debugPrint('Warning SSE setup skipped: $error');
    }
  }

  Future<bool> _ensureWarningSseSession() async {
    if (!kIsWeb) return true;

    final auth = context.read<UnifiedAuthProvider>();
    final active = await auth.ensureWebSessionActive();
    if (!mounted) return false;
    if (!active) {
      await _warningSseController.closeConnections();
    }
    return active;
  }

  void _showWarningSseAccessDenied() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(content: Text('權限不足，無法接收此鏡頭的警告訊息。')),
    );
  }

  Map<String, String> _warningStreamIdsByKey() {
    final streamIdsByKey = <String, String>{};

    for (var index = 0; index < _streams.length; index += 1) {
      final stream = _streams[index];
      final streamId =
          stream['_wall_warning_stream_id']?.toString().trim() ?? '';
      if (streamId.isEmpty) continue;

      final slotIndex = _streamSlotIndex(stream) ?? index;
      streamIdsByKey[_tileStreamKey(stream, slotIndex)] = streamId;
    }

    return streamIdsByKey;
  }

  Future<bool> _clearExpiredWebAppSession(Object error) async {
    if (!kIsWeb) return false;
    final message = error.toString().toLowerCase();
    final expired = error is PlaybackApiException
        ? error.statusCode == 401
        : message.contains('app_session_expired') ||
            message.contains('(401)') ||
            message.contains(' 401');
    if (!expired) return false;
    await context.read<UnifiedAuthProvider>().logout(localOnly: true);
    return true;
  }

  Future<void> _handleWallHlsUnauthorized(String reason, String slotKey) async {
    if (!mounted) return;
    setState(() {
      _error = null;
    });
    try {
      await _renewWall();
    } catch (_) {
      if (!mounted) return;
      await _loadStreams(resetCache: true);
    }
  }

  Future<void> _handleCameraTap(Map<String, dynamic> stream) async {
    await _closeActiveWall();
    if (!mounted) return;

    if (widget.preferNavigatorBack) {
      _openCameraPage(stream);
      return;
    }

    final cameraName = _cameraNameForUrl(stream);
    if (cameraName.isNotEmpty) {
      context.go(
        _streamLocation(
          site: _siteNameForUrl(),
          camera: cameraName,
        ),
      );
      return;
    }

    _openCameraPage(stream);
  }

  void _openCameraPage(
    Map<String, dynamic> stream, {
    bool clearCameraFromUrlOnPop = false,
  }) {
    final cameraName = _streamName(stream);
    final streamId = _streamId(stream);
    pushAppPage<void>(
      context,
      builder: (_) => StreamingWebCameraPage(
        label: widget.label,
        streamId: streamId,
        cameraName: cameraName,
        cameraKey: stream['key']?.toString().trim() ?? cameraName,
        overlayLanguage: _overlayLanguage,
        initialShowOverlay: _showOverlay,
      ),
    ).then((_) {
      if (!mounted) return;
      unawaited(_loadStreams(resetCache: true));
      if (clearCameraFromUrlOnPop) {
        context.go(_streamLocation(site: _siteNameForUrl()));
        _openedInitialCameraKey = null;
      }
    });
  }

  Future<void> _switchOverlay(bool showOverlay) async {
    if (_showOverlay == showOverlay) return;
    setState(() => _showOverlay = showOverlay);
    await _loadStreams(resetCache: true);
  }

  void _openInitialCameraIfNeeded() {
    if (kIsWeb) return;

    final cameraName = widget.initialCameraName?.trim();
    if (cameraName == null || cameraName.isEmpty) return;

    final cameraKey = 'name:$cameraName';
    if (_isLoading || _openedInitialCameraKey == cameraKey) return;

    final targetStream = _wallStore.findByCameraName(cameraName);
    if (targetStream == null) {
      setState(() {
        _error = '找不到 camera=$cameraName 的直播鏡頭';
      });
      _openedInitialCameraKey = cameraKey;
      return;
    }

    _openedInitialCameraKey = cameraKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openCameraPage(targetStream, clearCameraFromUrlOnPop: true);
    });
  }

  String _streamName(Map<String, dynamic> stream) =>
      _WallStreamStore.streamName(stream);

  String _streamId(Map<String, dynamic> stream) =>
      _WallStreamStore.streamIdOf(stream);

  String _streamSlotKey(Map<String, dynamic> stream) =>
      _WallStreamStore.slotKeyOf(stream);

  int? _streamSlotIndex(Map<String, dynamic> stream) =>
      _WallStreamStore.slotIndexOf(stream);

  String _tileStreamKey(Map<String, dynamic> stream, int fallbackIndex) {
    final slotKey = _streamSlotKey(stream).trim();
    if (slotKey.isNotEmpty) return slotKey;
    return 'slot-$fallbackIndex';
  }

  String _cameraNameForUrl(Map<String, dynamic> stream) {
    final streamName = _streamName(stream).trim();
    if (streamName.isNotEmpty) return streamName;
    return _streamId(stream).trim();
  }

  String _siteNameForUrl() {
    final siteName = widget.siteName?.trim();
    if (siteName != null && siteName.isNotEmpty) return siteName;
    return widget.label;
  }

  String _streamLocation({required String site, String? camera}) {
    return Uri(
      path: '/stream',
      queryParameters: <String, String>{
        'site': site,
        if (camera != null && camera.trim().isNotEmpty) 'camera': camera,
        'language': _overlayLanguage,
      },
    ).toString();
  }

  Uri? _activeWallPlaybackUri(Map<String, dynamic> stream) {
    final selectedUri = stream['_wall_playback_uri']?.toString();
    if (selectedUri == null || selectedUri.isEmpty) return null;
    return Uri.tryParse(selectedUri);
  }

  bool get _hasAnyOverlayCapableStream => _streams.isNotEmpty;

  bool _isHlsStream(Map<String, dynamic> stream) {
    return _isHlsTransport(stream) && _activeWallPlaybackUri(stream) != null;
  }

  bool _isHlsTransport(Map<String, dynamic> stream) {
    final transport = stream['transport']?.toString().toLowerCase();
    return transport == null || transport.isEmpty || transport == 'hls';
  }

  bool _streamHasWarning(Map<String, dynamic> stream) {
    for (final key in const <String>[
      'has_warning',
      'hasWarning',
      'warning',
      'is_warning',
      'isWarning',
      'alert',
      'has_alert',
    ]) {
      final value = stream[key];
      if (value is bool && value) return true;
      final text = value?.toString().trim().toLowerCase();
      if (text == 'true' || text == '1' || text == 'yes') return true;
    }

    final alerts = stream['alerts'] ?? stream['warnings'];
    if (alerts is Iterable && alerts.isNotEmpty) return true;
    return false;
  }

  void _goToSiteList() {
    if (!mounted) return;
    context.replace('/stream');
  }

  void _goToSiteGrid() {
    if (!mounted) return;
    context.replace(_streamLocation(site: _siteNameForUrl()));
  }

  String _locationTitle() => widget.label;

  Widget? _buildWebRouteCameraPageIfNeeded(AppLocalizations local) {
    if (!kIsWeb) return null;

    final cameraName = widget.initialCameraName?.trim();
    if (cameraName == null || cameraName.isEmpty) return null;
    if (_isLoading || _error != null) return null;

    final targetStream = _wallStore.findByCameraName(cameraName);
    if (targetStream == null) {
      return ResponsiveScaffold(
        title: _locationTitle(),
        isFullscreen: true,
        onBackPressed: _goToSiteGrid,
        body: Center(
          child: Text(
            '找不到 camera=$cameraName 的直播鏡頭',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    return StreamingWebCameraPage(
      key: ValueKey<String>(
        'web-route-camera:${widget.label}:${_streamId(targetStream)}',
      ),
      label: widget.label,
      streamId: _streamId(targetStream),
      cameraName: _streamName(targetStream),
      cameraKey:
          targetStream['key']?.toString().trim() ?? _streamName(targetStream),
      overlayLanguage: _overlayLanguage,
      initialShowOverlay: _showOverlay,
      onBackPressed: _goToSiteGrid,
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context)!;
    final routeCameraPage = _buildWebRouteCameraPageIfNeeded(local);
    if (routeCameraPage != null) return routeCameraPage;

    return ResponsiveScaffold(
      title: _locationTitle(),
      isFullscreen: true,
      onBackPressed: widget.preferNavigatorBack ? null : _goToSiteList,
      actions: [
        Row(
          children: [
            Text(local.showDetectionResults),
            Switch(
              value: _showOverlay,
              onChanged: _hasAnyOverlayCapableStream
                  ? (value) => unawaited(_switchOverlay(value))
                  : null,
            ),
          ],
        ),
        IconButton(
          tooltip: local.refresh,
          icon: const Icon(Icons.refresh),
          onPressed: _isLoading
              ? null
              : () => unawaited(_loadStreams(resetCache: true)),
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
              : _buildMonitorWall(context, local),
    );
  }

  Widget _buildMonitorWall(BuildContext context, AppLocalizations local) {
    if (_streams.isEmpty) {
      return Center(child: Text(local.noImage));
    }

    return _buildGridView(context);
  }

  _MonitorWallLayout _layoutForWidth(double width) {
    if (width < 520) {
      return const _MonitorWallLayout(
        crossAxisCount: 1,
        aspectRatio: 16 / 11,
        padding: 0,
        showCameraIndex: false,
      );
    }
    if (width < 760) {
      return const _MonitorWallLayout(
        crossAxisCount: 2,
        aspectRatio: 16 / 11,
        padding: 0,
        showCameraIndex: false,
      );
    }
    if (width < 1040) {
      return const _MonitorWallLayout(
        crossAxisCount: 3,
        aspectRatio: 16 / 10.5,
        padding: 0,
        showCameraIndex: true,
      );
    }
    if (width < 1360) {
      return const _MonitorWallLayout(
        crossAxisCount: 4,
        aspectRatio: 16 / 10,
        padding: 0,
        showCameraIndex: true,
      );
    }
    if (width < 1720) {
      return const _MonitorWallLayout(
        crossAxisCount: 5,
        aspectRatio: 16 / 9.8,
        padding: 0,
        showCameraIndex: true,
      );
    }
    if (width < 2200) {
      return const _MonitorWallLayout(
        crossAxisCount: 6,
        aspectRatio: 16 / 9.5,
        padding: 0,
        showCameraIndex: true,
      );
    }

    return _MonitorWallLayout(
      crossAxisCount: (width / 340).floor().clamp(6, 10),
      aspectRatio: 16 / 9.5,
      padding: 0,
      showCameraIndex: true,
    );
  }

  Widget _buildGridView(BuildContext context) {
    final layout = _layoutForWidth(MediaQuery.of(context).size.width);
    final tiles = <HlsVideoWallTile>[];

    for (var index = 0; index < _streams.length; index += 1) {
      final stream = _streams[index];
      final slotIndex = _streamSlotIndex(stream) ?? index;
      final slotKey = _tileStreamKey(stream, slotIndex);
      final cameraName = _streamName(stream);
      final streamId = _streamId(stream);
      final playbackUri = _activeWallPlaybackUri(stream);
      final isPlayable = streamId.isNotEmpty && _isHlsStream(stream);
      final statusColor =
          isPlayable ? const Color(0xFF1FC77E) : const Color(0xFFFFB020);

      tiles.add(
        HlsVideoWallTile(
          slotKey: slotKey,
          slotId: 'slot-${slotIndex.toString().padLeft(3, '0')}',
          title: _cameraTitle(
            cameraName: cameraName,
            streamId: streamId,
            index: slotIndex,
          ),
          playbackUri: playbackUri,
          isPlayable: isPlayable,
          isOverlayPending: false,
          hasWarning: _streamHasWarning(stream) ||
              _warningSseController.isActive(slotKey),
          overlayIndex: layout.showCameraIndex
              ? (slotIndex + 1).toString().padLeft(2, '0')
              : null,
          overlayStatus: isPlayable ? 'LIVE' : '',
          overlayStatusColor: _cssColor(statusColor),
        ),
      );
    }

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(layout.padding),
        child: HlsVideoWall(
          key: ValueKey('wall-${widget.label}-${_wall?.id ?? 'none'}'),
          tiles: tiles,
          crossAxisCount: layout.crossAxisCount,
          aspectRatio: layout.aspectRatio,
          httpHeaders: const <String, String>{},
          dividerColor: _cssColor(_dividerColor),
          warningColor: _cssColor(_warningDividerColor),
          onTileTap: (slotKey) {
            final stream = _wallStore.findBySlotKey(slotKey);
            if (stream != null) unawaited(_handleCameraTap(stream));
          },
          onPlaybackUnauthorized: _handleWallHlsUnauthorized,
        ),
      ),
    );
  }

  String _cssColor(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0')}';
  }

  String _cameraTitle({
    required String cameraName,
    required String streamId,
    required int index,
  }) {
    final trimmedName = cameraName.trim();
    if (trimmedName.isNotEmpty) return trimmedName;

    final trimmedStreamId = streamId.trim();
    if (trimmedStreamId.isNotEmpty) return trimmedStreamId;

    return 'Camera ${index + 1}';
  }
}
