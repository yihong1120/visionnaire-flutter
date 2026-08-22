import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:visionnaire/services/auth_session_manager.dart';

class _RecordingClient extends http.BaseClient {
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(const Stream<List<int>>.empty(), 204);
  }
}

void main() {
  test('replaces and clears a complete native token pair atomically', () {
    final AuthSessionManager session = AuthSessionManager();

    session.replaceTokens(
      NativeTokenPair(
        accessToken: '  access-token  ',
        refreshToken: '  refresh-token  ',
      ),
    );

    expect(session.accessToken, 'access-token');
    expect(session.refreshToken, 'refresh-token');

    session.clearTokens();

    expect(session.accessToken, isNull);
    expect(session.refreshToken, isNull);
  });

  test('rejects an incomplete native token pair before changing a session', () {
    final AuthSessionManager session = AuthSessionManager()
      ..replaceTokens(
        NativeTokenPair(
          accessToken: 'existing-access',
          refreshToken: 'existing-refresh',
        ),
      );

    expect(
      () => NativeTokenPair(
        accessToken: 'next-access',
        refreshToken: '   ',
      ),
      throwsArgumentError,
    );
    expect(session.accessToken, 'existing-access');
    expect(session.refreshToken, 'existing-refresh');
  });

  test('restores refresh only and locks access without deleting refresh', () {
    final AuthSessionManager session = AuthSessionManager()
      ..replaceTokens(
        NativeTokenPair(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
        ),
      );

    session.lockAccessToken();
    expect(session.accessToken, isNull);
    expect(session.refreshToken, 'refresh-token');

    session.restoreRefreshToken('  restored-refresh  ');
    expect(session.accessToken, isNull);
    expect(session.refreshToken, 'restored-refresh');
  });

  test('fails before sending a native request when bearer is missing', () {
    final _RecordingClient client = _RecordingClient();
    final AuthSessionManager session = AuthSessionManager(client: client);

    expect(
      () => session.put(
        Uri.parse('https://example.test/devices'),
        body: '{}',
      ),
      throwsA(isA<MissingAuthenticatedSessionException>()),
    );
    expect(client.requests, isEmpty);
  });
}
