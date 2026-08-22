import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

@JS('visionnaireAttachHlsById')
external void _attachHlsById(
  String elementId,
  String url,
  String headersJson,
  bool showControls,
);

@JS('visionnaireDisposeHlsById')
external void _disposeHlsById(String elementId);

@JS('visionnaireResumeHlsById')
external void _resumeHlsById(String elementId);

@JS('visionnaireSetHlsAuthHeaders')
external void _setHlsAuthHeaders(String headersJson);

class HlsVideoPlayer extends StatefulWidget {
  final Uri playbackUri;
  final Map<String, String> httpHeaders;
  final bool showControls;
  final String? overlayTitle;
  final String? overlayStatus;
  final String? overlayIndex;
  final String? overlayStatusColor;
  final String? frameBorderColor;
  final double frameBorderWidth;
  final Duration attachDelay;
  final VoidCallback? onPlaybackError;
  final FutureOr<void> Function(String reason)? onPlaybackUnauthorized;

  const HlsVideoPlayer({
    super.key,
    required this.playbackUri,
    this.httpHeaders = const <String, String>{},
    this.showControls = true,
    this.overlayTitle,
    this.overlayStatus,
    this.overlayIndex,
    this.overlayStatusColor,
    this.frameBorderColor,
    this.frameBorderWidth = 0,
    this.attachDelay = Duration.zero,
    this.onPlaybackError,
    this.onPlaybackUnauthorized,
  });

  @override
  State<HlsVideoPlayer> createState() => _HlsVideoPlayerState();
}

