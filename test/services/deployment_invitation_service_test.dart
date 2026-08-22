import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:visionnaire/models/deployment_invitation.dart';
import 'package:visionnaire/services/auth_request_headers.dart';
import 'package:visionnaire/services/deployment_invitation_service.dart';
import 'package:visionnaire/services/management_api_service.dart';

const String _invitationId = '0000000a-0000-4000-8000-000000000001';
final Uri _managementBase =
    Uri(scheme: 'https', host: 'api.example.test', path: '/db_management');

void main() {
  tearDown(AuthRequestHeaders.clearWebSession);

  test('creates an invitation with the exact authenticated request contract',
      () async {
    final _RecordingTransport transport = _RecordingTransport(
      response: _jsonResponse(<String, String>{
        'id': _invitationId,
        'enrollment_code': 'code-9F2_A',
        'expires_at': '2026-08-21T12:00:00Z',
      }),
    );
    final DeploymentInvitationService service = _service(transport);

    final CreatedDeploymentInvitation invitation = await service.create(
      requestToken: 'native-access-token',
      expiresInMinutes: 30,
    );

    expect(invitation.id, _invitationId);
    expect(invitation.enrollmentCode, 'code-9F2_A');
    expect(invitation.expiresAt.isUtc, isTrue);
    final _CapturedRequest request = transport.requests.single;
    expect(request.method, 'POST');
    expect(
      request.uri,
      Uri.parse(
        'https://api.example.test/db_management/deployment-enrollment-codes',
      ),
    );
    expect(request.headers['Authorization'], 'Bearer native-access-token');
    expect(request.headers['x-csrf-token'], isNull);
    expect(request.headers['accept'], 'application/json');
    expect(request.headers['cache-control'], 'no-store');
    expect(request.headers['content-type'], 'application/json');
    expect(request.body, '{"expires_in_minutes":30}');
  }, skip: kIsWeb);

  test('lists only non-secret invitation metadata', () async {
    final _RecordingTransport transport = _RecordingTransport(
      response: _jsonResponse(<String, Object?>{
        'items': <Map<String, String>>[
          <String, String>{
            'id': _invitationId,
            'expires_at': '2026-08-21T12:00:00Z',
            'status': 'active',
          },
        ],
      }),
    );
    final DeploymentInvitationService service = _service(transport);

    final List<DeploymentInvitation> invitations = await service.list(
      requestToken: 'native-access-token',
    );

    expect(invitations, hasLength(1));
    expect(invitations.single.id, _invitationId);
    expect(invitations.single.status, DeploymentInvitationStatus.active);
    expect(transport.requests.single.method, 'GET');
    expect(transport.requests.single.body, isNull);
  });

  test('revokes an invitation using a canonical ID and an empty 204 response',
      () async {
    final _RecordingTransport transport = _RecordingTransport(
      response: http.Response('', 204),
    );
    final DeploymentInvitationService service = _service(transport);

    await service.revoke(
      requestToken: 'native-access-token',
      invitationId: _invitationId,
    );

    final _CapturedRequest request = transport.requests.single;
    expect(request.method, 'DELETE');
    expect(
      request.uri,
      Uri.parse(
        'https://api.example.test/db_management/'
        'deployment-enrollment-codes/$_invitationId',
      ),
    );
    expect(request.body, isNull);
    expect(request.headers['Authorization'], 'Bearer native-access-token');
  }, skip: kIsWeb);

  test('uses BFF cookie and CSRF authentication instead of a bearer token',
      () async {
    AuthRequestHeaders.setCsrfToken('web-csrf-token');
    final _RecordingTransport transport = _RecordingTransport(
      response: _jsonResponse(<String, String>{
        'id': _invitationId,
        'enrollment_code': 'safe-code',
        'expires_at': '2026-08-21T12:00:00Z',
      }),
    );
    final DeploymentInvitationService service = DeploymentInvitationService(
      isWeb: true,
      managementBaseUriProvider: () async => Uri.parse(
        'https://app.example.test/bff/db_management',
      ),
      webOriginProvider: () => Uri.parse('https://app.example.test'),
      transport: transport,
    );

    await service.create(
      requestToken: 'web-bff-marker',
      expiresInMinutes: 10,
    );

    final _CapturedRequest request = transport.requests.single;
    expect(request.headers['X-CSRF-Token'], 'web-csrf-token');
    expect(request.headers.containsKey('authorization'), isFalse);
    expect(
      request.uri,
      Uri.parse(
        'https://app.example.test/bff/db_management/'
        'deployment-enrollment-codes',
      ),
    );
  });

  test('requires a web CSRF credential before a mutation is sent', () async {
    final _RecordingTransport transport = _RecordingTransport(
      response: _jsonResponse(<String, String>{
        'id': _invitationId,
        'enrollment_code': 'safe-code',
        'expires_at': '2026-08-21T12:00:00Z',
      }),
    );
    final DeploymentInvitationService service = DeploymentInvitationService(
      isWeb: true,
      managementBaseUriProvider: () async => _managementBase,
      webOriginProvider: () => Uri.parse('https://api.example.test'),
      transport: transport,
    );

    await _expectProtocolFailure(
      service.create(requestToken: 'web-bff-marker', expiresInMinutes: 10),
      'invitation_csrf_missing',
    );
    expect(transport.requests, isEmpty);
  });

  test('rejects malformed schemas, leaked codes in list data, and bad values',
      () async {
    final _SequentialTransport transport = _SequentialTransport(
      <http.Response>[
        _jsonResponse(<String, String>{
          'id': _invitationId,
          'enrollment_code': 'safe-code',
          'expires_at': '2026-08-21T12:00:00+00:00',
        }),
        _jsonResponse(<String, Object?>{
          'items': <Map<String, String>>[
            <String, String>{
              'id': _invitationId,
              'enrollment_code': 'must-not-be-here',
              'expires_at': '2026-08-21T12:00:00Z',
              'status': 'active',
            },
          ],
        }),
        _jsonResponse(<String, Object?>{
          'items': <Map<String, String>>[
            <String, String>{
              'id': _invitationId.toUpperCase(),
              'expires_at': '2026-08-21T12:00:00Z',
              'status': 'active',
            },
          ],
        }),
        _jsonResponse(<String, Object?>{
          'items': <Map<String, String>>[
            <String, String>{
              'id': _invitationId,
              'expires_at': '2026-08-21T12:00:00Z',
              'status': 'unknown',
            },
          ],
        }),
      ],
    );
    final DeploymentInvitationService service = _service(transport);

    await _expectProtocolFailure(
      service.create(requestToken: 'native-access-token', expiresInMinutes: 10),
      'invalid_invitation_response',
    );
    await _expectProtocolFailure(
      service.list(requestToken: 'native-access-token'),
      'invalid_invitation_response',
    );
    await _expectProtocolFailure(
      service.list(requestToken: 'native-access-token'),
      'invalid_invitation_response',
    );
    await _expectProtocolFailure(
      service.list(requestToken: 'native-access-token'),
      'invalid_invitation_response',
    );
  });

  test('validates local arguments before a request and preserves HTTP 401',
      () async {
    final _RecordingTransport transport = _RecordingTransport(
      response: http.Response(
        jsonEncode(<String, Object?>{
          'detail': <String, String>{'code': 'expired_access_token'},
        }),
        401,
        headers: const <String, String>{'content-type': 'application/json'},
      ),
    );
    final DeploymentInvitationService service = _service(transport);

    expect(
      () => service.create(
        requestToken: 'native-access-token',
        expiresInMinutes: 0,
      ),
      throwsArgumentError,
    );
    await _expectProtocolFailure(
      service.revoke(
        requestToken: 'native-access-token',
        invitationId: 'not-a-uuid',
      ),
      'invalid_invitation_id',
    );
    expect(transport.requests, isEmpty);

    await expectLater(
      service.list(requestToken: 'native-access-token'),
      throwsA(
        isA<ManagementApiException>()
            .having((ManagementApiException error) => error.statusCode,
                'statusCode', 401)
            .having(
              (ManagementApiException error) => error.code,
              'code',
              'expired_access_token',
            ),
      ),
    );
  });

  test('rejects an empty request token before a request is sent', () async {
    final _RecordingTransport transport = _RecordingTransport(
      response: _jsonResponse(<String, Object?>{'items': <Object?>[]}),
    );
    final DeploymentInvitationService service = _service(transport);

    await _expectProtocolFailure(
      service.list(requestToken: ''),
      'invitation_unauthenticated',
    );
    expect(transport.requests, isEmpty);
  });

  test('rejects a cross-origin Web management endpoint before a request',
      () async {
    AuthRequestHeaders.setCsrfToken('web-csrf-token');
    final _RecordingTransport transport = _RecordingTransport(
      response: _jsonResponse(<String, Object?>{'items': <Object?>[]}),
    );
    final DeploymentInvitationService service = DeploymentInvitationService(
      isWeb: true,
      managementBaseUriProvider: () async => Uri.parse(
        'https://api.example.test/bff/db_management',
      ),
      webOriginProvider: () => Uri.parse('https://app.example.test'),
      transport: transport,
    );

    await _expectProtocolFailure(
      service.list(requestToken: 'web-bff-marker'),
      'invitation_cross_origin_rejected',
    );
    expect(transport.requests, isEmpty);
  });

  test('accepts an explicit default port for a same-origin Web BFF', () async {
    AuthRequestHeaders.setCsrfToken('web-csrf-token');
    final _RecordingTransport transport = _RecordingTransport(
      response: _jsonResponse(<String, Object?>{'items': <Object?>[]}),
    );
    final DeploymentInvitationService service = DeploymentInvitationService(
      isWeb: true,
      managementBaseUriProvider: () async => Uri.parse(
        'https://app.example.test:443/bff/db_management',
      ),
      webOriginProvider: () => Uri.parse('https://app.example.test'),
      transport: transport,
    );

    await service.list(requestToken: 'web-bff-marker');
    expect(transport.requests, hasLength(1));
  });

  test('Web transport disables redirects before dispatch', () async {
    late http.BaseRequest captured;
    final _CapturingHttpClient client = _CapturingHttpClient(
      (http.BaseRequest request) async {
        captured = request;
        return http.StreamedResponse(const Stream<List<int>>.empty(), 302);
      },
    );
    final CredentialedDeploymentInvitationTransport transport =
        CredentialedDeploymentInvitationTransport(httpClient: client);

    final http.Response response = await transport.send(
      method: 'GET',
      uri: Uri.parse(
        'https://app.example.test/bff/db_management/deployment-enrollment-codes',
      ),
      headers: const <String, String>{'X-CSRF-Token': 'web-csrf-token'},
    );

    expect(response.statusCode, 302);
    expect(captured.followRedirects, isFalse);
    expect(captured.maxRedirects, 0);
  }, skip: !kIsWeb);

  test('requires no-store for successful JSON responses', () async {
    final _RecordingTransport transport = _RecordingTransport(
      response: http.Response(
        jsonEncode(<String, Object?>{'items': <Object?>[]}),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      ),
    );

    await _expectProtocolFailure(
      _service(transport).list(requestToken: 'native-access-token'),
      'invalid_invitation_response',
    );
  });

  test('sanitizes enrollment codes from HTTP error data and messages',
      () async {
    final _RecordingTransport transport = _RecordingTransport(
      response: http.Response(
        jsonEncode(<String, Object?>{
          'enrollment_code': 'top-secret-code',
          'detail': <String, Object?>{
            'code': 'expired_access_token',
            'message': 'top-secret-code must never be displayed',
            'nested': <String, String>{'enrollment_code': 'nested-secret'},
          },
        }),
        401,
        headers: const <String, String>{'content-type': 'application/json'},
      ),
    );

    try {
      await _service(transport).list(requestToken: 'native-access-token');
      fail('Expected an HTTP failure.');
    } on ManagementApiException catch (error) {
      expect(error.statusCode, 401);
      expect(error.code, 'expired_access_token');
      expect(error.message, 'Invitation request failed (401).');
      final String serialized = jsonEncode(error.data);
      expect(serialized, isNot(contains('top-secret-code')));
      expect(serialized, isNot(contains('nested-secret')));
      expect(serialized, isNot(contains('enrollment_code')));
    }
  });

  test('rejects redirects and a non-empty DELETE response', () async {
    final _SequentialTransport transport = _SequentialTransport(
      <http.Response>[
        http.Response('', 302),
        http.Response('unexpected', 204),
      ],
    );
    final DeploymentInvitationService service = _service(transport);

    await _expectProtocolFailure(
      service.list(requestToken: 'native-access-token'),
      'invitation_redirect_rejected',
    );
    await _expectProtocolFailure(
      service.revoke(
        requestToken: 'native-access-token',
        invitationId: _invitationId,
      ),
      'invalid_invitation_response',
    );
  });
}

