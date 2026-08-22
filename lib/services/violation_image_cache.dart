import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;

import 'api_config_service.dart';
import 'auth_request_headers.dart';

class ViolationImageData {
  final String url;
  final Uint8List rawBytes;
  final double width;
  final double height;

  const ViolationImageData({
    required this.url,
    required this.rawBytes,
    required this.width,
    required this.height,
  });
}

class ViolationImageCache {
  static const int _maxEntries = 8;
  static const int _maxBytes = 24 * 1024 * 1024;
  static final LinkedHashMap<String, Future<ViolationImageData>> _cache =
      LinkedHashMap<String, Future<ViolationImageData>>();
  static final Map<String, int> _byteLengthByUrl = <String, int>{};
  static int _cachedByteLength = 0;

  @visibleForTesting
  static Future<ViolationImageData> Function({
    required String url,
    required String token,
    required Duration timeout,
  })? debugLoader;

  ViolationImageCache._();

  static Future<ViolationImageData> fetch({
    required String url,
    required String token,
    Duration timeout = const Duration(seconds: 600),
  }) {
    final String normalizedUrl = url.trim();
    final Future<ViolationImageData>? existing = _cache.remove(normalizedUrl);
    if (existing != null) {
      _cache[normalizedUrl] = existing;
      return existing;
    }

    final loader = debugLoader ?? _downloadAndDecode;
    final Future<ViolationImageData> future = _loadTrustedImage(
      url: normalizedUrl,
      token: token,
      timeout: timeout,
      loader: loader,
    );
    _cache[normalizedUrl] = future;
    unawaited(
      future.then<void>(
        (ViolationImageData data) =>
            _recordCompletedEntry(normalizedUrl, future, data),
        onError: (Object _, StackTrace __) {
          _removeEntryIfCurrent(normalizedUrl, future);
        },
      ),
    );
    _trim();
    return future;
  }

  static Future<ViolationImageData> _loadTrustedImage({
    required String url,
    required String token,
    required Duration timeout,
    required Future<ViolationImageData> Function({
      required String url,
      required String token,
      required Duration timeout,
    }) loader,
  }) async {
    if (kIsWeb) {
      _requireWebBffOrigin(url);
    } else {
      await _requireSignedNativeOrigin(url);
    }
    return loader(url: url, token: token, timeout: timeout);
  }

  /// Rejects a browser image URL before a BFF cookie or CSRF header is sent.
  ///
  /// Browser image authentication is same-origin BFF authentication. A URL
  /// from a record is therefore never authority to make an authenticated
  /// request to another origin.
  static void _requireWebBffOrigin(String value) {
    if (!isAbsoluteImageUriOnOrigin(value, Uri.base)) {
      throw const FormatException(
        'Violation image URL is outside the browser BFF origin.',
      );
    }
  }

  /// Rejects a native image URL before any request can carry a bearer token.
  ///
  /// Violation metadata can contain absolute image links. Those links are not
  /// authority to send the user's credential to another host: native images
  /// must stay on the origin selected by the signed deployment profile.
  static Future<void> _requireSignedNativeOrigin(String value) async {
    final Uri? apiBaseUri = (await ApiConfigService.initialize()).apiBaseUri;
    if (apiBaseUri == null || !isAbsoluteImageUriOnOrigin(value, apiBaseUri)) {
      throw const FormatException(
        'Violation image URL is outside the signed deployment origin.',
      );
    }
  }

  /// Returns whether [value] is an absolute HTTP(S) image URL on [origin].
  ///
  /// Kept pure so the browser BFF origin rule can be tested without a web
  /// runtime. Relative links and user-info URLs are rejected deliberately.
  @visibleForTesting
  static bool isAbsoluteImageUriOnOrigin(String value, Uri origin) {
    final Uri? imageUri = Uri.tryParse(value);
    return imageUri != null &&
        _isHttpUri(imageUri) &&
        _isHttpUri(origin) &&
        imageUri.hasAuthority &&
        imageUri.host.isNotEmpty &&
        imageUri.userInfo.isEmpty &&
        _hasSameOrigin(imageUri, origin);
  }

  static bool _isHttpUri(Uri uri) =>
      uri.scheme == 'http' || uri.scheme == 'https';

