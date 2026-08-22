import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:visionnaire/l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/unified_auth_provider.dart';
import '../../services/detection_api_service.dart';
import '../../widgets/detection_painter.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../widgets/unified_image_action_buttons.dart';

/// A page for performing object detection on images using selectable models.
///
/// Users can pick or capture an image, select a detection model, and view detection results
/// with overlays and a summary table. Handles token refresh, error display, and responsive layout.
class DetectionPage extends StatefulWidget {
  /// Creates a [DetectionPage].
  const DetectionPage({super.key});

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

/// State for [DetectionPage], managing image selection, detection, and result display.
class _DetectionPageState extends State<DetectionPage> {
  /// The selected image file for detection.
  XFile? _imageFile;

  /// Cached bytes for the selected image. Build methods must not read files.
  Uint8List? _imageBytes;

  /// The selected detection model key.
  String _model = "yolo26n";

  /// Whether a detection operation is in progress.
  bool _isLoading = false;

  /// Error message to display, if any.
  String? _error;

  /// Detection overlay items derived once when results change.
  List<DetectionItem> _detectionItems = <DetectionItem>[];

  /// Per-label counts derived once when results change.
  Map<String, int> _detectionCounts = const <String, int>{};

  /// The width of the original image (double for precision).
  double _imageWidth = 0.0;

  /// The height of the original image (double for precision).
  double _imageHeight = 0.0;

  /// Whether to show detection overlays on the image.
  bool _showOverlays = true;

  /// List of polygons for cones, as returned by the backend.
  List<List<Offset>> _conePolygons = <List<Offset>>[];

  /// List of polygons for poles, as returned by the backend.
  List<List<Offset>> _polePolygons = <List<Offset>>[];

  /// All known label keys, used for displaying counts in the summary table.
  final List<String> _allLabelsKey = <String>[
    'hardhat',
    'mask',
    'no_hardhat',
    'no_mask',
    'no_vest',
    'person',
    'cone',
    'vest',
    'machinery',
    'utility_pole',
    'vehicle',
  ];

