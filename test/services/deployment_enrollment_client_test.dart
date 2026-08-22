import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:visionnaire/services/deployment_enrollment_client.dart';

const String _deploymentId = '0000000a-0000-4000-8000-000000000001';

void main() {
  test('exchanges the raw code with an exact fixed-registry request', () async {
    late http.BaseRequest capturedRequest;
    final DeploymentEnrollmentClient client = DeploymentEnrollmentClient(
      registryBaseUri: Uri.parse('https://registry.example.test/managed'),
      httpClient: _FakeClient((http.BaseRequest request) async {
        capturedRequest = request;
        return _jsonResponse(<String, String>{'deployment_id': _deploymentId});
      }),
    );

    final String deploymentId = await client.exchange('  invite-code  ');

    expect(deploymentId, _deploymentId);
    expect(
      capturedRequest.url,
      Uri.parse(
          'https://registry.example.test/managed/v1/enrollments/exchange'),
    );
    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.followRedirects, isFalse);
    expect(capturedRequest.maxRedirects, 0);
    expect(capturedRequest.headers['accept'], 'application/json');
    expect(capturedRequest.headers['cache-control'], 'no-store');
    expect(capturedRequest.headers['content-type'], 'application/json');
    expect(capturedRequest.headers.containsKey('authorization'), isFalse);
    expect(capturedRequest.headers.containsKey('cookie'), isFalse);
    expect(
      utf8.decode((capturedRequest as http.Request).bodyBytes),
      '{"enrollment_code":"  invite-code  "}',
    );
  });

  test('normalizes one terminal slash in the fixed registry URL', () async {
    late http.BaseRequest capturedRequest;
    final DeploymentEnrollmentClient client = DeploymentEnrollmentClient(
      registryBaseUri: Uri.parse('https://registry.example.test/managed/'),
      httpClient: _FakeClient((http.BaseRequest request) async {
        capturedRequest = request;
        return _jsonResponse(<String, String>{'deployment_id': _deploymentId});
      }),
    );

    await client.exchange('invite-code');

    expect(
      capturedRequest.url,
      Uri.parse(
          'https://registry.example.test/managed/v1/enrollments/exchange'),
    );
  });

  test('rejects an empty enrollment code before sending a request', () async {
    final DeploymentEnrollmentClient client = DeploymentEnrollmentClient(
      registryBaseUri: Uri.parse('https://registry.example.test'),
      httpClient: _FakeClient((_) => throw StateError('must not send')),
    );

    await _expectFailure(client.exchange(''), 'invalid_enrollment_code');
  });

  test('rejects redirects instead of following them', () async {
    final DeploymentEnrollmentClient client = DeploymentEnrollmentClient(
      registryBaseUri: Uri.parse('https://registry.example.test'),
      httpClient: _FakeClient(
        (_) async => http.StreamedResponse(
          const Stream<List<int>>.empty(),
          302,
          headers: const <String, String>{'location': 'https://other.test'},
        ),
      ),
    );

    await _expectFailure(
      client.exchange('invite-code'),
      'enrollment_redirect_rejected',
    );
  });

  test('requires exact response JSON, canonical ID, and JSON content type',
      () async {
    final List<http.StreamedResponse> responses = <http.StreamedResponse>[
      _jsonResponse(<String, String>{
        'deployment_id': _deploymentId,
        'unexpected': 'value',
      }),
      _jsonResponse(<String, String>{
        'deployment_id': _deploymentId.toUpperCase(),
      }),
      http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(
              jsonEncode(<String, String>{'deployment_id': _deploymentId})),
        ),
        200,
        headers: const <String, String>{'content-type': 'text/plain'},
      ),
      http.StreamedResponse(
        Stream<List<int>>.value(List<int>.filled(1025, 0x20)),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      ),
    ];

    for (final http.StreamedResponse response in responses) {
      final DeploymentEnrollmentClient client = DeploymentEnrollmentClient(
        registryBaseUri: Uri.parse('https://registry.example.test'),
        httpClient: _FakeClient((_) async => response),
      );

      await _expectFailure(
        client.exchange('invite-code'),
        'invalid_enrollment_response',
      );
    }
  });

  test('maps a rejected code and transport failures to safe typed errors',
      () async {
    final DeploymentEnrollmentClient rejected = DeploymentEnrollmentClient(
      registryBaseUri: Uri.parse('https://registry.example.test'),
      httpClient: _FakeClient(
        (_) async => http.StreamedResponse(
          const Stream<List<int>>.empty(),
          403,
        ),
      ),
    );
    final DeploymentEnrollmentClient unavailable = DeploymentEnrollmentClient(
      registryBaseUri: Uri.parse('https://registry.example.test'),
      httpClient: _FakeClient((_) => throw StateError('network failed')),
    );

    await _expectFailure(
        rejected.exchange('invite-code'), 'enrollment_code_rejected');
    await _expectFailure(
        unavailable.exchange('invite-code'), 'enrollment_unavailable');
  });

  test('rejects non-HTTPS or non-canonical registry roots', () {
    expect(
      () => DeploymentEnrollmentClient(
        registryBaseUri: Uri.parse('http://registry.example.test'),
      ),
      throwsA(
        isA<DeploymentEnrollmentException>().having(
          (DeploymentEnrollmentException error) => error.code,
          'code',
          'invalid_registry_url',
        ),
      ),
    );
    expect(
      () => DeploymentEnrollmentClient(
        registryBaseUri: Uri.parse('https://registry.example.test?query=value'),
      ),
      throwsA(
        isA<DeploymentEnrollmentException>().having(
          (DeploymentEnrollmentException error) => error.code,
          'code',
          'invalid_registry_url',
        ),
      ),
    );
  });
}

Future<void> _expectFailure(Future<Object?> operation, String code) {
  return expectLater(
    operation,
    throwsA(
      isA<DeploymentEnrollmentException>().having(
        (DeploymentEnrollmentException error) => error.code,
        'code',
        code,
      ),
    ),
  );
}

http.StreamedResponse _jsonResponse(Map<String, String> body) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    200,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

final class _FakeClient extends http.BaseClient {
  _FakeClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}
