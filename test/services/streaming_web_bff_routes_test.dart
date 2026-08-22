@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:visionnaire/services/api_config_service.dart';
import 'package:visionnaire/services/auth_request_headers.dart';
import 'package:visionnaire/services/platform_http_client.dart';
import 'package:visionnaire/services/streaming_web_api_service.dart';

void main() {
  tearDown(AuthRequestHeaders.clearWebSession);

  test('global web HTTP client includes HttpOnly cookies', () {
    final client = createPlatformHttpClient();
    addTearDown(client.close);

    expect(client, isA<BrowserClient>());
    expect((client as BrowserClient).withCredentials, isTrue);
  });

  test('web service bases use /bff/{service} without /api', () async {
    final expectedPaths = <String, String>{
      'chat': '/bff/chat',
      'management': '/bff/db_management',
      'fcm': '/bff/fcm',
      'streaming_web': '/bff/streaming_web',
      'fileManagement': '/bff/file_manage',
      'violationRecords': '/bff/violations',
    };

    for (final entry in expectedPaths.entries) {
      final uri = Uri.parse(await ApiConfigService.getApiUrl(entry.key));
      expect(uri.path, entry.value, reason: entry.key);
    }
  });

  test('labels and streams stay under the streaming_web service', () async {
    final requestedPaths = <String>[];
    final client = MockClient((request) async {
      requestedPaths.add(request.url.path);
      expect(request.headers, isNot(contains('Authorization')));
      if (request.url.path.endsWith('/labels')) {
        return http.Response(
            jsonEncode(<String, dynamic>{'labels': <String>[]}), 200);
      }
      return http.Response(
          jsonEncode(<String, dynamic>{'streams': <dynamic>[]}), 200);
    });

    await http.runWithClient(
      () async {
        await StreamingWebAPIService.fetchLabels(token: 'web-bff-session');
        await StreamingWebAPIService.fetchStreams(
          label: 'Site A',
          token: 'web-bff-session',
        );
      },
      () => client,
    );

    expect(requestedPaths, <String>[
      '/bff/streaming_web/labels',
      '/bff/streaming_web/streams/Site%20A',
    ]);
  });
}
