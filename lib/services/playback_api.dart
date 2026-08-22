import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'api_config_service.dart';
import 'auth_request_headers.dart';
import '../config/bff_config.dart';
import 'credentialed_http.dart' as credentialed_http;
import 'management_api_service.dart';
import '../utils/overlay_language.dart';

typedef PlaybackAccessTokenProvider = Future<String> Function({bool force});

abstract final class PlaybackRoutes {
  static String get webBase => BffConfig.playbackBasePath;

  static String sessions(Uri base) => _append(base, const <String>['sessions']);

  static String walls(Uri base) => _append(base, const <String>['walls']);

  static String renew(Uri base) =>
      _append(base, const <String>['sessions', 'renew']);

  static String close(Uri base, String id) => _append(
        base,
        <String>['sessions', Uri.encodeComponent(id)],
      );

  static String _append(Uri base, List<String> children) {
    final path = <String>[
      base.path.replaceFirst(RegExp(r'/+$'), ''),
      ...children,
    ].join('/');
    return base.replace(path: path, query: null, fragment: null).toString();
  }
}

sealed class PlaybackResource {
  const PlaybackResource({
    required this.id,
    required this.expiresIn,
    required this.renewEndpoint,
  });

  final String id;
  final int expiresIn;
  final String? renewEndpoint;
}

class PlaybackSession extends PlaybackResource {
  const PlaybackSession({
    required super.id,
    required super.expiresIn,
    required super.renewEndpoint,
    required this.hlsUrl,
    required this.hlsUri,
    this.language,
  });

  final String hlsUrl;
  final Uri hlsUri;
  final String? language;

  PlaybackSession copyWithRenewal(PlaybackRenewal renewal) {
    return PlaybackSession(
      id: id,
      expiresIn: renewal.expiresIn,
      renewEndpoint: renewEndpoint,
      hlsUrl: hlsUrl,
      hlsUri: hlsUri,
      language: language,
    );
  }

  factory PlaybackSession.fromJson(
    Map<String, dynamic> json, {
    required Uri resolveBase,
  }) {
    final id = _requiredString(json, 'id');
    final hlsUrl = _requiredString(json, 'hls_url');
    return PlaybackSession(
      id: id,
      expiresIn: _intValue(json['expires_in'], fallback: 600),
      renewEndpoint: _stringValue(json['renew_endpoint']),
      hlsUrl: hlsUrl,
      hlsUri: _resolvePlaybackUri(hlsUrl, resolveBase),
      language: _stringValue(json['language']),
    );
  }
}

class PlaybackWall extends PlaybackResource {
  const PlaybackWall({
    required super.id,
    required super.expiresIn,
    required super.renewEndpoint,
    required this.items,
    this.language,
  });

  final List<PlaybackWallItem> items;
  final String? language;

  PlaybackWall copyWithRenewal(PlaybackRenewal renewal) {
    return PlaybackWall(
      id: id,
      expiresIn: renewal.expiresIn,
      renewEndpoint: renewEndpoint,
      items: items,
      language: language,
    );
  }

