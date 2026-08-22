import 'package:http/http.dart' as http;

Future<http.Response> sendJsonRequest(
  String method,
  Uri uri, {
  required Map<String, String> headers,
  Object? body,
  required Duration timeout,
}) {
  switch (method) {
    case 'GET':
      return http.get(uri, headers: headers).timeout(timeout);
    case 'POST':
      return http.post(uri, headers: headers, body: body).timeout(timeout);
    case 'PUT':
      return http.put(uri, headers: headers, body: body).timeout(timeout);
    case 'DELETE':
      return http.delete(uri, headers: headers, body: body).timeout(timeout);
    default:
      throw ArgumentError('Unsupported HTTP method: $method');
  }
}
