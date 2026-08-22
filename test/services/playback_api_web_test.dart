@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:visionnaire/services/auth_request_headers.dart';
import 'package:visionnaire/services/playback_api.dart';

void main() {
  setUp(() => AuthRequestHeaders.setCsrfToken('test-csrf'));
  tearDown(AuthRequestHeaders.clearWebSession);

  test('revalidates the BFF session once after playback receives a 401',
      () async {
    final tokenForces = <bool>[];
    final authorizations = <String?>[];
    var requestCount = 0;
    final api = PlaybackApi(
      accessTokenProvider: ({bool force = false}) async {
        tokenForces.add(force);
        return 'web-bff-session';
      },
      client: MockClient((request) async {
        authorizations.add(request.headers['Authorization']);
        requestCount += 1;
        if (requestCount == 1) {
          return http.Response('{"detail":"app_session_expired"}', 401);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'id': 'single-1',
            'hls_url': '/hazard/media/single/index.m3u8',
            'expires_in': 600,
          }),
          200,
        );
      }),
    );

    await api.createSingle(site: 'site-a', camera: 'cam-1');

    expect(tokenForces, <bool>[false, true, false]);
    expect(authorizations, <String?>[null, null]);
  });
}
