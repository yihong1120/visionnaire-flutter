import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

// Conditional import: only import web package on Web platform
import 'cross_platform_download_stub.dart'
    if (dart.library.html) 'cross_platform_download_web.dart' as platform;

/// Cross-platform download utility class.
///
/// This class provides comprehensive download functionality supporting both
/// Web and mobile platforms. On Web platforms, it uses HTML DOM APIs.
/// For mobile platforms, prefer UnifiedImageService when user-visible feedback
/// or gallery/share integration is needed.
class CrossPlatformDownload {
  /// Downloads an image file.
  ///
  /// On Web platforms, this method uses browser-specific download APIs
  /// with multiple fallback strategies to ensure compatibility across
  /// different browsers and configurations.
  ///
  /// On mobile platforms, this method throws an UnsupportedError and
  /// recommends using UnifiedImageService.downloadImage() instead.
  ///
  /// [imageBytes] The image byte data to download.
  /// [filename] The filename for the downloaded file.
  ///
  /// Throws UnsupportedError on non-web platforms.
  static void downloadImage(Uint8List imageBytes, String filename) {
    if (kIsWeb) {
      platform.PlatformDownload.downloadImageWeb(imageBytes, filename);
    } else {
      throw UnsupportedError(
          'Use UnifiedImageService.downloadImage() for mobile platforms');
    }
  }

  /// Downloads arbitrary bytes as a file (cross-platform API).
  ///
  /// On Web platforms, triggers a browser download using modern Web APIs.
  /// On mobile platforms, throws UnsupportedError (implement as needed).
  ///
  /// [bytes] The data to download.
  /// [filename] The suggested filename.
  /// [mimeType] Optional MIME type hint (used on web when building data URLs).
  static void downloadBytes(Uint8List bytes, String filename,
      {String? mimeType}) {
    if (kIsWeb) {
      platform.PlatformDownload.downloadBytesWeb(bytes, filename,
          mimeType: mimeType);
    } else {
      throw UnsupportedError(
          'Download bytes is only implemented for web in this utility');
    }
  }
}
