import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionnaire/services/violation_records_api_service.dart';

import '../test_support/deployment_profile_test_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    installEnrollmentDeploymentProfile(debug: true);
  });

  tearDown(resetDeploymentProfile);

  test('loads filter options and sends camera and type query parameters',
      () async {
    final List<http.Request> requests = <http.Request>[];

    await http.runWithClient(
      () async {
        final ViolationFilterOptions options =
            await ViolationRecordsAPIService.getViolationFilterOptions(
          token: 'native-access',
          siteId: 7,
          groupId: 3,
        );
        expect(options.cameras, hasLength(1));
        expect(options.cameras.single.streamId, 'camera-1');
        expect(options.cameras.single.name, 'Cam 1');
        expect(options.violationTypes, hasLength(1));
        expect(options.violationTypes.single.code, 'near_vehicle');

        await ViolationRecordsAPIService.getViolations(
          token: 'native-access',
          siteId: 7,
          streamId: 'camera-1',
          violationType: 'near_vehicle',
        );
        await ViolationRecordsAPIService.getViolationAnalytics(
          token: 'native-access',
          siteId: 7,
          streamId: 'camera-1',
          violationType: 'near_vehicle',
        );
      },
      () => MockClient((http.Request request) async {
        requests.add(request);
        if (request.url.path.endsWith('/filter-options')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, dynamic>{
                'cameras': <Map<String, String>>[
                  <String, String>{
                    'stream_id': 'camera-1',
                    'name': 'Cam 1',
                  },
                  <String, String>{
                    'stream_id': 'camera-1',
                    'name': 'Duplicate',
                  },
                ],
                'violation_types': <Map<String, String>>[
                  <String, String>{
                    'code': 'near_vehicle',
                    'label': '人員靠近車輛',
                  },
                ],
              }),
            ),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        return http.Response('{}', 200);
      }),
    );

    expect(requests, hasLength(3));
    expect(requests.first.url.path, '/hazard/api/violations/filter-options');
    expect(requests.first.url.queryParameters, <String, String>{
      'site_id': '7',
      'group_id': '3',
    });
    for (final http.Request request in requests) {
      expect(request.headers['Authorization'], 'Bearer native-access');
    }

    expect(requests[1].url.queryParameters['stream_id'], 'camera-1');
    expect(requests[1].url.queryParameters['violation_type'], 'near_vehicle');
    expect(requests[2].url.queryParameters['stream_id'], 'camera-1');
    expect(requests[2].url.queryParameters['violation_type'], 'near_vehicle');
  });
}
