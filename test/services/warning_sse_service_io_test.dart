import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/services/warning_sse_service.dart';

void main() {
  test('native SSE refreshes once after 401 and reconnects with the new token',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    final authorizations = <String?>[];
    var requestCount = 0;
    server.listen((request) async {
      authorizations
          .add(request.headers.value(HttpHeaders.authorizationHeader));
      requestCount += 1;

      if (requestCount == 1) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }

      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response.write('event: metadata\ndata: {"has_warning":true}\n\n');
      await request.response.close();
    });

    var accessToken = 'expired-token';
    final refreshCalls = <bool>[];
    final metadata = Completer<Map<String, dynamic>>();
    final connection = await connectWarningSse(
      baseUrl: 'http://${server.address.address}:${server.port}',
      label: 'site-a',
      streamId: 'cam-1',
      streamKey: 'slot-0',
      tokenProvider: ({bool force = false}) async {
        refreshCalls.add(force);
        if (force) accessToken = 'refreshed-token';
        return accessToken;
      },
      onMetadata: (_, data) => metadata.complete(data),
    );
    addTearDown(connection.close);

    expect(
      await metadata.future.timeout(const Duration(seconds: 3)),
      <String, dynamic>{'has_warning': true},
    );
    expect(authorizations, <String?>[
      'Bearer expired-token',
      'Bearer refreshed-token',
    ]);
    expect(refreshCalls, <bool>[false, true, false]);
  });

  test('native SSE reports 403 once and does not reconnect', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    var requestCount = 0;
    server.listen((request) async {
      requestCount += 1;
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
    });

    final error = Completer<Object>();
    final connection = await connectWarningSse(
      baseUrl: 'http://${server.address.address}:${server.port}',
      label: 'site-a',
      streamId: 'cam-1',
      streamKey: 'slot-0',
      tokenProvider: ({bool force = false}) async => 'access-token',
      onMetadata: (_, __) {},
      onError: (_, value) => error.complete(value),
    );
    addTearDown(connection.close);

    final value = await error.future.timeout(const Duration(seconds: 3));
    expect(value, isA<WarningSseHttpException>());
    expect((value as WarningSseHttpException).statusCode, HttpStatus.forbidden);

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(requestCount, 1);
  });
}
