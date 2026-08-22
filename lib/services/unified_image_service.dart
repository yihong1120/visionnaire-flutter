import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:camera/camera.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';

import '../utils/cross_platform_download.dart';
import '../widgets/detection_painter.dart';
import '../widgets/app_transitions.dart';

/// Enumeration for date stamp position on images.
///
/// Defines where the date stamp should be placed when adding timestamps to images.
enum DateStampPosition {
  /// Position the date stamp at the top-left corner.
  topLeft,

  /// Position the date stamp at the top-right corner.
  topRight,

  /// Position the date stamp at the bottom-left corner.
  bottomLeft,

  /// Position the date stamp at the bottom-right corner.
  bottomRight,
}

class _ImageActionFeedback {
  const _ImageActionFeedback({
    required this.messenger,
    required this.colors,
  });

  final ScaffoldMessengerState messenger;
  final ColorScheme colors;

  static _ImageActionFeedback? maybe(
    BuildContext? context, {
    required bool enabled,
  }) {
    if (!enabled || context == null) return null;
    return _ImageActionFeedback(
      messenger: ScaffoldMessenger.of(context),
      colors: Theme.of(context).colorScheme,
    );
  }

  void showInfo(String message) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: colors.onPrimary),
        ),
        backgroundColor: colors.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void showError(String message) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: colors.onError),
        ),
        backgroundColor: colors.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

/// Unified image service for handling all image and multimedia operations.
///
/// This service integrates all image and multimedia-related operations, including:
/// - Image processing (adding timestamps, encoding/decoding, etc.)
/// - Image selection and camera capture
/// - Image operations (download, copy, share)
/// - Advanced image operations with overlay layers
/// - Clipboard operations (text and images)
/// - Cross-platform file saving
class UnifiedImageService {
  /// The image picker instance used for selecting images from gallery or camera.
  static final image_picker.ImagePicker _picker = image_picker.ImagePicker();

  // ==================== Basic Image Processing ====================

