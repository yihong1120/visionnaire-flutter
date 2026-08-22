import 'dart:io' show File, Directory;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../l10n/app_localizations.dart';

/// A page that allows users to capture photos using the device camera.
///
/// Displays a camera preview, a horizontal list of captured photo thumbnails,
/// and controls for taking photos, previewing, removing, and completing the selection.
class CameraCapturePage extends StatefulWidget {
  /// Creates a [CameraCapturePage].
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

/// State for [CameraCapturePage], managing camera control and captured images.
class _CameraCapturePageState extends State<CameraCapturePage> {
  /// The controller for the device camera.
  late final CameraController _controller;

  /// Whether the camera is ready for use.
  bool _ready = false;

  /// The list of captured images.
  final List<XFile> _shots = <XFile>[];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  /// Initialises the camera and sets [_ready] to true when done.
  ///
  /// This method fetches the available cameras, selects the back camera if available,
  /// and initialises the [CameraController].
  ///
  /// If the widget is still mounted after initialisation, it updates the [_ready] state.
  Future<void> _initCamera() async {
    final List<CameraDescription> cams =
        await availableCameras(); // Get all available cameras
    final CameraDescription back = cams.firstWhere(
      (CameraDescription c) =>
          c.lensDirection == CameraLensDirection.back, // Prefer back camera
      orElse: () => cams.first, // Fallback to first camera if no back camera
    );
    _controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await _controller.initialize(); // Initialise the camera controller
    if (mounted) setState(() => _ready = true); // Update state if still mounted
  }

  @override
  void dispose() {
    _controller.dispose(); // Release camera when leaving the page
    super.dispose();
  }

  /// Captures a photo and adds it to [_shots].
  ///
  /// On web, the image is added directly. On mobile/desktop, the image is copied
  /// to a temporary directory with a timestamped filename before being added.
  ///
  /// After capturing, the widget state is updated if still mounted.
  Future<void> _takeShot() async {
    final XFile raw = await _controller.takePicture(); // Capture photo

    if (kIsWeb) {
      _shots.add(raw); // Web: blob URL
    } else {
      final Directory dir = await getTemporaryDirectory(); // Get temp directory
      final File saved = await File(raw.path).copy(
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg'); // Save with timestamp
      _shots.add(XFile(saved.path));
    }
    if (mounted) setState(() {}); // Update state if still mounted
  }

  /// Builds a thumbnail widget for a captured image, with preview and remove options.
  ///
  /// [x] The image file to display as a thumbnail.
  ///
  /// Returns a [Widget] displaying the image as a thumbnail, with tap to preview
  /// and a close button to remove the image from the list.
  Widget _thumb(XFile x) => Stack(
        children: <Widget>[
          InkWell(
            onTap: () => _preview(x), // Tap to preview
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: kIsWeb
                  ? Image.network(x.path, width: 72, fit: BoxFit.cover)
                  : Image.file(File(x.path), width: 72, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: () => setState(() => _shots.remove(x)), // Remove image
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      );

  /// Shows a full-screen preview of the selected image [x].
  ///
  /// Tapping the close icon removes the image and closes the preview.
  /// Tapping outside the image closes the preview without removing the image.
  void _preview(XFile x) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (BuildContext _) => GestureDetector(
        onTap: () => Navigator.pop(context), // Tap outside to close only
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: <Widget>[
              Center(
                child:
                    kIsWeb ? Image.network(x.path) : Image.file(File(x.path)),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: SafeArea(
                  child: IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () {
                      // Remove and close
                      setState(() => _shots.remove(x));
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the widget tree for the camera capture page.
  ///
  /// Shows a loading indicator while the camera is initialising. Once ready,
  /// displays the camera preview, a horizontal list of thumbnails, and controls
  /// for taking photos and completing the selection.
  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          CameraPreview(_controller), // Camera preview

          // Bottom toolbar: thumbnails and controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    height: 80,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _shots
                          .map((XFile x) => Padding(
                                padding: const EdgeInsets.all(4),
                                child: _thumb(x),
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      IconButton(
                        iconSize: 72,
                        onPressed: _takeShot, // Take photo
                        icon: const Icon(Icons.camera, color: Colors.white),
                      ),
                      const SizedBox(width: 32),
                      ElevatedButton(
                        onPressed: () => Navigator.pop<List<XFile>>(
                            context, _shots), // Complete
                        child: Text(AppLocalizations.of(context)!
                            .doneWithCount(_shots.length.toString())),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Top left close button
          SafeArea(
            child: IconButton(
              onPressed: () => Navigator.pop(context), // Close page
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
