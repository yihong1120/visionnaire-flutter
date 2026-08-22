import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

/// Data structure representing a detection item.
///
/// [rect] is the absolute coordinate rectangle (left, top, right, bottom) in the original image.
/// [label] is the object label returned from the backend (e.g., "hardhat", "person", or a number "0~10").
class DetectionItem {
  /// The bounding rectangle of the detected object in the original image.
  final Rect rect;

  /// The label of the detected object.
  final String label;

  /// Creates a [DetectionItem] with the given [rect] and [label].
  DetectionItem({
    required this.rect,
    required this.label,
  });
}

/// Plain strings used by overlay painters.
///
/// Keep this separate from [BuildContext] so painters never depend on inherited
/// widgets after the owning route starts leaving the tree.
@immutable
class DetectionOverlayLabels {
  final String hardhat;
  final String mask;
  final String noHardhat;
  final String noMask;
  final String noVest;
  final String person;
  final String cone;
  final String vest;
  final String machinery;
  final String utilityPole;
  final String vehicle;

  const DetectionOverlayLabels({
    required this.hardhat,
    required this.mask,
    required this.noHardhat,
    required this.noMask,
    required this.noVest,
    required this.person,
    required this.cone,
    required this.vest,
    required this.machinery,
    required this.utilityPole,
    required this.vehicle,
  });

  const DetectionOverlayLabels.fallback()
      : hardhat = '安全帽',
        mask = '口罩',
        noHardhat = '未戴安全帽',
        noMask = '未戴口罩',
        noVest = '無安全背心',
        person = '人員',
        cone = '交通錐',
        vest = '安全背心',
        machinery = '機具',
        utilityPole = '電桿',
        vehicle = '車輛';

  factory DetectionOverlayLabels.fromLocalizations(AppLocalizations local) {
    return DetectionOverlayLabels(
      hardhat: local.hardhat,
      mask: local.mask,
      noHardhat: local.no_hardhat,
      noMask: local.no_mask,
      noVest: local.no_vest,
      person: local.person,
      cone: local.cone,
      vest: local.vest,
      machinery: local.machinery,
      utilityPole: local.utility_pole,
      vehicle: local.vehicle,
    );
  }

  String labelFor(String rawLabel) {
    switch (DetectionOverlayLabels.canonicalKey(rawLabel)) {
      case 'hardhat':
        return hardhat;
      case 'mask':
        return mask;
      case 'no_hardhat':
        return noHardhat;
      case 'no_mask':
        return noMask;
      case 'no_vest':
        return noVest;
      case 'person':
        return person;
      case 'cone':
        return cone;
      case 'vest':
        return vest;
      case 'machinery':
        return machinery;
      case 'utility_pole':
        return utilityPole;
      case 'vehicle':
        return vehicle;
      default:
        return rawLabel;
    }
  }

  Color colorFor(String rawLabel) {
    switch (DetectionOverlayLabels.canonicalKey(rawLabel)) {
      case 'hardhat':
      case 'vest':
        return Colors.green;
      case 'machinery':
        return Colors.orangeAccent;
      case 'vehicle':
        return Colors.yellowAccent;
      case 'no_hardhat':
      case 'no_vest':
        return Colors.red;
      case 'person':
        return Colors.orange;
      case 'cone':
      case 'utility_pole':
        return Colors.blue;
      default:
        return Colors.white;
    }
  }

  static String canonicalKey(String rawLabel) {
    final double? numeric = double.tryParse(rawLabel.trim());
    if (numeric == null ||
        !numeric.isFinite ||
        numeric != numeric.truncateToDouble()) {
      return rawLabel;
    }
    const Map<int, String> idToKey = <int, String>{
      0: 'hardhat',
      1: 'mask',
      2: 'no_hardhat',
      3: 'no_mask',
      4: 'no_vest',
      5: 'person',
      6: 'cone',
      7: 'vest',
      8: 'machinery',
      9: 'utility_pole',
      10: 'vehicle',
    };
    return idToKey[numeric.toInt()] ?? rawLabel;
  }

