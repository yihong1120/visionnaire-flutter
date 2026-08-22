import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/utils/authenticated_http.dart';

void main() {
  test('does not follow a redirect carrying authenticated headers', () async {
    final HttpServer target =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final HttpServer source =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var targetRequests = 0;
    String? sourceAuthorization;

    target.listen((HttpRequest request) async {
      targetRequests += 1;
      await request.response.close();
    });
    source.listen((HttpRequest request) async {
      sourceAuthorization =
          request.headers.value(HttpHeaders.authorizationHeader);
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          'http://${target.address.address}:${target.port}/redirect-target',
        );
      await request.response.close();
    });

    try {
      final response = await AuthenticatedHttp.get(
        Uri.parse('http://${source.address.address}:${source.port}/source'),
        headers: const <String, String>{
          HttpHeaders.authorizationHeader: 'Bearer test-token',
        },
        timeout: const Duration(seconds: 5),
      );

      expect(response.statusCode, HttpStatus.found);
      expect(sourceAuthorization, 'Bearer test-token');
      expect(targetRequests, 0);
    } finally {
      await source.close(force: true);
      await target.close(force: true);
    }
  });
}
