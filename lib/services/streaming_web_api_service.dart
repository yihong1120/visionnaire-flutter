import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:http/http.dart' as http;

import 'api_config_service.dart';
import 'auth_request_headers.dart';
import '../utils/overlay_language.dart';

/// Service for streaming site and camera metadata.
class StreamingWebAPIService {
  static Future<String> get baseUrl async {
    return ApiConfigService.getApiUrl('streaming_web');
  }

  static const int _timeoutSeconds = 30;

  static String overlayLanguageForLocale(Locale locale) =>
      OverlayLanguage.forLocale(locale);

  static String playbackProfileForOverlay(bool showOverlay) {
    return showOverlay ? 'overlay' : 'clean';
  }

  static Future<List<String>> fetchLabels({required String token}) async {
    final baseUrlValue = await baseUrl;
    final cleanBaseUrl = _sanitiseBaseUrl(baseUrlValue);
    final uri = Uri.parse('$cleanBaseUrl/labels');

    final resp = await http.get(
      uri,
      headers: <String, String>{...AuthRequestHeaders.forRequest(token)},
    ).timeout(const Duration(seconds: _timeoutSeconds));

    final decodedBody = utf8.decode(resp.bodyBytes);

    if (resp.statusCode == 200) {
      final data = jsonDecode(decodedBody);
      final labelsData = data['labels'];
      if (labelsData is List) {
        return labelsData.map((e) => e.toString()).toList(growable: false);
      }
      throw Exception("Invalid format: field 'labels' is not a List");
    }

    final detail = _safeDetail(decodedBody);
    throw Exception('Failed to fetch labels (${resp.statusCode}): $detail');
  }

  static Future<List<Map<String, dynamic>>> fetchStreams({
    required String label,
    required String token,
  }) async {
    final baseUrlValue = await baseUrl;
    final baseUri = Uri.parse(_sanitiseBaseUrl(baseUrlValue));
    final uri = _apiUri(baseUri, <String>['streams', label]);

    final resp = await http.get(
      uri,
      headers: <String, String>{...AuthRequestHeaders.forRequest(token)},
    ).timeout(const Duration(seconds: _timeoutSeconds));

    final decodedBody = utf8.decode(resp.bodyBytes);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final data = jsonDecode(decodedBody);
      final streamsData = data['streams'];
      if (streamsData is List) {
        return streamsData
            .whereType<Map>()
            .map((stream) => Map<String, dynamic>.from(stream))
            .toList(growable: false);
      }
      throw Exception("Invalid format: field 'streams' is not a List");
    }

    final detail = _safeDetail(decodedBody);
    throw Exception('Failed to fetch streams (${resp.statusCode}): $detail');
  }

  static String _sanitiseBaseUrl(String url) =>
      url.replaceAll(RegExp(r'/+$'), '');

  static Uri _apiUri(Uri baseUri, List<String> pathSegments) {
    return baseUri.replace(
      pathSegments: <String>[
        ...baseUri.pathSegments,
        ...pathSegments.where((segment) => segment.isNotEmpty),
      ],
      query: null,
      fragment: null,
    );
  }

  static String _safeDetail(String rawBody) {
    try {
      final obj = jsonDecode(rawBody);
      if (obj is Map) {
        return obj['reason']?.toString() ??
            obj['detail']?.toString() ??
            rawBody;
      }
      return rawBody;
    } catch (_) {
      return rawBody;
    }
  }
}
