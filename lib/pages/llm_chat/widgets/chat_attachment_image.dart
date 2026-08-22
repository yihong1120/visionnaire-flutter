import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'chat_browser_context_image.dart';

class ChatAttachmentImage extends StatefulWidget {
  final Map<String, dynamic> attachment;
  final Future<Uint8List> Function(String url) getBytes;
  final double width;
  final double? maxHeight;
  final double? height;
  final VoidCallback? onTap;
  final bool useBrowserContextMenu;
  final bool hideWhenViewerOpen;

  const ChatAttachmentImage({
    super.key,
    required this.attachment,
    required this.getBytes,
    this.width = 200,
    this.maxHeight,
    this.height,
    this.onTap,
    this.useBrowserContextMenu = true,
    this.hideWhenViewerOpen = true,
  });

  @override
  State<ChatAttachmentImage> createState() => _ChatAttachmentImageState();
}

class _ChatAttachmentImageState extends State<ChatAttachmentImage> {
  Future<_LoadedChatImage>? _imageFuture;
  String? _futureUrl;

  double get _placeholderHeight => widget.height ?? widget.width * 0.75;

  String? get _url =>
      (widget.attachment['preview_url'] ?? widget.attachment['url']) as String?;

  @override
  void initState() {
    super.initState();
    _updateFuture();
  }

  @override
  void didUpdateWidget(covariant ChatAttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateFuture();
  }

  void _updateFuture() {
    final localBytes = widget.attachment['bytes'] as Uint8List?;
    if (localBytes != null) {
      _imageFuture = null;
      _futureUrl = null;
      return;
    }

    final url = _url;
    if (url == null || url.isEmpty || url == _futureUrl) return;

    _futureUrl = url;
    _imageFuture = _loadImage(url);
  }

  Future<_LoadedChatImage> _loadImage(String url) async {
    final bytes = await widget.getBytes(url);
    return _LoadedChatImage(
      bytes: bytes,
      aspectRatio: await _decodeAspectRatio(bytes),
    );
  }

  Future<double?> _decodeAspectRatio(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final width = image.width;
      final height = image.height;
      image.dispose();
      if (width <= 0 || height <= 0) return null;
      return width / height;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localBytes = widget.attachment['bytes'] as Uint8List?;
    if (localBytes != null) {
      if (widget.height == null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            localBytes,
            width: widget.width,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) {
              return _placeholder(
                Icon(
                  Icons.broken_image,
                  color: Theme.of(context).colorScheme.error,
                ),
              );
            },
          ),
        );
      }

      return _imageFrame(
        Image.memory(
          localBytes,
          fit: BoxFit.cover,
          width: widget.width,
          height: widget.height,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Icon(
                Icons.broken_image,
                color: Theme.of(context).colorScheme.error,
              ),
            );
          },
        ),
      );
    }

    final url = _url;
    if (url == null || url.isEmpty) {
      return _placeholder(const Icon(Icons.broken_image));
    }

    return FutureBuilder<_LoadedChatImage>(
      future: _imageFuture,
      builder: (context, snapshot) {
        Widget? placeholder;
        if (snapshot.connectionState == ConnectionState.waiting) {
          placeholder = const CircularProgressIndicator();
        } else if (snapshot.hasError || !snapshot.hasData) {
          placeholder = const Icon(Icons.error_outline);
        }

        if (placeholder != null) {
          return _placeholder(placeholder);
        }

        final loaded = snapshot.data!;
        return _imageFrame(
          widget.useBrowserContextMenu
              ? ChatBrowserContextImage(
                  bytes: loaded.bytes,
                  mimeType: _imageMimeType(),
                  fit: widget.height == null ? BoxFit.contain : BoxFit.cover,
                  onTap: widget.onTap,
                  hideWhenViewerOpen: widget.hideWhenViewerOpen,
                )
              : GestureDetector(
                  onTap: widget.onTap,
                  child: Image.memory(
                    loaded.bytes,
                    fit: widget.height == null ? BoxFit.contain : BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      );
                    },
                  ),
                ),
          aspectRatio: loaded.aspectRatio,
        );
      },
    );
  }

  Widget _imageFrame(Widget child, {double? aspectRatio}) {
    final size = _frameSize(aspectRatio);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: child,
      ),
    );
  }

  Size _frameSize(double? aspectRatio) {
    if (widget.height != null) {
      return Size(widget.width, widget.height!);
    }
    if (aspectRatio == null || aspectRatio <= 0) {
      return Size(widget.width, _placeholderHeight);
    }

    final naturalHeight = widget.width / aspectRatio;
    final minHeight = widget.width * 0.45;
    final maxHeight = widget.maxHeight ?? widget.width * 1.6;
    final height = naturalHeight.clamp(minHeight, maxHeight).toDouble();
    final width = (height == naturalHeight)
        ? widget.width
        : (height * aspectRatio).clamp(1.0, widget.width).toDouble();
    return Size(width, height);
  }

  Widget _placeholder(Widget child) {
    return Container(
      width: widget.width,
      height: _placeholderHeight,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(child: child),
    );
  }

  String _imageMimeType() {
    final contentType = widget.attachment['content_type'];
    if (contentType is String && contentType.startsWith('image/')) {
      return contentType;
    }

    final rawName = widget.attachment['original_name'] ??
        widget.attachment['filename'] ??
        widget.attachment['name'] ??
        _url;
    final name = rawName is String ? rawName.toLowerCase() : '';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.gif')) return 'image/gif';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }
}

class _LoadedChatImage {
  final Uint8List bytes;
  final double? aspectRatio;

  const _LoadedChatImage({
    required this.bytes,
    required this.aspectRatio,
  });
}