DeploymentInvitationService _service(DeploymentInvitationTransport transport) {
  return DeploymentInvitationService(
    isWeb: false,
    managementBaseUriProvider: () async => _managementBase,
    transport: transport,
  );
}

Future<void> _expectProtocolFailure(Future<Object?> operation, String code) {
  return expectLater(
    operation,
    throwsA(
      isA<DeploymentInvitationException>().having(
        (DeploymentInvitationException error) => error.code,
        'code',
        code,
      ),
    ),
  );
}

http.Response _jsonResponse(Object body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const <String, String>{
      'content-type': 'application/json',
      'cache-control': 'no-store',
    },
  );
}

final class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

class _RecordingTransport implements DeploymentInvitationTransport {
  _RecordingTransport({required this.response});

  final http.Response response;
  final List<_CapturedRequest> requests = <_CapturedRequest>[];

  @override
  Future<http.Response> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) async {
    requests.add(
      _CapturedRequest(
        method: method,
        uri: uri,
        headers: Map<String, String>.from(headers),
        body: body,
      ),
    );
    return response;
  }
}

final class _SequentialTransport extends _RecordingTransport {
  _SequentialTransport(this._responses) : super(response: _responses.first);

  final List<http.Response> _responses;
  var _index = 0;

  @override
  Future<http.Response> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) async {
    await super.send(method: method, uri: uri, headers: headers, body: body);
    return _responses[_index++];
  }
}

final class _CapturingHttpClient extends http.BaseClient {
  _CapturingHttpClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}
