import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// Stub implementation for non-web platforms.
///
/// This class provides placeholder implementations for web-specific download
/// functionality that are not supported on other platforms. All methods
/// throw UnsupportedError when called on non-web platforms.
class PlatformDownload {
  /// Stub implementation of web image download.
  ///
  /// [imageBytes] The image byte data (not used in stub).
  /// [filename] The intended filename (not used in stub).
  ///
  /// Throws UnsupportedError as web download is only available on web platform.
  static void downloadImageWeb(Uint8List imageBytes, String filename) {
    debugPrint('Web download not supported on this platform');
    throw UnsupportedError('Web download is only available on web platform');
  }

  /// Stub implementation of web fallback download.
  ///
  /// [imageBytes] The image byte data (not used in stub).
  /// [filename] The intended filename (not used in stub).
  ///
  /// Throws UnsupportedError as web download is only available on web platform.
  static void fallbackWebDownload(Uint8List imageBytes, String filename) {
    debugPrint('Web fallback download not supported on this platform');
    throw UnsupportedError('Web download is only available on web platform');
  }

  /// Stub implementation of web clipboard fallback.
  ///
  /// [imageBytes] The image byte data (not used in stub).
  /// [filename] The intended filename (not used in stub).
  ///
  /// Throws UnsupportedError as web download is only available on web platform.
  static void copyToClipboardFallback(Uint8List imageBytes, String filename) {
    debugPrint('Web clipboard fallback not supported on this platform');
    throw UnsupportedError('Web download is only available on web platform');
  }

  /// Stub implementation of generic bytes download for web.
  static void downloadBytesWeb(Uint8List bytes, String filename,
      {String? mimeType}) {
    debugPrint('Generic bytes web download not supported on this platform');
    throw UnsupportedError('Web download is only available on web platform');
  }
}
