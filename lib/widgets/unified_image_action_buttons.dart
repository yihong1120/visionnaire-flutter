import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../services/unified_image_service.dart';
import '../widgets/detection_painter.dart';

const String _shareLinkTitle = 'Visionnaire';

/// A unified widget that provides download, copy, and share buttons for images.
///
/// This replaces the various individual image action button implementations
/// and provides a consistent interface across the app.
class UnifiedImageActionButtons extends StatefulWidget {
  /// The image bytes to operate on.
  final Uint8List imageBytes;

  /// The original width of the image (required for overlays).
  final double originalWidth;

  /// The original height of the image (required for overlays).
  final double originalHeight;

  /// Optional cone polygons to overlay.
  final List<List<Offset>>? conePolygons;

  /// Optional pole polygons to overlay.
  final List<List<Offset>>? polePolygons;

  /// Optional detection items to overlay.
  final List<DetectionItem>? detectionItems;

  /// Labels to use when rendering overlays into exported images.
  final DetectionOverlayLabels? labels;

  /// Whether overlays are currently enabled by default.
  final bool showOverlays;

  /// Optional filename prefix for downloads.
  final String? filename;

  /// Optional URL to share from the compact action set.
  final Uri? shareUri;

  /// Whether to show the overlay toggle switch.
  final bool showOverlayToggle;

  /// Whether to show buttons horizontally or vertically.
  final bool isHorizontal;

  /// Creates a [UnifiedImageActionButtons] widget.
  const UnifiedImageActionButtons({
    super.key,
    required this.imageBytes,
    required this.originalWidth,
    required this.originalHeight,
    this.conePolygons,
    this.polePolygons,
    this.detectionItems,
    this.labels,
    this.showOverlays = true,
    this.filename,
    this.shareUri,
    this.showOverlayToggle = true,
    this.isHorizontal = true,
  });

  @override
  State<UnifiedImageActionButtons> createState() =>
      _UnifiedImageActionButtonsState();
}

class _UnifiedImageActionButtonsState extends State<UnifiedImageActionButtons> {
  bool _includeOverlays = true;
  bool _isProcessing = false;

  Future<void> _runAction(Future<void> Function() action) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      await action();
    } catch (_) {
      // Error handling is done in UnifiedImageService.
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleDownload(DetectionOverlayLabels labels) {
    return _runAction(() {
      return UnifiedImageService.downloadImageWithOverlays(
        rawBytes: widget.imageBytes,
        width: widget.originalWidth,
        height: widget.originalHeight,
        context: context,
        labels: labels,
        conePolygons: widget.conePolygons,
        polePolygons: widget.polePolygons,
        detectionItems: widget.detectionItems,
        showOverlays: _includeOverlays,
        filename: widget.filename,
      );
    });
  }

  Future<void> _handleCopy(DetectionOverlayLabels labels) {
    return _runAction(() {
      return UnifiedImageService.copyImageWithOverlays(
        rawBytes: widget.imageBytes,
        width: widget.originalWidth,
        height: widget.originalHeight,
        context: context,
        labels: labels,
        conePolygons: widget.conePolygons,
        polePolygons: widget.polePolygons,
        detectionItems: widget.detectionItems,
        showOverlays: _includeOverlays,
      );
    });
  }

  Future<void> _handleShareLink() {
    return _runAction(() {
      final Uri? shareUri = widget.shareUri;
      if (shareUri == null) return Future<void>.value();
      return UnifiedImageService.shareLink(
        uri: shareUri,
        context: context,
        title: _shareLinkTitle,
      );
    });
  }

  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        foregroundColor: foregroundColor,
        backgroundColor: backgroundColor,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _includeOverlays = widget.showOverlays;
  }

  @override
  void didUpdateWidget(UnifiedImageActionButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showOverlays != oldWidget.showOverlays) {
      setState(() {
        _includeOverlays = widget.showOverlays;
      });
    }
  }

  Widget _buildActionButtons() {
    final AppLocalizations local = AppLocalizations.of(context)!;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final DetectionOverlayLabels labels =
        widget.labels ?? DetectionOverlayLabels.fromLocalizations(local);

    final List<Widget> buttons = [
      _buildActionButton(
        onPressed: _isProcessing ? null : () => _handleDownload(labels),
        icon: Icons.download,
        label: local.downloadImage,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      _buildActionButton(
        onPressed: _isProcessing ? null : () => _handleCopy(labels),
        icon: Icons.copy,
        label: local.copyImage,
        backgroundColor: colorScheme.secondary,
        foregroundColor: colorScheme.onSecondary,
      ),
      if (widget.shareUri != null)
        _buildActionButton(
          onPressed: _isProcessing ? null : _handleShareLink,
          icon: Icons.share,
          label: local.shareImage,
          backgroundColor: colorScheme.tertiary,
          foregroundColor: colorScheme.onTertiary,
        ),
    ];

    if (widget.isHorizontal) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: buttons,
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: buttons
            .map((button) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: button,
                ))
            .toList(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations local = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Overlay toggle switch (if enabled)
        if (widget.showOverlayToggle) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                local.showOverlay,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              Switch(
                value: _includeOverlays,
                onChanged: _isProcessing
                    ? null
                    : (value) {
                        setState(() => _includeOverlays = value);
                      },
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Action buttons or loading indicator
        if (_isProcessing)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          )
        else
          _buildActionButtons(),
      ],
    );
  }
}

