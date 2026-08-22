import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

@JS('visionnaireUpdateHlsWallById')
external void _updateHlsWallById(
  String wallId,
  String configJson,
  String headersJson,
);

@JS('visionnaireDisposeHlsWallById')
external void _disposeHlsWallById(String wallId);

@JS('visionnaireResumeHlsById')
external void _resumeHlsById(String elementId);

class HlsVideoWallTile {
  final String slotKey;
  final String slotId;
  final String title;
  final Uri? playbackUri;
  final bool isPlayable;
  final bool isOverlayPending;
  final bool hasWarning;
  final String? overlayIndex;
  final String overlayStatus;
  final String overlayStatusColor;

  const HlsVideoWallTile({
    required this.slotKey,
    required this.slotId,
    required this.title,
    required this.playbackUri,
    required this.isPlayable,
    required this.isOverlayPending,
    required this.hasWarning,
    required this.overlayIndex,
    required this.overlayStatus,
    required this.overlayStatusColor,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'slotKey': slotKey,
      'slotId': slotId,
      'title': title,
      'playbackUrl': playbackUri?.toString(),
      'isPlayable': isPlayable && playbackUri != null,
      'isOverlayPending': isOverlayPending,
      'hasWarning': hasWarning,
      'overlayIndex': overlayIndex,
      'overlayStatus': overlayStatus,
      'overlayStatusColor': overlayStatusColor,
    };
  }
}

class HlsVideoWall extends StatefulWidget {
  final List<HlsVideoWallTile> tiles;
  final int crossAxisCount;
  final double aspectRatio;
  final Map<String, String> httpHeaders;
  final String dividerColor;
  final String warningColor;
  final void Function(String slotKey)? onTileTap;
  final FutureOr<void> Function(String reason, String slotKey)?
      onPlaybackUnauthorized;

  const HlsVideoWall({
    super.key,
    required this.tiles,
    required this.crossAxisCount,
    required this.aspectRatio,
    this.httpHeaders = const <String, String>{},
    required this.dividerColor,
    required this.warningColor,
    this.onTileTap,
    this.onPlaybackUnauthorized,
  });

  @override
  State<HlsVideoWall> createState() => _HlsVideoWallState();
}

class _HlsVideoWallState extends State<HlsVideoWall>
    with AutomaticKeepAliveClientMixin {
  static int _nextWallId = 0;

  late final String _wallId;
  late final String _viewType;
  Timer? _updateRetryTimer;
  web.EventListener? _tileTapListener;
  web.EventListener? _playbackUnauthorizedListener;
  int _updateAttempts = 0;
  String? _lastConfigJson;
  String? _lastHeadersJson;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final uniqueId =
        '${DateTime.now().microsecondsSinceEpoch}-${_nextWallId++}';
    _wallId = 'visionnaire-hls-wall-$uniqueId';
    _viewType = 'visionnaire-hls-wall-view-$uniqueId';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final container = web.document.createElement('div') as web.HTMLDivElement;
      container.id = _wallId;
      container.style.width = '100%';
      container.style.height = '100%';
      container.style.overflow = 'hidden';
      container.style.backgroundColor = '#0d0d11';
      container.style.boxSizing = 'border-box';
      return container;
    });

    _tileTapListener = ((web.Event event) {
      final customEvent = event as web.CustomEvent;
      final detail = customEvent.detail;
      if (!detail.isA<JSObject>()) return;
      final object = detail as JSObject;
      final wallId = object.getProperty('wallId'.toJS);
      final slotKey = object.getProperty('slotKey'.toJS);
      if (!wallId.isA<JSString>() || !slotKey.isA<JSString>()) return;
      if ((wallId as JSString).toDart != _wallId) return;
      widget.onTileTap?.call((slotKey as JSString).toDart);
    }).toJS;
    web.window.addEventListener(
      'visionnaire-hls-wall-tap',
      _tileTapListener,
    );

    _playbackUnauthorizedListener = ((web.Event event) {
      final elementId = _eventStringProperty(event, 'elementId');
      if (elementId == null || !elementId.startsWith('$_wallId-video-')) {
        return;
      }
      final callback = widget.onPlaybackUnauthorized;
      if (callback == null) return;
      final reason = _eventStringProperty(event, 'reason') ?? 'unauthorized';
      final slotKey = _slotKeyForElementId(elementId);
      unawaited(
        Future<void>.sync(() => callback(reason, slotKey)).whenComplete(() {
          _resumeHlsById(elementId);
        }),
      );
    }).toJS;
    web.window.addEventListener(
      'visionnaire-hls-auth-error',
      _playbackUnauthorizedListener,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleUpdate());
  }

  @override
  void didUpdateWidget(covariant HlsVideoWall oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleUpdate());
  }

  @override
  void dispose() {
    _updateRetryTimer?.cancel();
    final tileTapListener = _tileTapListener;
    if (tileTapListener != null) {
      web.window.removeEventListener(
        'visionnaire-hls-wall-tap',
        tileTapListener,
      );
    }
    final playbackUnauthorizedListener = _playbackUnauthorizedListener;
    if (playbackUnauthorizedListener != null) {
      web.window.removeEventListener(
        'visionnaire-hls-auth-error',
        playbackUnauthorizedListener,
      );
    }
    _disposeHlsWallById(_wallId);
    super.dispose();
  }

  String? _eventStringProperty(web.Event event, String propertyName) {
    final customEvent = event as web.CustomEvent;
    final detail = customEvent.detail;
    if (!detail.isA<JSObject>()) return null;
    final object = detail as JSObject;
    final value = object.getProperty(propertyName.toJS);
    if (!value.isA<JSString>()) return null;
    return (value as JSString).toDart;
  }

  String _slotKeyForElementId(String elementId) {
    final prefix = '$_wallId-video-';
    if (!elementId.startsWith(prefix)) return '';
    final slotId = elementId.substring(prefix.length);
    for (final tile in widget.tiles) {
      if (tile.slotId == slotId) return tile.slotKey;
    }
    return slotId;
  }

  void _scheduleUpdate() {
    if (!mounted) return;
    _updateRetryTimer?.cancel();
    _updateRetryTimer = Timer(const Duration(milliseconds: 16), _updateWall);
  }

  void _updateWall() {
    if (!mounted) return;
    if (web.document.getElementById(_wallId) == null) {
      _updateAttempts += 1;
      if (_updateAttempts < 30) {
        _scheduleUpdate();
      }
      return;
    }

    _updateAttempts = 0;
    final config = <String, dynamic>{
      'wallId': _wallId,
      'columns': widget.crossAxisCount,
      'aspectRatio': widget.aspectRatio,
      'dividerColor': widget.dividerColor,
      'warningColor': widget.warningColor,
      'tiles': widget.tiles.map((tile) => tile.toJson()).toList(),
    };
    final configJson = jsonEncode(config);
    final headersJson = jsonEncode(widget.httpHeaders);
    if (configJson == _lastConfigJson && headersJson == _lastHeadersJson) {
      return;
    }
    _lastConfigJson = configJson;
    _lastHeadersJson = headersJson;
    _updateHlsWallById(_wallId, configJson, headersJson);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final columns = math.max(1, widget.crossAxisCount);
        final rows =
            widget.tiles.isEmpty ? 1 : (widget.tiles.length / columns).ceil();
        final tileWidth = width / columns;
        final tileHeight = tileWidth / widget.aspectRatio;
        final height = math.max(tileHeight, rows * tileHeight);

        return SizedBox(
          width: width,
          height: height,
          child: HtmlElementView(viewType: _viewType),
        );
      },
    );
  }
}