  static bool _hasSameOrigin(Uri first, Uri second) {
    return first.scheme == second.scheme &&
        first.host == second.host &&
        _effectivePort(first) == _effectivePort(second);
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return switch (uri.scheme) {
      'http' => 80,
      'https' => 443,
      _ => -1,
    };
  }

  static void evict(String url) {
    _removeEntry(url.trim());
  }

  static void clear() {
    _cache.clear();
    _byteLengthByUrl.clear();
    _cachedByteLength = 0;
  }

  static void _recordCompletedEntry(
    String url,
    Future<ViolationImageData> future,
    ViolationImageData data,
  ) {
    if (!identical(_cache[url], future)) return;
    final int byteLength = data.rawBytes.lengthInBytes;
    final int? previousByteLength = _byteLengthByUrl[url];
    if (previousByteLength != null) {
      _cachedByteLength -= previousByteLength;
    }
    _byteLengthByUrl[url] = byteLength;
    _cachedByteLength += byteLength;
    _trim();
  }

  static void _trim() {
    while (_cache.length > _maxEntries || _cachedByteLength > _maxBytes) {
      _removeEntry(_cache.keys.first);
    }
  }

  static void _removeEntry(String url) {
    _cache.remove(url);
    final int? byteLength = _byteLengthByUrl.remove(url);
    if (byteLength != null) {
      _cachedByteLength -= byteLength;
    }
  }

  static void _removeEntryIfCurrent(
    String url,
    Future<ViolationImageData> future,
  ) {
    if (identical(_cache[url], future)) _removeEntry(url);
  }

  static Future<ViolationImageData> _downloadAndDecode({
    required String url,
    required String token,
    required Duration timeout,
  }) async {
    final Uri uri = Uri.parse(url);
    final http.Client client = http.Client();
    final http.Response response;
    try {
      final http.Request request = http.Request('GET', uri)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.addAll(<String, String>{
          if (token.isNotEmpty) ...AuthRequestHeaders.forRequest(token),
        });
      final http.StreamedResponse streamedResponse =
          await client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamedResponse);
    } finally {
      client.close();
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to download image: ${response.statusCode}');
    }

    final Uint8List rawBytes = response.bodyBytes;
    if (rawBytes.isEmpty) {
      throw Exception('Empty image data from server.');
    }
    if (!_looksLikeImage(response, rawBytes)) {
      throw Exception(
        'Invalid image response from server: ${_responseSummary(response)}',
      );
    }

    final ui.Image image = await _decodeImage(rawBytes);
    final double width = image.width.toDouble();
    final double height = image.height.toDouble();
    image.dispose();

    return ViolationImageData(
      url: url,
      rawBytes: rawBytes,
      width: width,
      height: height,
    );
  }

  static Future<ui.Image> _decodeImage(Uint8List bytes) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      return frame.image;
    } catch (error) {
      throw Exception('Invalid image data: $error');
    } finally {
      codec?.dispose();
    }
  }

  static bool _looksLikeImage(http.Response response, Uint8List bytes) {
    final String contentType =
        response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.startsWith('image/')) return true;

    if (bytes.length >= 4) {
      final int b0 = bytes[0];
      final int b1 = bytes[1];
      final int b2 = bytes[2];
      final int b3 = bytes[3];

      final bool isJpeg = b0 == 0xFF && b1 == 0xD8;
      final bool isPng = b0 == 0x89 && b1 == 0x50 && b2 == 0x4E && b3 == 0x47;
      final bool isGif = b0 == 0x47 && b1 == 0x49 && b2 == 0x46;
      final bool isWebp = bytes.length >= 12 &&
          b0 == 0x52 &&
          b1 == 0x49 &&
          b2 == 0x46 &&
          b3 == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50;
      return isJpeg || isPng || isGif || isWebp;
    }

    return false;
  }

  static String _responseSummary(http.Response response) {
    final String contentType = response.headers['content-type'] ?? 'unknown';
    final String bodyPreview = _bodyPreview(response.bodyBytes);
    return 'status=${response.statusCode}, content-type=$contentType'
        '${bodyPreview.isEmpty ? '' : ', body=$bodyPreview'}';
  }

  static String _bodyPreview(Uint8List bytes) {
    try {
      final String text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isEmpty) return '';
      return text.length > 160 ? '${text.substring(0, 160)}...' : text;
    } catch (_) {
      return '';
    }
  }
}
