import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Sends one same-origin invitation-management request without redirects.
///
/// `BrowserClient` maps [http.BaseRequest.followRedirects] set to `false` to
/// Fetch's `redirect: 'error'`. This makes the browser reject a redirect before
/// it can replay a cookie-authenticated request at another origin.
Future<http.Response> sendDeploymentInvitationHttpRequest({
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  required Duration timeout,
  String? body,
  http.Client? httpClient,
}) async {
  final http.Client client =
      httpClient ?? (BrowserClient()..withCredentials = true);
  final bool ownsClient = httpClient == null;
  if (client is BrowserClient) client.withCredentials = true;

  final http.Request request = http.Request(method, uri)
    ..followRedirects = false
    ..maxRedirects = 0
    ..headers.addAll(headers);
  if (body != null) request.body = body;

  try {
    return await (() async {
      final http.StreamedResponse response = await client.send(request);
      return http.Response.fromStream(response);
    })()
        .timeout(timeout);
  } finally {
    if (ownsClient) client.close();
  }
}
