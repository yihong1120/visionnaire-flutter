import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/services/auth_request_headers.dart';

void main() {
  tearDown(AuthRequestHeaders.clearWebSession);

  test('native request uses the bearer token', () {
    final headers = AuthRequestHeaders.forRequest(
      'native-token',
      headers: const <String, String>{'Accept': 'application/json'},
    );

    expect(headers['Accept'], 'application/json');
    expect(headers['Authorization'], 'Bearer native-token');
    expect(headers, isNot(contains('X-CSRF-Token')));
  }, skip: kIsWeb);

  test('empty native credential does not create an authorization header', () {
    expect(
      AuthRequestHeaders.forRequest(''),
      isNot(contains('Authorization')),
    );
  }, skip: kIsWeb);

  test('web request uses CSRF and never creates a bearer header', () {
    AuthRequestHeaders.setCsrfToken('csrf-value');

    final headers = AuthRequestHeaders.forRequest('web-bff-session');

    expect(headers['X-CSRF-Token'], 'csrf-value');
    expect(headers, isNot(contains('Authorization')));
  }, skip: !kIsWeb);
}
