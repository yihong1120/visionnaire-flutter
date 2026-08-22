import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// Web platform implementation for downloads.
///
/// This class provides web-specific download functionality using modern
/// browser APIs. It includes multiple fallback strategies to ensure
/// downloads work across different browsers and configurations.
class PlatformDownload {
  /// Web platform image download implementation.
  ///
  /// Uses modern Web APIs to create an anchor element and trigger downloads.
  /// Falls back to alternative methods if the primary approach fails.
  ///
  /// [imageBytes] The image byte data to download.
  /// [filename] The filename for the downloaded file.
  static void downloadImageWeb(Uint8List imageBytes, String filename) {
    debugPrint('Web download: $filename (${imageBytes.length} bytes)');

    try {
      // Convert to base64
      final String base64Data = base64Encode(imageBytes);
      final String dataUrl = 'data:image/png;base64,$base64Data';

      // Use modern Web API to create anchor element for triggering download
      final web.HTMLAnchorElement anchor =
          web.document.createElement('a') as web.HTMLAnchorElement;
      anchor.href = dataUrl;
      anchor.download = filename;
      anchor.style.display = 'none';

      // Add to DOM and trigger click
      web.document.body?.appendChild(anchor);
      anchor.click();

      // Clean up: remove element
      web.document.body?.removeChild(anchor);

      debugPrint('Web download triggered successfully for: $filename');
    } catch (e) {
      debugPrint('Web download failed: $e');
      // Fallback option: open in new tab or copy to clipboard
      fallbackWebDownload(imageBytes, filename);
    }
  }

  /// Fallback web download strategy.
  ///
  /// Opens the image data URL in a new browser tab as an alternative
  /// download method when the primary anchor-based download fails.
  ///
  /// [imageBytes] The image byte data to download.
  /// [filename] The filename for the downloaded file.
  static void fallbackWebDownload(Uint8List imageBytes, String filename) {
    try {
      final String base64Data = base64Encode(imageBytes);
      final String dataUrl = 'data:image/png;base64,$base64Data';

      // Use modern Web API to open in new tab
      web.window.open(dataUrl, '_blank');
      debugPrint('Fallback web download opened in new tab for: $filename');
    } catch (e) {
      debugPrint('New tab fallback failed: $e');
      // Final fallback option: copy to clipboard
      copyToClipboardFallback(imageBytes, filename);
    }
  }

  /// Final fallback strategy: copy download link to clipboard.
  ///
  /// Copies the image data URL to the system clipboard as a last resort
  /// when other download methods fail.
  ///
  /// [imageBytes] The image byte data to download.
  /// [filename] The filename for the downloaded file.
  static void copyToClipboardFallback(Uint8List imageBytes, String filename) {
    try {
      final String base64Data = base64Encode(imageBytes);
      final String dataUrl = 'data:image/png;base64,$base64Data';
      Clipboard.setData(ClipboardData(text: dataUrl));
      debugPrint('Download URL copied to clipboard for: $filename');
      debugPrint('User can paste the URL in browser address bar to download');
    } catch (e) {
      debugPrint('Clipboard fallback also failed: $e');
    }
  }

  /// Web platform generic bytes download implementation.
  ///
  /// Creates a Blob with the provided bytes and optional MIME type,
  /// builds an object URL, and triggers a download via an anchor element.
  static void downloadBytesWeb(Uint8List bytes, String filename,
      {String? mimeType}) {
    try {
      final String base64Data = base64Encode(bytes);
      final String type = mimeType ?? 'application/octet-stream';
      final String dataUrl = 'data:$type;base64,$base64Data';

      final web.HTMLAnchorElement anchor =
          web.document.createElement('a') as web.HTMLAnchorElement;
      anchor.href = dataUrl;
      anchor.download = filename;
      anchor.style.display = 'none';

      web.document.body?.appendChild(anchor);
      anchor.click();
      web.document.body?.removeChild(anchor);

      debugPrint('Web bytes download triggered for: $filename');
    } catch (e) {
      debugPrint('Web bytes download failed: $e');
    }
  }
}
