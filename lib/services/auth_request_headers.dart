import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Owns the browser CSRF credential and builds platform-correct auth headers.
///
/// Web authentication is cookie based, so bearer tokens must never be exposed
/// to browser code. Native clients continue to use bearer access tokens.
abstract final class AuthRequestHeaders {
  static String? _csrfToken;

  static String? get csrfToken => _csrfToken;

  static void setCsrfToken(String? value) {
    final normalised = value?.trim();
    _csrfToken = normalised == null || normalised.isEmpty ? null : normalised;
  }

  static void clearWebSession() => _csrfToken = null;

  static Map<String, String> forRequest(
    String token, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return <String, String>{
      ...headers,
      if (kIsWeb && _csrfToken != null) 'X-CSRF-Token': _csrfToken!,
      if (!kIsWeb && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static void apply(http.BaseRequest request, String token) {
    request.headers.addAll(forRequest(token));
  }
}
