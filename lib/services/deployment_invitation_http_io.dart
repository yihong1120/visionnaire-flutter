import 'package:http/http.dart' as http;

/// Sends one invitation-management request without following redirects.
///
/// The caller owns [httpClient] when supplied.  A transport-created client is
/// closed after the request completes.
Future<http.Response> sendDeploymentInvitationHttpRequest({
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  required Duration timeout,
  String? body,
  http.Client? httpClient,
}) async {
  final http.Client client = httpClient ?? http.Client();
  final bool ownsClient = httpClient == null;
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