  @override
  bool operator ==(Object other) {
    return other is DetectionOverlayLabels &&
        hardhat == other.hardhat &&
        mask == other.mask &&
        noHardhat == other.noHardhat &&
        noMask == other.noMask &&
        noVest == other.noVest &&
        person == other.person &&
        cone == other.cone &&
        vest == other.vest &&
        machinery == other.machinery &&
        utilityPole == other.utilityPole &&
        vehicle == other.vehicle;
  }

  @override
  int get hashCode => Object.hash(
        hardhat,
        mask,
        noHardhat,
        noMask,
        noVest,
        person,
        cone,
        vest,
        machinery,
        utilityPole,
        vehicle,
      );
}

///
/// Widget that combines a memory image and overlays (bounding boxes, polygons) for detection visualisation.
///
/// - [rawBytes]: The binary data of the image ([Uint8List]).
/// - [originalWidth], [originalHeight]: The original resolution of the image (for scaling calculations).
/// - [conePolygons]: List of polygons representing safety cones.
/// - [polePolygons]: List of polygons representing utility poles.
/// - [detectionItems]: List of detection bounding boxes (can be empty).
/// - [showOverlays]: Whether to display bounding boxes and polygons.
///
class DetectionOverlayWidget extends StatefulWidget {
  /// The binary data of the image.
  final Uint8List rawBytes;

  /// The original width of the image.
  final double originalWidth;

  /// The original height of the image.
  final double originalHeight;

  /// List of polygons for safety cones.
  final List<List<Offset>> conePolygons;

  /// List of polygons for utility poles.
  final List<List<Offset>> polePolygons;

  /// List of detection items (bounding boxes and labels).
  final List<DetectionItem> detectionItems;

  /// Labels used by the overlay painter.
  final DetectionOverlayLabels labels;

  /// Whether to show overlays (bounding boxes and polygons).
  final bool showOverlays;

  /// Creates a [DetectionOverlayWidget].
  const DetectionOverlayWidget({
    super.key,
    required this.rawBytes,
    required this.originalWidth,
    required this.originalHeight,
    required this.conePolygons,
    required this.polePolygons,
    required this.detectionItems,
    this.labels = const DetectionOverlayLabels.fallback(),
    required this.showOverlays,
  });

  @override
  State<DetectionOverlayWidget> createState() => _DetectionOverlayWidgetState();
}

class _DetectionOverlayWidgetState extends State<DetectionOverlayWidget> {
  int _paintRevision = 0;
  bool _overlayWarmupQueued = false;
  Timer? _overlayWarmupTimer;

  @override
  void initState() {
    super.initState();
    _queueOverlayWarmupRepaint();
  }