/// Simple icon-only version of the image action buttons for compact layouts.
class UnifiedImageActionIconButtons extends StatelessWidget {
  /// The image bytes to operate on.
  final Uint8List imageBytes;

  /// The original width of the image.
  final double originalWidth;

  /// The original height of the image.
  final double originalHeight;

  /// Optional cone polygons to overlay.
  final List<List<Offset>>? conePolygons;

  /// Optional pole polygons to overlay.
  final List<List<Offset>>? polePolygons;

  /// Optional detection items to overlay.
  final List<DetectionItem>? detectionItems;

  /// Labels to use when rendering overlays into exported images.
  final DetectionOverlayLabels? labels;

  /// Whether overlays are enabled.
  final bool showOverlays;

  /// Optional filename prefix for downloads.
  final String? filename;

  /// Optional URL to share from the compact action set.
  final Uri? shareUri;

  /// Creates a [UnifiedImageActionIconButtons] widget.
  const UnifiedImageActionIconButtons({
    super.key,
    required this.imageBytes,
    required this.originalWidth,
    required this.originalHeight,
    this.conePolygons,
    this.polePolygons,
    this.detectionItems,
    this.labels,
    this.showOverlays = true,
    this.filename,
    this.shareUri,
  });

  Widget _buildIconButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String tooltip,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: tooltip,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    final DetectionOverlayLabels labels =
        this.labels ?? DetectionOverlayLabels.fromLocalizations(local);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildIconButton(
          onPressed: () => UnifiedImageService.downloadImageWithOverlays(
            rawBytes: imageBytes,
            width: originalWidth,
            height: originalHeight,
            context: context,
            labels: labels,
            conePolygons: conePolygons,
            polePolygons: polePolygons,
            detectionItems: detectionItems,
            showOverlays: showOverlays,
            filename: filename,
          ),
          icon: Icons.download,
          tooltip: local.downloadImage,
        ),
        _buildIconButton(
          onPressed: () => UnifiedImageService.copyImageWithOverlays(
            rawBytes: imageBytes,
            width: originalWidth,
            height: originalHeight,
            context: context,
            labels: labels,
            conePolygons: conePolygons,
            polePolygons: polePolygons,
            detectionItems: detectionItems,
            showOverlays: showOverlays,
          ),
          icon: Icons.copy,
          tooltip: local.copyImage,
        ),
        if (shareUri != null)
          _buildIconButton(
            onPressed: () => UnifiedImageService.shareLink(
              uri: shareUri!,
              context: context,
              title: _shareLinkTitle,
            ),
            icon: Icons.share,
            tooltip: local.shareImage,
          ),
      ],
    );
  }
}
