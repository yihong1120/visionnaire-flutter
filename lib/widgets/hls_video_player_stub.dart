import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

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
  VideoPlayerController? _controller;
  Object? _error;
  bool _isLoading = true;
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  bool get _usesIosNativeHlsPlayer => Platform.isIOS;

  @override
  void initState() {
    super.initState();
    if (!_usesIosNativeHlsPlayer) {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant HlsVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_usesIosNativeHlsPlayer) {
      _generation += 1;
      final controller = _controller;
      _controller = null;
      unawaited(controller?.dispose());
      if (_isLoading || _error != null) {
        setState(() {
          _isLoading = false;
          _error = null;
        });
      }
      return;
    }

    if (oldWidget.playbackUri != widget.playbackUri ||
        oldWidget.showControls != widget.showControls ||
        !_sameHeaders(oldWidget.httpHeaders, widget.httpHeaders)) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _generation += 1;
    final controller = _controller;
    _controller = null;
    unawaited(controller?.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final oldController = _controller;
    _controller = null;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    unawaited(oldController?.dispose());

    try {
      final controller = await _createController(widget.playbackUri);
      if (!mounted || generation != _generation) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _isLoading = false;
      });
    } catch (primaryError) {
      if (!mounted || generation != _generation) return;
      widget.onPlaybackError?.call();
      setState(() {
        _error = primaryError;
        _isLoading = false;
      });
    }
  }

  Future<VideoPlayerController> _createController(Uri uri) async {
    final controller = VideoPlayerController.networkUrl(
      uri,
      httpHeaders: widget.httpHeaders,
      videoPlayerOptions: VideoPlayerOptions(
        allowBackgroundPlayback: false,
      ),
    );

    try {
      await controller.initialize();
      await controller.setLooping(false);
      if (!widget.showControls) {
        await controller.setVolume(0);
      }
      await controller.play();
      return controller;
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }

  bool _sameHeaders(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  Color _parseCssColor(String? value, Color fallback) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return fallback;
    final hex = raw.startsWith('#') ? raw.substring(1) : raw;
    if (hex.length != 6) return fallback;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return fallback;
    return Color(0xFF000000 | parsed);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_usesIosNativeHlsPlayer) {
      return _buildIosNativePlayer();
    }

    final frameColor = _parseCssColor(widget.frameBorderColor, Colors.white);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        border: widget.frameBorderWidth > 0
            ? Border.all(color: frameColor, width: widget.frameBorderWidth)
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildVideo(),
          _buildTopOverlays(),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
          if (_error != null) _buildErrorState(),
        ],
      ),
    );
  }

  Widget _buildIosNativePlayer() {
    return Stack(
      fit: StackFit.expand,
      children: [
        UiKitView(
          key: ValueKey(
            '${widget.playbackUri}|${widget.httpHeaders}|${widget.showControls}',
          ),
          viewType: 'visionnaire/native_hls_player',
          gestureRecognizers: widget.showControls
              ? null
              : const <Factory<OneSequenceGestureRecognizer>>{},
          creationParams: <String, Object?>{
            'url': widget.playbackUri.toString(),
            'headers': widget.httpHeaders,
            'showControls': widget.showControls,
            'muted': !widget.showControls,
          },
          creationParamsCodec: const StandardMessageCodec(),
        ),
        _buildTopOverlays(),
      ],
    );
  }

  Widget _buildVideo() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.expand();
    }

    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  Widget _buildTopOverlays() {
    final title = widget.overlayTitle?.trim() ?? '';
    final status = widget.overlayStatus?.trim() ?? '';
    final index = widget.overlayIndex?.trim() ?? '';
    final statusText = [
      if (index.isNotEmpty) index,
      if (status.isNotEmpty) status,
    ].join(' ');
    final statusColor =
        _parseCssColor(widget.overlayStatusColor, const Color(0xFF21D18B));

    return Stack(
      children: [
        if (statusText.isNotEmpty)
          Positioned(
            left: 6,
            top: 6,
            child: _OverlayBadge(
              text: '● $statusText',
              color: statusColor,
              maxWidth: 150,
            ),
          ),
        if (title.isNotEmpty)
          Positioned(
            right: 6,
            top: 6,
            child: _OverlayBadge(
              text: '▸ $title',
              color: Colors.white,
              maxWidth: 260,
              fontSize: 13,
            ),
          ),
      ],
    );
  }

  Widget _buildErrorState() {
    return const Center(
      child: Icon(
        Icons.videocam_off_outlined,
        color: Colors.white54,
        size: 32,
      ),
    );
  }
}

class _OverlayBadge extends StatelessWidget {
  final String text;
  final Color color;
  final double maxWidth;
  final double fontSize;

  const _OverlayBadge({
    required this.text,
    required this.color,
    required this.maxWidth,
    this.fontSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