class _HlsVideoPlayerState extends State<HlsVideoPlayer>
    with AutomaticKeepAliveClientMixin {
  static int _nextInstanceId = 0;

  late final String _elementId;
  late final String _viewType;
  Timer? _attachRetryTimer;
  web.EventListener? _playbackErrorListener;
  web.EventListener? _playbackUnauthorizedListener;
  int _attachAttempts = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final uniqueId =
        '${DateTime.now().microsecondsSinceEpoch}-${_nextInstanceId++}';
    _elementId = 'visionnaire-hls-video-$uniqueId';
    _viewType = 'visionnaire-hls-video-view-$uniqueId';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final container = web.document.createElement('div') as web.HTMLDivElement;
      container.style.width = '100%';
      container.style.height = '100%';
      container.style.position = 'relative';
      container.style.overflow = 'hidden';
      container.style.backgroundColor = 'black';
      container.style.boxSizing = 'border-box';
      if (widget.frameBorderWidth > 0) {
        container.style.border =
            '${widget.frameBorderWidth}px solid ${widget.frameBorderColor ?? 'white'}';
      }

      final video = web.document.createElement('video') as web.HTMLVideoElement;
      video.id = _elementId;
      video.setAttribute('crossorigin', 'use-credentials');
      video.controls = widget.showControls;
      video.autoplay = true;
      video.muted = true;
      video.playsInline = true;
      video.style.width = '100%';
      video.style.height = '100%';
      video.style.objectFit = 'contain';
      video.style.backgroundColor = 'black';
      container.append(video);

      final stateBadge =
          web.document.createElement('div') as web.HTMLDivElement;
      stateBadge.id = '$_elementId-state';
      stateBadge.style.position = 'absolute';
      stateBadge.style.left = '6px';
      stateBadge.style.top = '6px';
      stateBadge.style.maxWidth = '42%';
      stateBadge.style.boxSizing = 'border-box';
      stateBadge.style.padding = '4px 7px';
      stateBadge.style.borderRadius = '4px';
      stateBadge.style.border = '1px solid rgba(255,255,255,0.10)';
      stateBadge.style.background = 'rgba(0,0,0,0.48)';
      stateBadge.style.color = '#21d18b';
      stateBadge.style.font = '800 10px system-ui, -apple-system, sans-serif';
      stateBadge.style.whiteSpace = 'nowrap';
      stateBadge.style.overflow = 'hidden';
      stateBadge.style.textOverflow = 'ellipsis';
      stateBadge.style.pointerEvents = 'none';
      container.append(stateBadge);

      final titleBadge =
          web.document.createElement('div') as web.HTMLDivElement;
      titleBadge.id = '$_elementId-title';
      titleBadge.style.position = 'absolute';
      titleBadge.style.right = '6px';
      titleBadge.style.top = '6px';
      titleBadge.style.maxWidth = '56%';
      titleBadge.style.boxSizing = 'border-box';
      titleBadge.style.padding = '5px 8px';
      titleBadge.style.borderRadius = '4px';
      titleBadge.style.border = '1px solid rgba(255,255,255,0.10)';
      titleBadge.style.background = 'rgba(0,0,0,0.46)';
      titleBadge.style.color = 'white';
      titleBadge.style.font = '800 13px system-ui, -apple-system, sans-serif';
      titleBadge.style.whiteSpace = 'nowrap';
      titleBadge.style.overflow = 'hidden';
      titleBadge.style.textOverflow = 'ellipsis';
      titleBadge.style.pointerEvents = 'none';
      container.append(titleBadge);

      _updateHtmlOverlays();
      return container;
    });
    _playbackErrorListener = ((web.Event event) {
      final customEvent = event as web.CustomEvent;
      final detail = customEvent.detail;
      if (detail.isA<JSObject>()) {
        final object = detail as JSObject;
        final elementId = object.getProperty('elementId'.toJS);
        if (elementId.isA<JSString>() &&
            (elementId as JSString).toDart == _elementId) {
          widget.onPlaybackError?.call();
        }
      }
    }).toJS;
    web.window.addEventListener(
      'visionnaire-hls-playback-error',
      _playbackErrorListener,
    );
    _playbackUnauthorizedListener = ((web.Event event) {
      if (_eventElementId(event) == _elementId) {
        final callback = widget.onPlaybackUnauthorized;
        if (callback == null) return;
        final reason = _eventReason(event) ?? 'unauthorized';
        unawaited(
          Future<void>.sync(() => callback(reason)).whenComplete(() {
            _resumeHlsById(_elementId);
          }),
        );
      }
    }).toJS;
    web.window.addEventListener(
      'visionnaire-hls-auth-error',
      _playbackUnauthorizedListener,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleAttach());
  }

  @override
  void didUpdateWidget(covariant HlsVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameHeaders(oldWidget.httpHeaders, widget.httpHeaders)) {
      _setHlsAuthHeaders(jsonEncode(widget.httpHeaders));
    }
    _syncVideoElementOptions();
    _updateHtmlOverlays();
    if (oldWidget.playbackUri != widget.playbackUri) {
      _attachAttempts = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleAttach());
    }
  }

  @override
  void dispose() {
    _attachRetryTimer?.cancel();
    final playbackErrorListener = _playbackErrorListener;
    if (playbackErrorListener != null) {
      web.window.removeEventListener(
        'visionnaire-hls-playback-error',
        playbackErrorListener,
      );
    }
    final playbackUnauthorizedListener = _playbackUnauthorizedListener;
    if (playbackUnauthorizedListener != null) {
      web.window.removeEventListener(
        'visionnaire-hls-auth-error',
        playbackUnauthorizedListener,
      );
    }
    _disposeHlsById(_elementId);
    super.dispose();
  }

  String? _eventElementId(web.Event event) {
    return _eventStringProperty(event, 'elementId');
  }

  String? _eventReason(web.Event event) {
    return _eventStringProperty(event, 'reason');
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

  void _scheduleAttach() {
    if (!mounted) return;
    _attachRetryTimer?.cancel();
    _attachRetryTimer =
        Timer(const Duration(milliseconds: 100) + widget.attachDelay, _attach);
  }

  void _attach() {
    if (!mounted) return;
    final video = web.document.getElementById(_elementId);
    if (video == null) {
      _attachAttempts += 1;
      if (_attachAttempts < 30) {
        _scheduleAttach();
      }
      return;
    }
    _attachAttempts = 0;
    _setHlsAuthHeaders(jsonEncode(widget.httpHeaders));
    _syncVideoElementOptions();
    final playbackUrl = widget.playbackUri.toString();
    _attachHlsById(
      _elementId,
      playbackUrl,
      jsonEncode(widget.httpHeaders),
      widget.showControls,
    );
    _updateHtmlOverlays();
  }

  void _syncVideoElementOptions() {
    final video = web.document.getElementById(_elementId);
    if (video != null && video.isA<web.HTMLVideoElement>()) {
      (video as web.HTMLVideoElement).controls = widget.showControls;
    }
  }

  void _updateHtmlOverlays() {
    final titleBadge = web.document.getElementById('$_elementId-title');
    if (titleBadge != null) {
      final title = widget.overlayTitle?.trim() ?? '';
      titleBadge.textContent = title.isEmpty ? '' : '▸ $title';
      (titleBadge as web.HTMLDivElement).style.display =
          title.isEmpty ? 'none' : 'block';
    }

    final stateBadge = web.document.getElementById('$_elementId-state');
    if (stateBadge != null) {
      final status = widget.overlayStatus?.trim() ?? '';
      final index = widget.overlayIndex?.trim() ?? '';
      final color = widget.overlayStatusColor?.trim() ?? '#21d18b';
      final text = [
        if (index.isNotEmpty) index,
        if (status.isNotEmpty) status,
      ].join(' ');
      stateBadge.textContent = text.isEmpty ? '' : '● $text';
      final stateElement = stateBadge as web.HTMLDivElement;
      stateElement.style.color = color;
      stateElement.style.display = text.isEmpty ? 'none' : 'block';
    }
  }

  bool _sameHeaders(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return HtmlElementView(viewType: _viewType);
  }
}