  @override
  Widget build(BuildContext context) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    final DetectionOverlayLabels overlayLabels =
        DetectionOverlayLabels.fromLocalizations(local);
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return ResponsiveScaffold(
      title: local.detection,
      body: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: <Widget>[
              _buildModelSelector(),
              const SizedBox(height: 16),
              _buildOverlaySwitch(local),
              const SizedBox(height: 16),

              /// Use LayoutBuilder to provide responsive layout for wide and narrow screens.
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  if (constraints.maxWidth >= 800) {
                    // Wide screen: image and table side by side.
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _buildImageCard(local, overlayLabels),
                          const SizedBox(width: 24),
                          _buildDetectionDataTable(local, isDarkMode),
                        ],
                      ),
                    );
                  } else {
                    // Narrow screen: image and table stacked vertically.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildImageCard(local, overlayLabels),
                        const SizedBox(height: 24),
                        _buildDetectionDataTable(local, isDarkMode),
                      ],
                    );
                  }
                },
              ),

              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              _buildActionButtons(local),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the model selector dropdown.
  ///
  /// Allows the user to choose which detection model to use.
  Widget _buildModelSelector() {
    final AppLocalizations local = AppLocalizations.of(context)!;
    return Row(
      children: <Widget>[
        Text(local.chooseModel),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: _model,
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem(value: "yolo26n", child: Text("YOLO26n")),
            DropdownMenuItem(value: "yolo26s", child: Text("YOLO26s")),
            DropdownMenuItem(value: "yolo26m", child: Text("YOLO26m")),
            DropdownMenuItem(value: "yolo26l", child: Text("YOLO26l")),
            DropdownMenuItem(value: "yolo26x", child: Text("YOLO26x")),
          ],
          onChanged: (String? val) {
            if (!mounted || val == null) return;
            setState(() => _model = val);
          },
        ),
      ],
    );
  }

  /// Builds the switch to show or hide detection overlays.
  ///
  /// [local] The localisation object for text.
  Widget _buildOverlaySwitch(AppLocalizations local) {
    return Row(
      children: <Widget>[
        Text(local.showOverlay),
        Switch(
          value: _showOverlays,
          onChanged: (bool val) {
            setState(() => _showOverlays = val);
          },
        ),
      ],
    );
  }

  /// Builds the image display card, including overlays and detection results.
  ///
  /// [local] The localisation object for text.
  Widget _buildImageCard(
    AppLocalizations local,
    DetectionOverlayLabels overlayLabels,
  ) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color placeholderColor = colors.surfaceContainerHighest;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 4,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // If no image is selected, show a placeholder.
          if (_imageFile == null) {
            final double availableWidth = constraints.maxWidth;
            final double displayWidth =
                availableWidth >= 640 ? 640 : availableWidth;
            return Container(
              width: displayWidth,
              height: 480,
              color: placeholderColor,
              child: Center(child: Text(local.noImageSelected)),
            );
          }

          final Uint8List? bytes = _imageBytes;
          if (bytes == null) {
            return const Center(child: CircularProgressIndicator());
          }

          // Use original image dimensions, avoid division by zero.
          final double origWidth = (_imageWidth <= 0.0) ? 1.0 : _imageWidth;
          final double origHeight = (_imageHeight <= 0.0) ? 1.0 : _imageHeight;

          // Calculate ideal display size, max 640x480.
          const double maxImageWidth = 640;
          const double maxImageHeight = 480;
          final double scaleFactor = math.min(
            math.min(maxImageWidth / origWidth, maxImageHeight / origHeight),
            1.0,
          );
          final double intrinsicWidth = origWidth * scaleFactor;
          final double intrinsicHeight = origHeight * scaleFactor;

          // Adjust for available width.
          final double availableWidth = constraints.maxWidth;
          final double displayWidth =
              availableWidth < intrinsicWidth ? availableWidth : intrinsicWidth;
          final double displayHeight =
              displayWidth * (intrinsicHeight / intrinsicWidth);

          return Column(
            children: [
              Center(
                child: SizedBox(
                  width: displayWidth,
                  height: displayHeight,

                  // DetectionOverlayWidget displays the image and overlays.
                  child: DetectionOverlayWidget(
                    rawBytes: bytes,
                    originalWidth: origWidth,
                    originalHeight: origHeight,
                    conePolygons: _conePolygons,
                    polePolygons: _polePolygons,
                    detectionItems: _detectionItems,
                    labels: overlayLabels,
                    showOverlays: _showOverlays,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Image action buttons - use unified component
              UnifiedImageActionIconButtons(
                imageBytes: bytes,
                originalWidth: origWidth,
                originalHeight: origHeight,
                conePolygons: _conePolygons,
                polePolygons: _polePolygons,
                detectionItems: _detectionItems,
                labels: overlayLabels,
                showOverlays: _showOverlays,
                filename: 'detection_image',
              ),
            ],
          );
        },
      ),
    );
  }

  /// Builds a DataTable showing all known labels and their detected counts.
  ///
  /// [local] The localisation object for text.
  /// [isDarkMode] Whether the app is in dark mode.
  Widget _buildDetectionDataTable(AppLocalizations local, bool isDarkMode) {
    final List<DataRow> rows = <DataRow>[];
    for (final String key in _allLabelsKey) {
      final String labelName = _mapLocalKeyToLocalizedString(key, local);
      final int cnt = _detectionCounts[key] ?? 0;
      rows.add(
        DataRow(
          cells: <DataCell>[
            DataCell(Text(labelName)),
            DataCell(Text(cnt.toString())),
          ],
        ),
      );
    }

    final ColorScheme colors = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[colors.primary, colors.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              children: <Widget>[
                Text(
                  local.detectionResult,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? colors.surfaceContainerHighest
                        : colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DataTable(
                    columns: <DataColumn>[
                      DataColumn(label: Text(local.label)),
                      const DataColumn(label: Text("Count")),
                    ],
                    rows: rows,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the action buttons for picking images and starting detection.
  ///
  /// [local] The localisation object for text.
  Widget _buildActionButtons(AppLocalizations local) {
    return Column(
      children: <Widget>[
        if (_isLoading)
          const CircularProgressIndicator()
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.photo_camera),
                  label: Text(local.takePhoto),
                  onPressed: _pickImageFromCamera,
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.photo_library),
                  label: Text(local.photoLibrary),
                  onPressed: _pickImageFromGallery,
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed:
              _imageFile == null || _isLoading ? null : _performDetection,
          child: Text(local.startDetection),
        ),
      ],
    );
  }

  /// Picks an image from the camera and updates state.
  ///
  /// Clears previous detection results and polygons. Updates image size after selection.
  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? picked =
          await ImagePicker().pickImage(source: ImageSource.camera);
      if (picked != null && mounted) {
        setState(() {
          _imageFile = picked;
          _imageBytes = null;
          _clearDetectionState();
        });
        await _setPickedImage(picked);
      }
    } catch (e) {
      if (!mounted) return;
      final AppLocalizations local = AppLocalizations.of(context)!;
      setState(() {
        _error = "${local.cannotOpenCamera}: $e";
      });
    }
  }

  /// Picks an image from the gallery and updates state.
  ///
  /// Clears previous detection results and polygons. Updates image size after selection.
  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? picked =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked != null && mounted) {
        setState(() {
          _imageFile = picked;
          _imageBytes = null;
          _clearDetectionState();
        });
        await _setPickedImage(picked);
      }
    } catch (e) {
      if (!mounted) return;
      final AppLocalizations local = AppLocalizations.of(context)!;
      setState(() {
        _error = "${local.cannotOpenGallery}: $e";
      });
    }
  }

  void _clearDetectionState() {
    _detectionItems = <DetectionItem>[];
    _detectionCounts = _emptyDetectionCounts();
    _conePolygons = <List<Offset>>[];
    _polePolygons = <List<Offset>>[];
  }

  Map<String, int> _emptyDetectionCounts() {
    return <String, int>{for (final String key in _allLabelsKey) key: 0};
  }

  /// Reads and decodes the selected image once, then caches bytes and size.
  ///
  /// Sets error message if decoding fails.
  Future<void> _setPickedImage(XFile imageFile) async {
    try {
      final Uint8List bytes = await imageFile.readAsBytes();
      final decodedImage = await decodeImageFromList(bytes);
      final double imageWidth = decodedImage.width.toDouble();
      final double imageHeight = decodedImage.height.toDouble();
      decodedImage.dispose();

      if (!mounted) return;
      setState(() {
        _imageFile = imageFile;
        _imageBytes = bytes;
        _imageWidth = imageWidth;
        _imageHeight = imageHeight;
      });
    } catch (e) {
      if (!mounted) return;
      final AppLocalizations local = AppLocalizations.of(context)!;
      setState(() {
        _error = "${local.getImageSizeFailed}: $e";
      });
    }
  }

  /// Performs object detection by sending the image to the backend API.
  ///
  /// Handles token refresh, error display, and updates detection results.
  Future<void> _performDetection() async {
    final AppLocalizations local = AppLocalizations.of(context)!;

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _clearDetectionState();
    });

    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    final String? token = auth.requestToken;
    if (token == null) {
      setState(() {
        _error = local.notLoggedIn;
        _isLoading = false;
      });
      return;
    }

    try {
      // Call backend API for detection.
      final List<dynamic> results = await DetectionAPIService.detectObjects(
        imageFile: _imageFile!,
        imageBytes: _imageBytes,
        filename: _imageFile?.name,
        model: _model,
        token: token,
      );

      // (C) If backend returns cone_polygons and pole_polygons, parse here.
      // final conePolygonsData = results["cone_polygons"];
      // final polePolygonsData = results["pole_polygons"];
      // _conePolygons = _parsePolygons(conePolygonsData);
      // _polePolygons = _parsePolygons(polePolygonsData);

      if (!mounted) return;
      setState(() {
        // Here, assume results only contains bounding boxes.
        _setDetectionResults(results);
      });
    } catch (e) {
      final String errStr = e.toString();
      if (errStr.contains("expired_token") ||
          errStr.contains("invalid") ||
          errStr.contains("replaced")) {
        // If token is invalid, attempt refresh.
        try {
          await auth.refreshIfNeeded();
          final String? newToken = auth.requestToken;
          if (newToken == null) throw Exception(local.tokenRefreshFailed);
          // Retry detection with new token.
          final List<dynamic> results = await DetectionAPIService.detectObjects(
            imageFile: _imageFile!,
            imageBytes: _imageBytes,
            filename: _imageFile?.name,
            model: _model,
            token: newToken,
          );
          if (!mounted) return;
          setState(() {
            _setDetectionResults(results);
          });
        } catch (secondErr) {
          if (!mounted) return;
          setState(() {
            _error = "${local.tokenRefreshFailed}: $secondErr";
          });
        }
      } else {
        setState(() {
          _error = errStr;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _setDetectionResults(List<dynamic> results) {
    final items = <DetectionItem>[];
    final counts = _emptyDetectionCounts();

    for (final dynamic result in results) {
      if (result is! List<dynamic> || result.length < 6) continue;

      final double x1 = result[0].toDouble();
      final double y1 = result[1].toDouble();
      final double x2 = result[2].toDouble();
      final double y2 = result[3].toDouble();
      final String label = result[5].toString();

      items.add(
        DetectionItem(
          rect: Rect.fromLTRB(x1, y1, x2, y2),
          label: label,
        ),
      );

      final String localKey = _mapLabelToKey(label);
      if (counts.containsKey(localKey)) {
        counts[localKey] = counts[localKey]! + 1;
      }
    }

    _detectionItems = items;
    _detectionCounts = counts;
  }

  /// Maps backend classId or label string to a known label key for counting.
  ///
  /// [rawLabel] The raw label or classId from the backend.
  /// Returns a known label key string.
  String _mapLabelToKey(String rawLabel) {
    final int? numeric = int.tryParse(rawLabel);
    if (numeric != null) {
      switch (numeric) {
        case 0:
          return 'hardhat';
        case 1:
          return 'mask';
        case 2:
          return 'no_hardhat';
        case 3:
          return 'no_mask';
        case 4:
          return 'no_vest';
        case 5:
          return 'person';
        case 6:
          return 'cone';
        case 7:
          return 'vest';
        case 8:
          return 'machinery';
        case 9:
          return 'utility_pole';
        case 10:
          return 'vehicle';
      }
    }
    return rawLabel;
  }

  /// Maps a known label key to a localised string for display.
  ///
  /// [key] The label key.
  /// [local] The localisation object.
  /// Returns the localised label string.
  String _mapLocalKeyToLocalizedString(String key, AppLocalizations local) {
    switch (key) {
      case 'hardhat':
        return local.hardhat;
      case 'mask':
        return local.mask;
      case 'no_hardhat':
        return local.no_hardhat;
      case 'no_mask':
        return local.no_mask;
      case 'no_vest':
        return local.no_vest;
      case 'person':
        return local.person;
      case 'cone':
        return local.cone;
      case 'vest':
        return local.vest;
      case 'machinery':
        return local.machinery;
      case 'utility_pole':
        return local.utility_pole;
      case 'vehicle':
        return local.vehicle;
      default:
        return key; // fallback
    }
  }
}
