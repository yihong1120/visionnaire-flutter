import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:visionnaire/services/deployment_invitation_service.dart';

void main() {
  test('does not follow a redirect or forward native bearer credentials',
      () async {
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
      final CredentialedDeploymentInvitationTransport transport =
          CredentialedDeploymentInvitationTransport(
        requestTimeout: const Duration(seconds: 5),
      );
      final http.Response response = await transport.send(
        method: 'GET',
        uri:
            Uri.parse('http://${source.address.address}:${source.port}/source'),
        headers: const <String, String>{
          HttpHeaders.authorizationHeader: 'Bearer test-token',
        },
      );

      expect(response.statusCode, HttpStatus.found);
      expect(sourceAuthorization, 'Bearer test-token');
      expect(targetRequests, 0);
    } finally {
      await source.close(force: true);
      await target.close(force: true);
    }
  });

  test('marks the native request as non-redirecting before sending', () async {
    late http.BaseRequest captured;
    final _RecordingClient client =
        _RecordingClient((http.BaseRequest request) async {
      captured = request;
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        HttpStatus.found,
      );
    });
    final CredentialedDeploymentInvitationTransport transport =
        CredentialedDeploymentInvitationTransport(httpClient: client);

    final http.Response response = await transport.send(
      method: 'GET',
      uri: Uri.parse(
          'https://api.example.test/db_management/deployment-enrollment-codes'),
      headers: const <String, String>{'authorization': 'Bearer test-token'},
    );

    expect(response.statusCode, HttpStatus.found);
    expect(captured.followRedirects, isFalse);
    expect(captured.maxRedirects, 0);
    expect(captured.headers['authorization'], 'Bearer test-token');
  });
}

final class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}
