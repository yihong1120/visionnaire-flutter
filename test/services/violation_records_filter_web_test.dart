@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:visionnaire/services/violation_records_api_service.dart';

void main() {
  test('web filter options stay under the violations BFF route', () async {
    late http.Request request;
    await http.runWithClient(
      () => ViolationRecordsAPIService.getViolationFilterOptions(
        token: 'web-session',
        siteId: 7,
      ),
      () => MockClient((http.Request value) async {
        request = value;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'cameras': <dynamic>[],
            'violation_types': <dynamic>[],
          }),
          200,
        );
      }),
    );

    expect(request.url.path, '/bff/violations/filter-options');
    expect(request.url.queryParameters, <String, String>{'site_id': '7'});
    expect(request.headers, isNot(contains('Authorization')));
  });
}