  factory PlaybackWall.fromJson(
    Map<String, dynamic> json, {
    required Uri resolveBase,
  }) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('Playback wall response is missing items');
    }

    return PlaybackWall(
      id: _requiredString(json, 'id'),
      expiresIn: _intValue(json['expires_in'], fallback: 600),
      renewEndpoint: _stringValue(json['renew_endpoint']),
      language: _stringValue(json['language']),
      items: rawItems
          .whereType<Map>()
          .map(
            (item) => PlaybackWallItem.fromJson(
              Map<String, dynamic>.from(item),
              resolveBase: resolveBase,
            ),
          )
          // The backend must already exclude disabled streams before creating
          // playback sessions. This is a second guard so an accidentally
          // returned disabled item neither renders nor consumes a wall slot.
          .where((item) => item.recognitionEnabled)
          .where((item) => item.previewHlsUrl.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class PlaybackWallItem {
  const PlaybackWallItem({
    required this.title,
    required this.previewHlsUrl,
    required this.previewHlsUri,
    required this.recognitionEnabled,
    this.camera,
    this.streamId,
    this.key,
  });

  final String title;
  final String previewHlsUrl;
  final Uri previewHlsUri;
  final bool recognitionEnabled;
  final String? camera;
  final String? streamId;
  final String? key;

  String get cameraKey {
    final candidates = <String?>[camera, key, title, streamId];
    for (final candidate in candidates) {
      final value = candidate?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  String get stableStreamId {
    final value = streamId?.trim();
    if (value != null && value.isNotEmpty) return value;
    return cameraKey;
  }

  factory PlaybackWallItem.fromJson(
    Map<String, dynamic> json, {
    required Uri resolveBase,
  }) {
    final rawUrl =
        _stringValue(json['preview_hls_url'] ?? json['hls_url']) ?? '';
    final title = _stringValue(json['title']) ??
        _stringValue(json['camera']) ??
        _stringValue(json['key']) ??
        _stringValue(json['stream_name']) ??
        _stringValue(json['stream_id']) ??
        '';

    return PlaybackWallItem(
      title: title,
      previewHlsUrl: rawUrl,
      previewHlsUri: _resolvePlaybackUri(rawUrl, resolveBase),
      recognitionEnabled:
          _boolValue(json['recognition_enabled'], fallback: true),
      camera: _stringValue(json['camera'] ?? json['stream_name']),
      streamId: _stringValue(json['stream_id'] ?? json['streamId']),
      key: _stringValue(json['key']),
    );
  }
}

class PlaybackRenewal {
  const PlaybackRenewal({
    required this.id,
    required this.expiresIn,
    required this.renewed,
    required this.hlsUrlsChanged,
  });

  final String id;
  final int expiresIn;
  final bool renewed;
  final bool hlsUrlsChanged;

  factory PlaybackRenewal.fromJson(Map<String, dynamic> json) {
    return PlaybackRenewal(
      id: _requiredString(json, 'id'),
      expiresIn: _intValue(json['expires_in'], fallback: 600),
      renewed: _boolValue(json['renewed'], fallback: true),
      hlsUrlsChanged: _boolValue(json['hls_urls_changed'], fallback: false),
    );
  }
}

class PlaybackApiException implements Exception {
  const PlaybackApiException(this.statusCode, this.detail);

  final int statusCode;
  final String detail;

  bool get isUnauthorized => statusCode == 401;
  bool get isInvalidCsrf => statusCode == 403 && detail == 'invalid_csrf_token';
  bool get isAppSessionExpired =>
      statusCode == 401 && detail == 'app_session_expired';

  @override
  String toString() => 'PlaybackApiException($statusCode, $detail)';
}

class PlaybackApi {
  PlaybackApi({
    PlaybackAccessTokenProvider? accessTokenProvider,
    http.Client? client,
  })  : _accessTokenProvider = accessTokenProvider,
        _client = client;

  final PlaybackAccessTokenProvider? _accessTokenProvider;
  final http.Client? _client;

  static const Duration _timeout = Duration(seconds: 30);

  Future<PlaybackSession> createSingle({
    required String site,
    required String camera,
    String profile = 'overlay',
    String language = OverlayLanguage.fallback,
    String transport = 'hls',
  }) async {
    final normalizedProfile = _profile(profile);
    final normalizedLanguage = normalizedProfile == 'overlay'
        ? OverlayLanguage.requireSupported(language)
        : null;
    final response = await _request(
      'POST',
      (base) => PlaybackRoutes.sessions(base),
      body: <String, dynamic>{
        'site': site,
        'camera': camera,
        'profile': normalizedProfile,
        if (normalizedLanguage != null) 'language': normalizedLanguage,
        'transport': transport,
      },
    );
    final session = PlaybackSession.fromJson(
      response.body,
      resolveBase: response.resolveBase,
    );
    _verifyResponseLanguage(
      requested: normalizedLanguage,
      returned: session.language,
    );
    return session;
  }

  Future<PlaybackWall> createWall({
    required String site,
    List<String>? cameras,
    String profile = 'overlay',
    String language = 'zh-TW',
    String transport = 'hls',
  }) async {
    final normalizedProfile = _profile(profile);
    final normalizedLanguage = normalizedProfile == 'overlay'
        ? OverlayLanguage.requireSupported(language)
        : null;
    final cameraList = cameras
        ?.map((camera) => camera.trim())
        .where((camera) => camera.isNotEmpty)
        .toList(growable: false);

    final response = await _request(
      'POST',
      (base) => PlaybackRoutes.walls(base),
      body: <String, dynamic>{
        'site': site,
        if (cameraList != null && cameraList.isNotEmpty) 'cameras': cameraList,
        'profile': normalizedProfile,
        if (normalizedLanguage != null) 'language': normalizedLanguage,
        'transport': transport,
      },
    );
    final wall = PlaybackWall.fromJson(
      response.body,
      resolveBase: response.resolveBase,
    );
    _verifyResponseLanguage(
      requested: normalizedLanguage,
      returned: wall.language,
    );
    return wall;
  }

  Future<PlaybackRenewal> renew(PlaybackResource current) async {
    final sessionId = current.id.trim();
    if (sessionId.isEmpty) {
      throw const FormatException('Playback session id is missing');
    }

    final response = await _request(
      'POST',
      (base) => _renewRoute(base, current),
      body: <String, dynamic>{'id': sessionId},
    );
    return PlaybackRenewal.fromJson(response.body);
  }

  Future<void> close(String id) async {
    final sessionId = id.trim();
    if (sessionId.isEmpty) return;
    try {
      await _request(
        'DELETE',
        (base) => PlaybackRoutes.close(base, sessionId),
        expectedStatuses: const <int>{200, 202, 204, 404, 410},
      );
    } on PlaybackApiException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 410) return;
      rethrow;
    }
  }

  Future<_PlaybackApiResponse> _request(
    String method,
    String Function(Uri base) routeBuilder, {
    Map<String, dynamic>? body,
    Set<int> expectedStatuses = const <int>{200, 201, 202},
    bool retryCsrf = true,
    bool retryAuth = true,
  }) async {
    final base = await _playbackBaseUri();
    final uri = Uri.parse(routeBuilder(base));
    final token = await _accessToken(force: false);
    await _ensureWebCsrf();

    final response = await _send(
      method,
      uri,
      token: token,
      body: body,
    );
    final decoded = _decodeBody(response);

    if (expectedStatuses.contains(response.statusCode)) {
      return _PlaybackApiResponse(decoded, resolveBase: base);
    }

    final exception = PlaybackApiException(
      response.statusCode,
      _detail(decoded, response.body),
    );

    if (kIsWeb && exception.isInvalidCsrf && retryCsrf) {
      AuthRequestHeaders.clearWebSession();
      await _ensureWebCsrf(forceRefresh: true);
      return _request(
        method,
        routeBuilder,
        body: body,
        expectedStatuses: expectedStatuses,
        retryCsrf: false,
        retryAuth: retryAuth,
      );
    }

    if (exception.isUnauthorized && retryAuth) {
      await _accessToken(force: true);
      return _request(
        method,
        routeBuilder,
        body: body,
        expectedStatuses: expectedStatuses,
        retryCsrf: retryCsrf,
        retryAuth: false,
      );
    }

    throw exception;
  }

  String _renewRoute(Uri base, PlaybackResource current) {
    final endpoint = current.renewEndpoint?.trim();
    if (endpoint == null || endpoint.isEmpty) {
      return PlaybackRoutes.renew(base);
    }
    return _resolveRenewEndpoint(endpoint, base).toString();
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    required String token,
    required Map<String, dynamic>? body,
  }) {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      ...AuthRequestHeaders.forRequest(token),
    };
    final encodedBody = body == null ? null : jsonEncode(body);

    final client = _client;
    if (client != null) {
      switch (method) {
        case 'POST':
          return client
              .post(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
        case 'DELETE':
          return client
              .delete(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
        default:
          throw ArgumentError('Unsupported playback method: $method');
      }
    }

    return credentialed_http.sendJsonRequest(
      method,
      uri,
      headers: headers,
      body: encodedBody,
      timeout: _timeout,
    );
  }

  Future<String> _accessToken({required bool force}) async {
    if (kIsWeb) {
      final token = await _accessTokenProvider?.call(force: force);
      return token?.trim().isNotEmpty == true ? token!.trim() : '';
    }

    final provider = _accessTokenProvider;
    if (provider == null) {
      throw const FormatException('Playback API requires an access token');
    }
    final token = (await provider(force: force)).trim();
    if (token.isEmpty) {
      throw const FormatException('Playback API requires an access token');
    }
    return token;
  }

  Future<void> _ensureWebCsrf({bool forceRefresh = false}) async {
    if (!kIsWeb) return;
    if (!forceRefresh && AuthRequestHeaders.csrfToken != null) return;

    final token = await ManagementAPIService.getWebCsrfToken();
    AuthRequestHeaders.setCsrfToken(token);
  }

  Future<Uri> _playbackBaseUri() async {
    if (kIsWeb) return Uri.base.resolve(PlaybackRoutes.webBase);

    final managementBase =
        (await ApiConfigService.getApiUrl('management')).trim();
    final trimmed = managementBase.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$trimmed/api/playback');
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    final raw = utf8.decode(response.bodyBytes);
    if (raw.trim().isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('Playback API returned invalid JSON');
  }
}

/// Resolves a backend-provided renewal endpoint without allowing it to change
/// the authenticated API origin.
///
/// Playback media URLs deliberately have different rules: signed HLS URLs may
/// point to a CDN. A renewal endpoint is an authenticated control-plane
/// request, so it may only be a path-relative URI or an absolute URI on the
/// configured playback API origin.
Uri _resolveRenewEndpoint(String rawEndpoint, Uri base) {
  final uri = Uri.parse(rawEndpoint);

  if (uri.userInfo.isNotEmpty) {
    throw const FormatException(
      'Playback renewal endpoint must not contain credentials',
    );
  }

  if (uri.hasScheme || uri.hasAuthority) {
    if (!uri.hasScheme || !uri.hasAuthority || !_hasSameOrigin(uri, base)) {
      throw const FormatException(
        'Playback renewal endpoint must use the configured API origin',
      );
    }
    return uri;
  }

  return base.replace(
    path: uri.path,
    query: uri.hasQuery ? uri.query : null,
    fragment: uri.hasFragment ? uri.fragment : null,
  );
}

bool _hasSameOrigin(Uri first, Uri second) {
  return first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
      first.host.toLowerCase() == second.host.toLowerCase() &&
      _effectivePort(first) == _effectivePort(second);
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) return uri.port;
  return switch (uri.scheme.toLowerCase()) {
    'http' => 80,
    'https' => 443,
    _ => 0,
  };
}

class _PlaybackApiResponse {
  const _PlaybackApiResponse(this.body, {required this.resolveBase});

  final Map<String, dynamic> body;
  final Uri resolveBase;
}

int playbackRenewalDelaySeconds(int expiresIn) {
  if (expiresIn <= 0) return 30;
  return max(30, min(600, (expiresIn * 0.5).round()));
}

/// Exponential retry delay for transient playback transport failures.
Duration playbackRetryDelay(int failureCount) {
  final exponent = failureCount.clamp(0, 5);
  return Duration(seconds: min(60, 3 * (1 << exponent)));
}

/// Whether retrying can recover without changing playback credentials.
bool isRetryablePlaybackError(Object error) {
  if (error is PlaybackApiException) {
    return const <int>{408, 429, 502, 503, 504}.contains(error.statusCode);
  }
  if (error is TimeoutException || error is http.ClientException) return true;

  final message = error.toString().toLowerCase();
  return <String>[
    'err_name_not_resolved',
    'failed to fetch',
    'socketexception',
    'network is unreachable',
    'network error',
    'connection refused',
    'connection reset',
    'connection closed',
    'timed out',
  ].any(message.contains);
}

String _profile(String profile) {
  final value = profile.trim().toLowerCase();
  if (value.isEmpty) throw ArgumentError.value(profile, 'profile');
  return value;
}

void _verifyResponseLanguage({
  required String? requested,
  required String? returned,
}) {
  if (requested == null || returned == null || returned.isEmpty) return;
  final normalizedReturned = OverlayLanguage.requireSupported(returned);
  if (normalizedReturned != requested) {
    throw StateError(
      'Playback response language ($normalizedReturned) does not match '
      'requested language ($requested)',
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _stringValue(json[key]);
  if (value == null || value.isEmpty) {
    throw FormatException('Playback API response is missing $key');
  }
  return value;
}

String? _stringValue(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _intValue(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '') ?? fallback;
}

bool _boolValue(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return fallback;
}

String _detail(Map<String, dynamic> body, String fallback) {
  return _stringValue(body['detail'] ?? body['reason'] ?? body['code']) ??
      fallback;
}

Uri _resolvePlaybackUri(String rawUrl, Uri resolveBase) {
  final value = rawUrl.trim();
  if (value.isEmpty) return Uri();
  final uri = Uri.parse(value);
  if (uri.hasScheme && uri.hasAuthority) return uri;
  return resolveBase.replace(
    path: uri.path,
    query: uri.hasQuery ? uri.query : null,
    fragment: uri.hasFragment ? uri.fragment : null,
  );
}