  /// Adds a date stamp to an image.
  ///
  /// [srcBytes] The source image byte data.
  /// [dateText] The date text to add to the image.
  /// [color] The text colour, defaults to red.
  /// [fontSize] The text size ratio relative to image height, defaults to 0.07.
  /// [position] The text position, defaults to bottom-right corner.
  ///
  /// Returns the image byte data with the date stamp added.
  static Future<Uint8List> stampDate(
    Uint8List srcBytes,
    String dateText, {
    Color color = const Color(0xFFFF0000),
    double fontSize = 0.07,
    DateStampPosition position = DateStampPosition.bottomRight,
  }) async {
    ui.Image? src;
    ui.Image? outImg;
    try {
      // Decode the image
      final ui.Codec codec = await ui.instantiateImageCodec(srcBytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      src = frame.image;
      final double w = src.width.toDouble();
      final double h = src.height.toDouble();

      // Prepare the canvas
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas =
          ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, w, h));
      canvas.drawImage(src, ui.Offset.zero, ui.Paint());

      // Define text style
      final ui.TextStyle textStyle = ui.TextStyle(
        color: color,
        fontSize: h * fontSize,
        fontWeight: ui.FontWeight.bold,
      );

      // Build text paragraph
      final ui.Paragraph paragraph = (ui.ParagraphBuilder(
        ui.ParagraphStyle(textDirection: ui.TextDirection.ltr),
      )
            ..pushStyle(textStyle)
            ..addText(dateText))
          .build()
        ..layout(ui.ParagraphConstraints(width: w));

      // Calculate text position
      ui.Offset textOffset;
      switch (position) {
        case DateStampPosition.topLeft:
          textOffset = const ui.Offset(8, 8);
          break;
        case DateStampPosition.topRight:
          textOffset = ui.Offset(w - paragraph.maxIntrinsicWidth - 8, 8);
          break;
        case DateStampPosition.bottomLeft:
          textOffset = ui.Offset(8, h - paragraph.height - 8);
          break;
        case DateStampPosition.bottomRight:
          textOffset = ui.Offset(
            w - paragraph.maxIntrinsicWidth - 8,
            h - paragraph.height - 8,
          );
          break;
      }

      // Draw the text
      canvas.drawParagraph(paragraph, textOffset);

      // Convert to byte data
      outImg = await recorder.endRecording().toImage(
            src.width,
            src.height,
          );
      final ByteData? data =
          await outImg.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw Exception('Failed to encode image with date stamp.');
      }
      return data.buffer.asUint8List();
    } finally {
      outImg?.dispose();
      src?.dispose();
    }
  }

  /// Decodes image bytes to a ui.Image object.
  ///
  /// [bytes] The image byte data to decode.
  ///
  /// Returns the decoded ui.Image object.
  static Future<ui.Image> decodeImage(Uint8List bytes) async {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image image) {
      completer.complete(image);
    });
    return completer.future;
  }

  /// Converts a ui.Image to byte data.
  ///
  /// [image] The ui.Image object to convert.
  /// [format] The image format, defaults to PNG.
  ///
  /// Returns the image byte data.
  static Future<Uint8List> encodeImage(
    ui.Image image, {
    ui.ImageByteFormat format = ui.ImageByteFormat.png,
  }) async {
    final ByteData? byteData = await image.toByteData(format: format);
    if (byteData == null) {
      throw Exception('Failed to encode image');
    }
    return byteData.buffer.asUint8List();
  }

  // ==================== Image Selection and Camera Capture ====================

  /// Selects multiple images from the gallery.
  ///
  /// [imageQuality] The image quality (1-100, defaults to 85).
  ///
  /// Returns a list of selected image files.
  static Future<List<image_picker.XFile>> pickMultiImage(
      {int imageQuality = 85}) async {
    return await _picker.pickMultiImage(imageQuality: imageQuality);
  }

  /// Selects a single image from camera or gallery.
  ///
  /// [fromCamera] Whether to capture from camera; if false, selects from gallery.
  /// [imageQuality] The image quality (1-100, defaults to 85).
  ///
  /// Returns the selected image file, or null if cancelled.
  static Future<image_picker.XFile?> pickSingleImage({
    required bool fromCamera,
    int imageQuality = 85,
  }) async {
    return await _picker.pickImage(
      source: fromCamera
          ? image_picker.ImageSource.camera
          : image_picker.ImageSource.gallery,
      imageQuality: imageQuality,
    );
  }

  /// Opens camera page or allows selection of multiple images.
  ///
  /// [context] The build context.
  /// [cameraPage] The custom camera page widget.
  ///
  /// Returns a list of captured or selected image files.
  static Future<List<image_picker.XFile>> openCameraOrPickMulti(
    BuildContext context,
    Widget cameraPage,
  ) async {
    List<CameraDescription> cameras = <CameraDescription>[];
    try {
      cameras = await availableCameras();
    } catch (_) {}

    if (cameras.isEmpty) {
      return await pickMultiImage();
    }

    if (!context.mounted) return <image_picker.XFile>[];

    final List<image_picker.XFile>? shots =
        await pushAppPage<List<image_picker.XFile>>(
      context,
      builder: (_) => cameraPage,
    );

    if (shots == null || shots.isEmpty) {
      return await pickMultiImage();
    }

    return shots;
  }

  /// Shows a dialogue to select image source for a single image.
  ///
  /// [context] The build context.
  /// [cameraLabel] The camera button label, defaults to "Camera".
  /// [galleryLabel] The gallery button label, defaults to "Gallery".
  /// [titleLabel] The dialogue title, defaults to "Choose source".
  ///
  /// Returns the selected image file, or null if cancelled.
  static Future<image_picker.XFile?> pickSingleWithDialog(
    BuildContext context, {
    String cameraLabel = 'Camera',
    String galleryLabel = 'Gallery',
    String titleLabel = 'Choose source',
  }) async {
    final String? choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titleLabel),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: Text(cameraLabel),
              onPressed: () => Navigator.pop(context, 'camera'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.collections),
              label: Text(galleryLabel),
              onPressed: () => Navigator.pop(context, 'gallery'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return null;
    return await pickSingleImage(fromCamera: choice == 'camera');
  }

  // ==================== Basic Image Operations ====================

  /// Downloads an image to device storage.
  ///
  /// [imageBytes] The image data to download.
  /// [filename] Optional filename prefix (timestamp will be added).
  /// [context] The build context for displaying messages.
  /// [showNotification] Whether to show success/failure notifications.
  ///
  /// Returns true if the operation succeeds, false otherwise.
  static Future<bool> downloadImage({
    required Uint8List imageBytes,
    String? filename,
    BuildContext? context,
    bool showNotification = true,
  }) async {
    try {
      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      final String actualFilename = filename ?? 'visionnaire_image';

      if (kIsWeb) {
        // Web platform: trigger download
        CrossPlatformDownload.downloadImage(
          imageBytes,
          '${actualFilename}_$timestamp.png',
        );

        if (showNotification && context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image download started'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Mobile platform: save to gallery
        // Create temp file for gal
        final Directory tempDir = await getTemporaryDirectory();
        final File tempFile =
            File('${tempDir.path}/${actualFilename}_$timestamp.png');
        await tempFile.writeAsBytes(imageBytes);

        await Gal.putImage(tempFile.path);

        // Clean up temp file
        await tempFile.delete();

        if (showNotification && context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image saved to gallery'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
      return true;
    } catch (e) {
      if (showNotification && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
  }

  /// Copies an image to the system clipboard.
  ///
  /// [imageBytes] The image byte data to copy.
  /// [context] The BuildContext for displaying error messages (optional).
  /// [showNotification] Whether to show success/failure notifications.
  ///
  /// Returns true if the operation succeeds, false otherwise.
  static Future<bool> copyImage(
    Uint8List imageBytes,
    BuildContext? context, {
    bool showNotification = true,
  }) async {
    try {
      // Use super_clipboard for unified cross-platform handling
      final SystemClipboard? clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        throw Exception('Clipboard API not available on this platform');
      }

      final DataWriterItem item = DataWriterItem();
      item.add(Formats.png(imageBytes));
      await clipboard.write([item]);

      if (showNotification && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image copied to clipboard'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Image copy failed: $e');

      // If super_clipboard fails, try Web platform fallback
      if (kIsWeb) {
        // Check if context is still mounted before passing to fallback
        if (context != null && !context.mounted) {
          return await _copyImageWebFallback(
              imageBytes, null, showNotification);
        }
        return await _copyImageWebFallback(
            imageBytes, context, showNotification);
      }

      if (showNotification && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copy failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
  }

  /// Shares an image using the system share dialogue.
  ///
  /// [imageBytes] The image data to share.
  /// [context] The build context for displaying messages.
  /// [title] Optional share title.
  /// [text] Optional share text.
  /// [filename] Optional filename.
  /// [showNotification] Whether to show success/failure notifications.
  ///
  /// Returns true if the operation succeeds, false otherwise.
  static Future<bool> shareImage({
    required Uint8List imageBytes,
    BuildContext? context,
    String? title,
    String? text,
    String? filename,
    bool showNotification = true,
  }) async {
    final _ImageActionFeedback? feedback = _ImageActionFeedback.maybe(
      context,
      enabled: showNotification,
    );

    try {
      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      final String actualFilename =
          '${filename ?? 'visionnaire_image'}_$timestamp.png';
      final String effectiveTitle = title ?? 'Detection Image';
      final String effectiveText = text ?? 'Shared from Visionnaire';

      if (kIsWeb) {
        try {
          final ShareResult result = await SharePlus.instance.share(
            ShareParams(
              files: <XFile>[
                XFile.fromData(
                  imageBytes,
                  mimeType: 'image/png',
                  name: actualFilename,
                  length: imageBytes.length,
                ),
              ],
              fileNameOverrides: <String>[actualFilename],
              text: effectiveText,
              title: effectiveTitle,
              subject: effectiveTitle,
              downloadFallbackEnabled: false,
              mailToFallbackEnabled: false,
            ),
          );

          if (result.status == ShareResultStatus.unavailable) {
            feedback?.showError('此瀏覽器不支援分享圖片，請改用下載或複製圖片。');
            return false;
          }

          return true;
        } catch (error) {
          debugPrint('Web image share failed: $error');
          feedback?.showError('此瀏覽器不支援分享圖片，請改用下載或複製圖片。');
          return false;
        }
      }

      // Save image to accessible location
      final String imagePath = await saveImageToAccessibleLocation(
        imageBytes,
        filename: filename,
      );

      // Use SharePlus to share the image file
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(imagePath)],
          text: effectiveText,
          title: effectiveTitle,
          subject: effectiveTitle,
        ),
      );

      return true;
    } catch (e) {
      feedback?.showError('Share failed: $e');
      return false;
    }
  }

  /// Shares a record/page link.
  ///
  /// On web, this intentionally copies the link to the clipboard because
  /// desktop browsers expose inconsistent native share support. On mobile and
  /// desktop apps, it opens the platform share sheet.
  static Future<bool> shareLink({
    required Uri uri,
    BuildContext? context,
    String? title,
    bool showNotification = true,
  }) async {
    final _ImageActionFeedback? feedback = _ImageActionFeedback.maybe(
      context,
      enabled: showNotification,
    );
    final String link = uri.toString();

    try {
      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: link));
        feedback?.showInfo('已複製連結到剪貼簿');
        return true;
      }

      final ShareResult result = await SharePlus.instance.share(
        ShareParams(
          uri: uri,
          title: title ?? 'Visionnaire',
          subject: title ?? 'Visionnaire',
          downloadFallbackEnabled: false,
          mailToFallbackEnabled: false,
        ),
      );

      if (result.status == ShareResultStatus.unavailable) {
        feedback?.showError('無法分享連結');
        return false;
      }

      return true;
    } catch (error) {
      debugPrint('Share link failed: $error');
      feedback?.showError('無法分享連結');
      return false;
    }
  }

  // ==================== Advanced Image Operations (with Overlays) ====================

  /// Generates an image with overlay layers.
  ///
  /// [rawBytes] The original image bytes.
  /// [width] The original image width.
  /// [height] The original image height.
  /// [context] The build context for localisation.
  /// [labels] Plain overlay labels captured before async image work starts.
  /// [conePolygons] Optional cone polygon overlays.
  /// [polePolygons] Optional pole polygon overlays.
  /// [detectionItems] Optional detection item overlays.
  /// [showOverlays] Whether to include overlay layers.
  ///
  /// Returns the processed image byte data.
  static Future<Uint8List> generateImageWithOverlays({
    required Uint8List rawBytes,
    required double width,
    required double height,
    required BuildContext context,
    DetectionOverlayLabels labels = const DetectionOverlayLabels.fallback(),
    List<List<Offset>>? conePolygons,
    List<List<Offset>>? polePolygons,
    List<DetectionItem>? detectionItems,
    bool showOverlays = true,
  }) async {
    if (!showOverlays) {
      return rawBytes; // If not showing overlays, return original image
    }

    // Decode the original image
    final ui.Image originalImage = await decodeImage(rawBytes);

    // Create canvas recorder
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    // Draw the original image
    canvas.drawImage(originalImage, Offset.zero, Paint());

    // Use unified overlay drawing method
    OverlayPainter.drawOverlays(
      canvas: canvas,
      size: Size(width, height),
      conePolygons: conePolygons ?? [],
      polePolygons: polePolygons ?? [],
      detectionItems: detectionItems ?? [],
      labels: labels,
      originalWidth: width,
      originalHeight: height,
    );

    // Convert to image
    final ui.Picture picture = recorder.endRecording();
    final ui.Image finalImage =
        await picture.toImage(width.toInt(), height.toInt());

    // Convert to byte data
    final ByteData? byteData =
        await finalImage.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Downloads an image with overlay layers.
  ///
  /// This is a convenience method that combines overlay generation and download functionality.
  ///
  /// [rawBytes] The original image bytes.
  /// [width] The original image width.
  /// [height] The original image height.
  /// [context] The build context for notifications and localisation.
  /// [conePolygons] Optional cone polygon overlays.
  /// [polePolygons] Optional pole polygon overlays.
  /// [detectionItems] Optional detection item overlays.
  /// [showOverlays] Whether to include overlay layers.
  /// [filename] Optional filename prefix.
  /// [showNotification] Whether to show notifications.
  ///
  /// Returns true if the operation succeeds, false otherwise.
  static Future<bool> downloadImageWithOverlays({
    required Uint8List rawBytes,
    required double width,
    required double height,
    required BuildContext context,
    DetectionOverlayLabels labels = const DetectionOverlayLabels.fallback(),
    List<List<Offset>>? conePolygons,
    List<List<Offset>>? polePolygons,
    List<DetectionItem>? detectionItems,
    bool showOverlays = true,
    String? filename,
    bool showNotification = true,
  }) async {
    try {
      final Uint8List imageWithOverlays = await generateImageWithOverlays(
        rawBytes: rawBytes,
        width: width,
        height: height,
        context: context,
        labels: labels,
        conePolygons: conePolygons,
        polePolygons: polePolygons,
        detectionItems: detectionItems,
        showOverlays: showOverlays,
      );

      if (context.mounted) {
        return await downloadImage(
          imageBytes: imageWithOverlays,
          filename: filename,
          context: context,
          showNotification: showNotification,
        );
      }
      return false;
    } catch (e) {
      debugPrint('Download with overlays failed: $e');
      return false;
    }
  }

  /// Copies an image with overlay layers.
  ///
  /// This is a convenience method that combines overlay generation and copy functionality.
  ///
  /// [rawBytes] The original image bytes.
  /// [width] The original image width.
  /// [height] The original image height.
  /// [context] The build context for notifications and localisation.
  /// [conePolygons] Optional cone polygon overlays.
  /// [polePolygons] Optional pole polygon overlays.
  /// [detectionItems] Optional detection item overlays.
  /// [showOverlays] Whether to include overlay layers.
  /// [showNotification] Whether to show notifications.
  ///
  /// Returns true if the operation succeeds, false otherwise.
  static Future<bool> copyImageWithOverlays({
    required Uint8List rawBytes,
    required double width,
    required double height,
    required BuildContext context,
    DetectionOverlayLabels labels = const DetectionOverlayLabels.fallback(),
    List<List<Offset>>? conePolygons,
    List<List<Offset>>? polePolygons,
    List<DetectionItem>? detectionItems,
    bool showOverlays = true,
    bool showNotification = true,
  }) async {
    try {
      final Uint8List imageWithOverlays = await generateImageWithOverlays(
        rawBytes: rawBytes,
        width: width,
        height: height,
        context: context,
        labels: labels,
        conePolygons: conePolygons,
        polePolygons: polePolygons,
        detectionItems: detectionItems,
        showOverlays: showOverlays,
      );

      if (context.mounted) {
        return await copyImage(
          imageWithOverlays,
          context,
          showNotification: showNotification,
        );
      }
      return false;
    } catch (e) {
      debugPrint('Copy with overlays failed: $e');
      return false;
    }
  }

  /// Shares an image with overlay layers.
  ///
  /// This is a convenience method that combines overlay generation and share functionality.
  ///
  /// [rawBytes] The original image bytes.
  /// [width] The original image width.
  /// [height] The original image height.
  /// [context] The build context for notifications and localisation.
  /// [conePolygons] Optional cone polygon overlays.
  /// [polePolygons] Optional pole polygon overlays.
  /// [detectionItems] Optional detection item overlays.
  /// [showOverlays] Whether to include overlay layers.
  /// [title] Optional share title.
  /// [text] Optional share text.
  /// [filename] Optional filename.
  /// [showNotification] Whether to show notifications.
  ///
  /// Returns true if the operation succeeds, false otherwise.
  static Future<bool> shareImageWithOverlays({
    required Uint8List rawBytes,
    required double width,
    required double height,
    required BuildContext context,
    DetectionOverlayLabels labels = const DetectionOverlayLabels.fallback(),
    List<List<Offset>>? conePolygons,
    List<List<Offset>>? polePolygons,
    List<DetectionItem>? detectionItems,
    bool showOverlays = true,
    String? title,
    String? text,
    String? filename,
    bool showNotification = true,
  }) async {
    try {
      final Uint8List imageWithOverlays = await generateImageWithOverlays(
        rawBytes: rawBytes,
        width: width,
        height: height,
        context: context,
        labels: labels,
        conePolygons: conePolygons,
        polePolygons: polePolygons,
        detectionItems: detectionItems,
        showOverlays: showOverlays,
      );

      if (context.mounted) {
        return await shareImage(
          imageBytes: imageWithOverlays,
          context: context,
          title: title,
          text: text,
          filename: filename,
          showNotification: showNotification,
        );
      }
      return false;
    } catch (e) {
      debugPrint('Share with overlays failed: $e');
      return false;
    }
  }

  // ==================== Text Clipboard Operations ====================

  /// Cuts text to clipboard and clears the input field.
  ///
  /// [controller] The TextEditingController to cut text from.
  static void cutText(TextEditingController controller) {
    if (controller.text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: controller.text));
    controller.clear();
  }

  /// Copies text to clipboard from a text controller.
  ///
  /// [controller] The TextEditingController to copy text from.
  static void copyTextFromController(TextEditingController controller) {
    if (controller.text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: controller.text));
  }

  /// Pastes text from clipboard to the input field.
  ///
  /// [controller] The TextEditingController to receive the text.
  static Future<void> pasteText(TextEditingController controller) async {
    final ClipboardData? data = await Clipboard.getData('text/plain');
    if (data?.text == null) return;
    controller.text = data!.text!;
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
  }

  /// Directly copies text to clipboard.
  ///
  /// [text] The text to copy.
  static Future<void> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Gets text from clipboard.
  ///
  /// Returns the text from clipboard, or null if no text is available.
  static Future<String?> getText() async {
    final ClipboardData? data = await Clipboard.getData('text/plain');
    return data?.text;
  }

  // ==================== Utility Methods ====================

  /// Saves an image to an accessible location.
  ///
  /// [imageBytes] The image byte data.
  /// [filename] Optional filename prefix.
  ///
  /// Returns the path of the saved file.
  static Future<String> saveImageToAccessibleLocation(
    Uint8List imageBytes, {
    String? filename,
  }) async {
    Directory directory;

    if (kIsWeb) {
      throw UnsupportedError(
        'Saving image to a temporary file is not supported on web.',
      );
    } else if (Platform.isAndroid || Platform.isIOS) {
      try {
        directory = await getApplicationDocumentsDirectory();
      } catch (e) {
        directory = await getTemporaryDirectory();
      }
    } else {
      // Desktop
      directory = await getApplicationDocumentsDirectory();
    }

    final int timestamp = DateTime.now().millisecondsSinceEpoch;
    final String actualFilename = filename ?? 'visionnaire_image';
    final File file =
        File('${directory.path}/${actualFilename}_$timestamp.png');
    await file.writeAsBytes(imageBytes);

    return file.path;
  }

  // ==================== Convenience Methods ====================

  /// Quick selection of multiple images.
  ///
  /// [imageQuality] The image quality (1-100).
  ///
  /// Returns a list of selected image files.
  static Future<List<image_picker.XFile>> pickImages(
      {int imageQuality = 85}) async {
    return await pickMultiImage(imageQuality: imageQuality);
  }

  /// Quick camera capture.
  ///
  /// [imageQuality] The image quality (1-100).
  ///
  /// Returns the captured image file, or null if cancelled.
  static Future<image_picker.XFile?> takePicture(
      {int imageQuality = 85}) async {
    return await pickSingleImage(fromCamera: true, imageQuality: imageQuality);
  }

  /// Quick selection from gallery.
  ///
  /// [imageQuality] The image quality (1-100).
  ///
  /// Returns the selected image file, or null if cancelled.
  static Future<image_picker.XFile?> pickFromGallery(
      {int imageQuality = 85}) async {
    return await pickSingleImage(fromCamera: false, imageQuality: imageQuality);
  }

  // ==================== Private Helper Methods ====================

  /// Web platform image copy fallback implementation.
  ///
  /// [imageBytes] The image byte data to copy.
  /// [context] The build context for notifications.
  /// [showNotification] Whether to show notifications.
  ///
  /// Returns true if the fallback succeeds, false otherwise.
  static Future<bool> _copyImageWebFallback(
    Uint8List imageBytes,
    BuildContext? context,
    bool showNotification,
  ) async {
    try {
      // Use base64 as a last resort fallback
      final String base64Image = base64Encode(imageBytes);
      final String dataUrl = 'data:image/png;base64,$base64Image';
      await Clipboard.setData(ClipboardData(text: dataUrl));

      if (showNotification && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image copied as data URL (base64 format)'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Web image copy fallback failed: $e');
      return false;
    }
  }
}
