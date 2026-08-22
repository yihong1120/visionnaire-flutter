import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

/// Renders a single PDF page image with common loading and error handling.
class PdfPageImageView extends StatefulWidget {
  const PdfPageImageView({
    super.key,
    required this.pdfDocument,
    required this.pageNumber,
    this.renderBackgroundColor,
    this.minScale,
    this.imageFit,
    this.wrapInCenter = false,
  });

  final PdfDocument pdfDocument;
  final int pageNumber;
  final String? renderBackgroundColor;
  final double? minScale;
  final BoxFit? imageFit;
  final bool wrapInCenter;

  @override
  State<PdfPageImageView> createState() => _PdfPageImageViewState();
}

class _PdfPageImageViewState extends State<PdfPageImageView> {
  static const int _maxCachedPages = 3;
  static final LinkedHashMap<String, PdfPageImage> _pageCache =
      LinkedHashMap<String, PdfPageImage>();

  PdfPageImage? _pageImage;
  bool _loading = true;
  String? _error;
  int _renderGeneration = 0;
  double? _viewportWidth;
  double? _devicePixelRatio;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final double nextViewportWidth = MediaQuery.sizeOf(context).width;
    final double nextDevicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final bool metricsChanged = _viewportWidth != nextViewportWidth ||
        _devicePixelRatio != nextDevicePixelRatio;

    _viewportWidth = nextViewportWidth;
    _devicePixelRatio = nextDevicePixelRatio;

    if (_pageImage == null || metricsChanged) {
      _renderPageInternal(reset: _pageImage != null || _error != null);
    }
  }

  @override
  void didUpdateWidget(covariant PdfPageImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pdfDocument, widget.pdfDocument) ||
        oldWidget.pageNumber != widget.pageNumber ||
        oldWidget.renderBackgroundColor != widget.renderBackgroundColor) {
      if (_viewportWidth != null && _devicePixelRatio != null) {
        _renderPageInternal(reset: true);
      }
    }
  }

  Future<void> _renderPageInternal({required bool reset}) async {
    final double? viewportWidth = _viewportWidth;
    final double? devicePixelRatio = _devicePixelRatio;
    if (viewportWidth == null || devicePixelRatio == null) return;

    final int generation = ++_renderGeneration;
    if (reset && mounted) {
      setState(() {
        _pageImage = null;
        _loading = true;
        _error = null;
      });
    }

    try {
      final page = await widget.pdfDocument.getPage(widget.pageNumber);
      final double targetWidth = math.min(
        page.width * 2,
        math.max(page.width, viewportWidth * devicePixelRatio),
      );
      final double targetHeight = page.height * targetWidth / page.width;
      final String cacheKey = Object.hash(
        identityHashCode(widget.pdfDocument),
        widget.pageNumber,
        widget.renderBackgroundColor,
        targetWidth.round(),
      ).toString();

      final PdfPageImage? cachedImage = _pageCache.remove(cacheKey);
      if (cachedImage != null) {
        _pageCache[cacheKey] = cachedImage;
        await page.close();
        if (!mounted || generation != _renderGeneration) return;
        setState(() {
          _pageImage = cachedImage;
          _loading = false;
        });
        return;
      }

      final pageImage = await page.render(
        width: targetWidth,
        height: targetHeight,
        format: PdfPageImageFormat.png,
        backgroundColor: widget.renderBackgroundColor,
      );
      await page.close();

      if (pageImage != null) {
        _pageCache[cacheKey] = pageImage;
        while (_pageCache.length > _maxCachedPages) {
          _pageCache.remove(_pageCache.keys.first);
        }
      }

      if (!mounted || generation != _renderGeneration) return;
      setState(() {
        _pageImage = pageImage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '頁面載入失敗：$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      final cs = Theme.of(context).colorScheme;
      return Center(child: Text(_error!, style: TextStyle(color: cs.error)));
    }

    final PdfPageImage? pageImage = _pageImage;
    if (pageImage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    Widget image = Image.memory(pageImage.bytes, fit: widget.imageFit);
    if (widget.wrapInCenter) {
      image = Center(child: image);
    }

    return InteractiveViewer(
      maxScale: 4,
      minScale: widget.minScale ?? 1,
      child: image,
    );
  }
}
