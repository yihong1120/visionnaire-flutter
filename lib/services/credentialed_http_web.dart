import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

Future<http.Response> sendJsonRequest(
  String method,
  Uri uri, {
  required Map<String, String> headers,
  Object? body,
  required Duration timeout,
}) async {
  final requestUri = _sameOriginRelativeUri(uri);
  final client = BrowserClient()..withCredentials = true;
  try {
    switch (method) {
      case 'GET':
        return await client.get(requestUri, headers: headers).timeout(timeout);
      case 'POST':
        return await client
            .post(requestUri, headers: headers, body: body)
            .timeout(timeout);
      case 'PUT':
        return await client
            .put(requestUri, headers: headers, body: body)
            .timeout(timeout);
      case 'DELETE':
        return await client
            .delete(requestUri, headers: headers, body: body)
            .timeout(timeout);
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }
  } finally {
    client.close();
  }
}

Uri _sameOriginRelativeUri(Uri uri) {
  final location = web.window.location;
  final protocol = location.protocol.replaceFirst(':', '');
  final port = location.port;
  final authority =
      port.isEmpty ? location.hostname : '${location.hostname}:$port';

  if (uri.scheme == protocol && uri.authority == authority) {
    return Uri(
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    );
  }

  return uri;
}
