import 'package:http/http.dart' as http;

/// Sends an authenticated request without forwarding its headers on redirects.
///
/// Callers must validate the initial URI's origin before using this helper.
/// A redirect response is returned to the caller as-is so it can be handled as
/// a failed authenticated resource request instead of following a new URL.
abstract final class AuthenticatedHttp {
  static Future<http.Response> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    final http.Client client = http.Client();
    try {
      final http.Request request = http.Request('GET', uri)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.addAll(headers);
      final http.StreamedResponse response =
          await client.send(request).timeout(timeout);
      return await http.Response.fromStream(response);
    } finally {
      client.close();
    }
  }
}