  @override
  void didUpdateWidget(covariant DetectionOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showOverlays != oldWidget.showOverlays ||
        widget.rawBytes != oldWidget.rawBytes ||
        widget.labels != oldWidget.labels ||
        widget.detectionItems != oldWidget.detectionItems ||
        widget.conePolygons != oldWidget.conePolygons ||
        widget.polePolygons != oldWidget.polePolygons) {
      _queueOverlayWarmupRepaint();
    }
  }

  void _queueOverlayWarmupRepaint() {
    if (!widget.showOverlays || _overlayWarmupQueued) return;

    _overlayWarmupQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _paintRevision++);

      // Flutter Web can paint canvas text before the browser finishes resolving
      // CJK fonts on a direct URL load. One settled-frame repaint keeps labels
      // correct without requiring users to toggle the overlay manually.
      _overlayWarmupTimer = Timer(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        setState(() => _paintRevision++);
        _overlayWarmupQueued = false;
        _overlayWarmupTimer = null;
      });
    });
  }

  @override
  void dispose() {
    _overlayWarmupTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double aspectRatio = widget.originalHeight == 0
        ? 1
        : widget.originalWidth / widget.originalHeight;

    // Use AspectRatio to maintain the image's aspect ratio.
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            RepaintBoundary(
              child: Image.memory(
                widget.rawBytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
            ),
            if (widget.showOverlays)
              RepaintBoundary(
                child: CustomPaint(
                  isComplex: true,
                  willChange: false,
                  painter: OverlayPainter(
                    conePolygons: widget.conePolygons,
                    polePolygons: widget.polePolygons,
                    detectionItems: widget.detectionItems,
                    labels: widget.labels,
                    originalWidth: widget.originalWidth,
                    originalHeight: widget.originalHeight,
                    paintRevision: _paintRevision,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for drawing cone polygons, pole polygons, detection boxes, and label text overlays on a canvas.
class OverlayPainter extends CustomPainter {
  static const List<String> _cjkFontFallbacks = <String>[
    'Noto Sans TC',
    'Noto Sans CJK TC',
    'PingFang TC',
    'Microsoft JhengHei',
    'Arial Unicode MS',
    'sans-serif',
  ];

  /// List of polygons for safety cones.
  final List<List<Offset>> conePolygons;

  /// List of polygons for utility poles.
  final List<List<Offset>> polePolygons;

  /// List of detection items (bounding boxes and labels).
  final List<DetectionItem> detectionItems;

  /// Plain label strings used while painting.
  final DetectionOverlayLabels labels;

  /// The original width of the image.
  final double originalWidth;

  /// The original height of the image.
  final double originalHeight;

  /// Forces repaint after first web font/layout settling when needed.
  final int paintRevision;

  /// Creates an [OverlayPainter].
  OverlayPainter({
    required this.conePolygons,
    required this.polePolygons,
    required this.detectionItems,
    DetectionOverlayLabels labels = const DetectionOverlayLabels.fallback(),
    AppLocalizations? localizations,
    required this.originalWidth,
    required this.originalHeight,
    this.paintRevision = 0,
  }) : labels = localizations == null
            ? labels
            : DetectionOverlayLabels.fromLocalizations(localizations);

  /// Static method to draw overlays on any canvas with consistent logic.
  /// This ensures both display and export use the same rendering.
  static void drawOverlays({
    required Canvas canvas,
    required Size size,
    required List<List<Offset>> conePolygons,
    required List<List<Offset>> polePolygons,
    required List<DetectionItem> detectionItems,
    DetectionOverlayLabels labels = const DetectionOverlayLabels.fallback(),
    AppLocalizations? localizations,
    required double originalWidth,
    required double originalHeight,
  }) {
    final DetectionOverlayLabels effectiveLabels = localizations == null
        ? labels
        : DetectionOverlayLabels.fromLocalizations(localizations);

    // Scale factors to map original image coordinates to the current canvas size.
    final double scaleX = size.width / originalWidth;
    final double scaleY = size.height / originalHeight;

    // ----------------------------
    // (1) Draw safety cone polygons (pink)
    // ----------------------------
    final Paint coneFillPaint = Paint()
      ..color = Colors.pinkAccent.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    final Paint coneStrokePaint = Paint()
      ..color = Colors.pink
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final Path path in OverlayPainter.buildPolygonPaths(
      conePolygons,
      scaleX: scaleX,
      scaleY: scaleY,
    )) {
      canvas.drawPath(path, coneFillPaint);
      canvas.drawPath(path, coneStrokePaint);
    }

    // ----------------------------
    // (2) Draw utility pole polygons (blue)
    // ----------------------------
    final Paint poleFillPaint = Paint()
      ..color = Colors.blueAccent.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    final Paint poleStrokePaint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final Path path in OverlayPainter.buildPolygonPaths(
      polePolygons,
      scaleX: scaleX,
      scaleY: scaleY,
    )) {
      canvas.drawPath(path, poleFillPaint);
      canvas.drawPath(path, poleStrokePaint);
    }

    for (final DetectionItem item in detectionItems) {
      // 1) Map label to localised string
      final String localisedLabel = effectiveLabels.labelFor(item.label);

      // 2) Skip drawing bounding box for cones
      if (DetectionOverlayLabels.canonicalKey(item.label) == 'cone') {
        continue; // Skip bounding box for cones
      }

      // Determine the colour for the bounding box (default to white if not found)
      final Color colour = effectiveLabels.colorFor(item.label);

      // Calculate the scaled bounding box position and ensure it's within canvas bounds
      final Rect originalRect = Rect.fromLTRB(
        item.rect.left * scaleX,
        item.rect.top * scaleY,
        item.rect.right * scaleX,
        item.rect.bottom * scaleY,
      );

      // Clamp the rectangle to canvas bounds
      final Rect rect = Rect.fromLTRB(
        math.max(0, originalRect.left),
        math.max(0, originalRect.top),
        math.min(size.width, originalRect.right),
        math.min(size.height, originalRect.bottom),
      );

      // Draw the bounding box
      final Paint boxPaint = Paint()
        ..color = colour
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawRect(rect, boxPaint);

      // Draw the label text with black stroke (outline) for better visibility
      final TextSpan textSpan = TextSpan(
        text: localisedLabel,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          fontFamilyFallback: _cjkFontFallbacks,
        ),
      );
      final TextPainter textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Create text with black stroke for TV subtitle effect
      final TextSpan strokeTextSpan = TextSpan(
        text: localisedLabel,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          fontFamilyFallback: _cjkFontFallbacks,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.black,
        ),
      );
      final TextPainter strokeTextPainter = TextPainter(
        text: strokeTextSpan,
        textDirection: TextDirection.ltr,
      );
      strokeTextPainter.layout();

      // Calculate label position - prioritize top, then left/right based on box position
      late Offset labelPosition;
      late Rect textBgRect;

      const double padding = 4.0;
      const double spacing = 2.0;

      // Determine if the box is in the left or right half of the image
      final bool isBoxInLeftHalf =
          (rect.left + rect.right) / 2 < size.width / 2;

      // Try placing label above the box
      if (rect.top - textPainter.height - padding >= 0) {
        // Label above the box
        labelPosition = Offset(
          math.max(
              0, math.min(size.width - textPainter.width - padding, rect.left)),
          rect.top - textPainter.height - spacing,
        );
        textBgRect = Rect.fromLTWH(
          labelPosition.dx - spacing,
          labelPosition.dy - spacing,
          textPainter.width + padding,
          textPainter.height + padding,
        );
      }
      // For boxes in left half, try placing label to the right (right-top corner)
      else if (isBoxInLeftHalf &&
          rect.right + textPainter.width + padding <= size.width) {
        labelPosition = Offset(
          rect.right + spacing,
          math.max(0, rect.top),
        );
        textBgRect = Rect.fromLTWH(
          labelPosition.dx - spacing,
          labelPosition.dy - spacing,
          textPainter.width + padding,
          textPainter.height + padding,
        );
      }
      // For boxes in right half, try placing label to the left (left-top corner)
      else if (!isBoxInLeftHalf &&
          rect.left - textPainter.width - padding >= 0) {
        labelPosition = Offset(
          rect.left - textPainter.width - spacing,
          math.max(0, rect.top),
        );
        textBgRect = Rect.fromLTWH(
          labelPosition.dx - spacing,
          labelPosition.dy - spacing,
          textPainter.width + padding,
          textPainter.height + padding,
        );
      }
      // General left/right fallbacks were redundant with the half-specific branches above and
      // are intentionally omitted as they are unreachable given the prior conditions.
      // Final fallback: place inside the box at top-left corner
      else {
        labelPosition = Offset(
          rect.left + spacing,
          rect.top + spacing,
        );
        textBgRect = Rect.fromLTWH(
          labelPosition.dx - spacing,
          labelPosition.dy - spacing,
          math.min(textPainter.width + padding, rect.width - spacing),
          math.min(textPainter.height + padding, rect.height - spacing),
        );
      }

      // Draw label background (semi-transparent)
      final Paint bgPaint = Paint()..color = colour.withValues(alpha: 0.7);
      canvas.drawRect(textBgRect, bgPaint);

      // Draw text stroke (black outline) first
      strokeTextPainter.paint(canvas, labelPosition);

      // Draw text fill (white) on top
      textPainter.paint(canvas, labelPosition);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Use the static method for consistent rendering
    OverlayPainter.drawOverlays(
      canvas: canvas,
      size: size,
      conePolygons: conePolygons,
      polePolygons: polePolygons,
      detectionItems: detectionItems,
      labels: labels,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
    );
  }

  /// Static helper method to map backend label (number/string) to a localised string.
  ///
  /// [rawLabel] is the label from the backend.
  /// [local] is the localisation instance.
  /// Returns the localised string for the label.
  static String mapLabelToLocalString(String rawLabel, AppLocalizations local) {
    return DetectionOverlayLabels.fromLocalizations(local).labelFor(rawLabel);
  }

  /// Static helper method to sort points by angle from the geometric centre to avoid polygon drawing order issues.
  ///
  /// [points] is the list of points to sort.
  /// Returns a new list of points sorted by angle.
  static List<Offset> sortPointsByAngle(List<Offset> points) {
    if (points.length <= 2) return points;
    double sumX = 0, sumY = 0;
    for (final Offset p in points) {
      sumX += p.dx;
      sumY += p.dy;
    }
    final Offset centre = Offset(sumX / points.length, sumY / points.length);

    final List<Offset> sorted = List<Offset>.from(points);
    sorted.sort((Offset a, Offset b) {
      final double angleA = math.atan2(a.dy - centre.dy, a.dx - centre.dx);
      final double angleB = math.atan2(b.dy - centre.dy, b.dx - centre.dx);
      return angleA.compareTo(angleB);
    });
    return sorted;
  }

  static List<Path> buildPolygonPaths(
    List<List<Offset>> polygons, {
    required double scaleX,
    required double scaleY,
  }) {
    final List<Path> paths = <Path>[];
    for (final List<Offset> polygon in polygons) {
      if (polygon.isEmpty) continue;
      final List<Offset> scaledPolygon = polygon
          .map((Offset p) => Offset(p.dx * scaleX, p.dy * scaleY))
          .toList(growable: false);
      final List<Offset> sortedPolygon =
          OverlayPainter.sortPointsByAngle(scaledPolygon);
      paths.add(Path()..addPolygon(sortedPolygon, true));
    }
    return paths;
  }

  /// Maps backend label (number/string) to a localised string.
  ///
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is! OverlayPainter) return true;

    // 只有在檢測資料真正改變時才重繪
    return !_listsEqual(conePolygons, oldDelegate.conePolygons) ||
        !_listsEqual(polePolygons, oldDelegate.polePolygons) ||
        !_detectionsEqual(detectionItems, oldDelegate.detectionItems) ||
        labels != oldDelegate.labels ||
        originalWidth != oldDelegate.originalWidth ||
        originalHeight != oldDelegate.originalHeight ||
        paintRevision != oldDelegate.paintRevision;
  }

  /// 比較兩個多邊形列表是否相等
  bool _listsEqual(List<List<Offset>> list1, List<List<Offset>> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].length != list2[i].length) return false;
      for (int j = 0; j < list1[i].length; j++) {
        if (list1[i][j] != list2[i][j]) return false;
      }
    }
    return true;
  }

  /// 比較兩個檢測項目列表是否相等
  bool _detectionsEqual(List<DetectionItem> list1, List<DetectionItem> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].rect != list2[i].rect || list1[i].label != list2[i].label) {
        return false;
      }
    }
    return true;
  }
}
