import 'package:http/http.dart' as http;

import 'auth_request_headers.dart';

/// A complete native authentication credential rotation.
///
/// Access and refresh tokens are validated together so callers cannot commit a
/// half-updated native session.
class NativeTokenPair {
  factory NativeTokenPair({
    required String accessToken,
    required String refreshToken,
  }) {
    final String normalisedAccessToken = _requireToken(
      accessToken,
      name: 'accessToken',
    );
    final String normalisedRefreshToken = _requireToken(
      refreshToken,
      name: 'refreshToken',
    );
    return NativeTokenPair._(
      accessToken: normalisedAccessToken,
      refreshToken: normalisedRefreshToken,
    );
  }

  const NativeTokenPair._({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;

  static String _requireToken(String value, {required String name}) {
    final String normalised = value.trim();
    if (normalised.isEmpty) {
      throw ArgumentError.value(value, name, 'Token must not be empty.');
    }
    return normalised;
  }
}

/// Raised before a native authenticated request when no access token exists.
class MissingAuthenticatedSessionException implements Exception {
  const MissingAuthenticatedSessionException();

  @override
  String toString() =>
      'MissingAuthenticatedSessionException: No native access token is set.';
}

/// Owns the in-memory authentication credentials used by authenticated API
/// clients.
///
/// It never persists either token. [UnifiedAuthProvider] keeps a native refresh
/// token in encrypted secure storage and restores a fresh access token only in
/// memory. API clients, including push registration, therefore never need a
/// token passed in from a page or coordinator.
class AuthSessionManager {
  AuthSessionManager({http.Client? client}) : _client = client ?? http.Client();

  static final AuthSessionManager shared = AuthSessionManager();

  final http.Client _client;

  String? _accessToken;
  String? _refreshToken;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;

  /// Replaces a rotated native token pair as one synchronous state change.
  void replaceTokens(NativeTokenPair tokens) {
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;
  }

  /// Clears both in-memory native credentials together.
  void clearTokens() {
    _accessToken = null;
    _refreshToken = null;
  }

  /// Restores only the encrypted refresh credential at app startup.
  ///
  /// Any access token is discarded because access tokens are memory-only and
  /// must be obtained again from the refresh endpoint.
  void restoreRefreshToken(String? refreshToken) {
    _accessToken = null;
    _refreshToken = _normalise(refreshToken);
  }

  /// Removes the access token while retaining the refresh credential for
  /// biometric unlock.
  void lockAccessToken() {
    _accessToken = null;
  }

  Future<http.Response> put(
    Uri uri, {
    required String body,
    Map<String, String> headers = const <String, String>{},
  }) {
    return _client.put(
      uri,
      headers: _authenticatedHeaders(headers),
      body: body,
    );
  }

  Future<http.Response> delete(
    Uri uri, {
    required String body,
    Map<String, String> headers = const <String, String>{},
  }) {
    return _client.delete(
      uri,
      headers: _authenticatedHeaders(headers),
      body: body,
    );
  }

  Map<String, String> _authenticatedHeaders(Map<String, String> headers) {
    final String? accessToken = _accessToken;
    if (accessToken == null) {
      throw const MissingAuthenticatedSessionException();
    }
    return AuthRequestHeaders.forRequest(accessToken, headers: headers);
  }

  static String? _normalise(String? value) {
    final String? trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
