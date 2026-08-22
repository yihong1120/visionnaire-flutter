import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionnaire/services/api_config_service.dart';
import 'package:visionnaire/services/streaming_web_api_service.dart';

import '../test_support/deployment_profile_test_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    installEnrollmentDeploymentProfile(debug: true);
  });

  tearDown(resetDeploymentProfile);

  test('native streaming defaults to the public API root', () async {
    expect(
      await ApiConfigService.getApiUrl('streaming_web'),
      'https://api.test.example/hazard/api',
    );
  });

  test('uses an explicitly configured streaming service URL unchanged',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'api_url_streaming_web':
          'https://api.example.invalid/hazard/api/streaming_web/',
    });

    expect(
      await ApiConfigService.getApiUrl('streaming_web'),
      'https://api.example.invalid/hazard/api/streaming_web/',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('api_url_streaming_web'), isTrue);
  });

  test('native labels and streams use public API routes with a bearer token',
      () async {
    final requests = <http.Request>[];

    await http.runWithClient(
      () async {
        await StreamingWebAPIService.fetchLabels(token: 'native-access');
        await StreamingWebAPIService.fetchStreams(
          label: 'Site A',
          token: 'native-access',
        );
      },
      () => MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/labels')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, dynamic>{
                'labels': <String>['Site A'],
              }),
            ),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{'streams': <dynamic>[]}),
          200,
        );
      }),
    );

    expect(
      requests.map((request) => request.url.path),
      <String>[
        '/hazard/api/labels',
        '/hazard/api/streams/Site%20A',
      ],
    );
    expect(
      requests.map((request) => request.headers['Authorization']),
      <String?>['Bearer native-access', 'Bearer native-access'],
    );
  });
}
