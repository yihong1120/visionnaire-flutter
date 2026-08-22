import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class ChatBrowserContextImage extends StatefulWidget {
  final Uint8List bytes;
  final String mimeType;
  final BoxFit fit;
  final VoidCallback? onTap;
  final bool hideWhenViewerOpen;

  const ChatBrowserContextImage({
    super.key,
    required this.bytes,
    required this.mimeType,
    required this.fit,
    this.onTap,
    this.hideWhenViewerOpen = true,
  });

  @override
  State<ChatBrowserContextImage> createState() =>
      _ChatBrowserContextImageState();
}

class ChatBrowserContextImageRegistry {
  static final Set<_ChatBrowserContextImageState> _instances =
      <_ChatBrowserContextImageState>{};
  static bool _viewerOpen = false;

  static void setViewerOpen(bool open) {
    if (_viewerOpen == open) return;
    _viewerOpen = open;
    for (final instance in Set<_ChatBrowserContextImageState>.of(_instances)) {
      instance._syncViewerVisibility();
    }
  }
}

class _ChatBrowserContextImageState extends State<ChatBrowserContextImage> {
  late final String _viewType;
  web.HTMLDivElement? _containerElement;
  web.HTMLImageElement? _imageElement;
  web.EventListener? _clickListener;
  String? _objectUrl;

  @override
  void initState() {
    super.initState();
    ChatBrowserContextImageRegistry._instances.add(this);
    final uniqueId = DateTime.now().microsecondsSinceEpoch;
    _viewType = 'visionnaire-chat-image-$uniqueId';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final container = web.document.createElement('div') as web.HTMLDivElement;
      container.style.width = '100%';
      container.style.height = '100%';
      container.style.overflow = 'hidden';
      container.style.borderRadius = '12px';
      container.style.backgroundColor = 'transparent';
      _containerElement = container;

      final image = web.document.createElement('img') as web.HTMLImageElement;
      image.style.width = '100%';
      image.style.height = '100%';
      image.style.display = 'block';
      image.style.objectFit = _objectFit(widget.fit);
      image.style.cursor = widget.onTap == null ? 'default' : 'zoom-in';
      image.setAttribute('draggable', 'true');
      _setImageSource(image, widget.bytes, widget.mimeType);

      _clickListener = ((web.Event event) {
        widget.onTap?.call();
      }).toJS;
      image.addEventListener('click', _clickListener);

      _imageElement = image;
      container.append(image);
      _syncViewerVisibility();
      return container;
    });
  }

  @override
  void didUpdateWidget(covariant ChatBrowserContextImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final image = _imageElement;
    if (image == null) return;

    if (oldWidget.bytes != widget.bytes ||
        oldWidget.mimeType != widget.mimeType) {
      _setImageSource(image, widget.bytes, widget.mimeType);
    }
    if (oldWidget.fit != widget.fit) {
      image.style.objectFit = _objectFit(widget.fit);
    }
    if (oldWidget.onTap != widget.onTap) {
      image.style.cursor = widget.onTap == null ? 'default' : 'zoom-in';
    }
    if (oldWidget.hideWhenViewerOpen != widget.hideWhenViewerOpen) {
      _syncViewerVisibility();
    }
  }

  @override
  void dispose() {
    ChatBrowserContextImageRegistry._instances.remove(this);
    final image = _imageElement;
    final listener = _clickListener;
    if (image != null && listener != null) {
      image.removeEventListener('click', listener);
    }
    _revokeObjectUrl();
    super.dispose();
  }

  void _syncViewerVisibility() {
    final container = _containerElement;
    if (container == null) return;

    final hidden = ChatBrowserContextImageRegistry._viewerOpen &&
        widget.hideWhenViewerOpen;
    container.style.visibility = hidden ? 'hidden' : 'visible';
    container.style.pointerEvents = hidden ? 'none' : 'auto';
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }

  void _setImageSource(
    web.HTMLImageElement image,
    Uint8List bytes,
    String mimeType,
  ) {
    _revokeObjectUrl();
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final nextUrl = web.URL.createObjectURL(blob);
    _objectUrl = nextUrl;
    image.src = nextUrl;
  }

  void _revokeObjectUrl() {
    final url = _objectUrl;
    if (url == null) return;
    web.URL.revokeObjectURL(url);
    _objectUrl = null;
  }

  String _objectFit(BoxFit fit) {
    return switch (fit) {
      BoxFit.cover => 'cover',
      BoxFit.fill => 'fill',
      BoxFit.fitHeight => 'contain',
      BoxFit.fitWidth => 'contain',
      BoxFit.none => 'none',
      BoxFit.scaleDown => 'scale-down',
      _ => 'contain',
    };
  }
}
