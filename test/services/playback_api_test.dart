import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionnaire/services/playback_api.dart';

import '../test_support/deployment_profile_test_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    installEnrollmentDeploymentProfile(debug: true);
  });

  tearDown(resetDeploymentProfile);

  test('createSingle uses unified playback session endpoint', () async {
    final requests = <http.Request>[];
    final api = PlaybackApi(
      accessTokenProvider: ({bool force = false}) async => 'app-access',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'id': 'single-1',
            'language': 'zh-TW',
            'renew_endpoint':
                '/hazard/api/db_management/api/playback/sessions/renew',
            'hls_url': '/hazard/media/single/index.m3u8',
            'expires_in': 600,
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final session = await api.createSingle(
      site: 'site-a',
      camera: 'cam-1',
      profile: 'overlay',
      language: 'zh-TW',
    );

    expect(requests, hasLength(1));
    expect(
      requests.single.url.path,
      '/hazard/api/db_management/api/playback/sessions',
    );
    expect(requests.single.headers['Authorization'], 'Bearer app-access');
    expect(
      jsonDecode(requests.single.body),
      <String, dynamic>{
        'site': 'site-a',
        'camera': 'cam-1',
        'profile': 'overlay',
        'language': 'zh-TW',
        'transport': 'hls',
      },
    );
    expect(session.id, 'single-1');
    expect(
      session.renewEndpoint,
      '/hazard/api/db_management/api/playback/sessions/renew',
    );
    expect(session.hlsUrl, '/hazard/media/single/index.m3u8');
    expect(session.language, 'zh-TW');
  });

  test('clean playback omits its irrelevant overlay language', () async {
    late http.Request request;
    final api = PlaybackApi(
      accessTokenProvider: ({bool force = false}) async => 'app-access',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'id': 'single-clean',
            'hls_url': '/hazard/media/single/clean.m3u8',
            'expires_in': 600,
          }),
          200,
        );
      }),
    );

    await api.createSingle(
      site: 'site-a',
      camera: 'cam-1',
      profile: 'clean',
      language: 'en',
    );

    expect(jsonDecode(request.body), <String, dynamic>{
      'site': 'site-a',
      'camera': 'cam-1',
      'profile': 'clean',
      'transport': 'hls',
    });
  });

  test('rejects a playback response with a different overlay language',
      () async {
    final api = PlaybackApi(
      accessTokenProvider: ({bool force = false}) async => 'app-access',
      client: MockClient((_) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'id': 'single-1',
            'language': 'en',
            'hls_url': '/hazard/media/single/index.m3u8',
            'expires_in': 600,
          }),
          200,
        );
      }),
    );

    await expectLater(
      api.createSingle(
        site: 'site-a',
        camera: 'cam-1',
        language: 'zh-TW',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('createWall uses unified playback wall endpoint', () async {
    final requests = <http.Request>[];
    final api = PlaybackApi(
      accessTokenProvider: ({bool force = false}) async => 'app-access',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'id': 'wall-1',
            'language': 'zh-TW',
            'renew_endpoint':
                '/hazard/api/db_management/api/playback/sessions/renew',
            'expires_in': 600,
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'title': 'Cam 1',
                'camera': 'Cam 1',
                'preview_hls_url': '/hazard/media/preview/index.m3u8',
              },
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final wall = await api.createWall(
      site: 'site-a',
      cameras: const <String>['cam-1', 'cam-2'],
      profile: 'overlay',
      language: 'zh-TW',
      transport: 'hls',
    );

    expect(requests, hasLength(1));
    expect(
      requests.single.url.path,
      '/hazard/api/db_management/api/playback/walls',
    );
    expect(requests.single.headers['Authorization'], 'Bearer app-access');
    expect(
      jsonDecode(requests.single.body),
      <String, dynamic>{
        'site': 'site-a',
        'cameras': <String>['cam-1', 'cam-2'],
        'profile': 'overlay',
        'language': 'zh-TW',
        'transport': 'hls',
      },
    );
    expect(wall.id, 'wall-1');
    expect(
      wall.renewEndpoint,
      '/hazard/api/db_management/api/playback/sessions/renew',
    );
    expect(wall.items.single.title, 'Cam 1');
    expect(wall.items.single.previewHlsUrl, '/hazard/media/preview/index.m3u8');
    expect(wall.language, 'zh-TW');
  });

  test('clean wall playback omits its irrelevant overlay language', () async {
    late http.Request request;
    final api = PlaybackApi(
      accessTokenProvider: ({bool force = false}) async => 'app-access',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'id': 'wall-clean',
            'expires_in': 600,
            'items': <Map<String, dynamic>>[],
          }),
          200,
        );
      }),
    );

    await api.createWall(site: 'site-a', profile: 'clean', language: 'en');

    expect(jsonDecode(request.body), <String, dynamic>{
      'site': 'site-a',
      'profile': 'clean',
      'transport': 'hls',
    });
  });

  test('createWall lets the playback facade choose all site cameras', () async {
    late http.Request request;
    final api = PlaybackApi(
      accessTokenProvider: ({bool force = false}) async => 'app-access',
      client: MockClient((value) async {
        request = value;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode(<String, dynamic>{
              'id': 'wall-1',
              'expires_in': 600,
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'stream_id': 'stream-1',
                  'camera': 'Cam 1',
                  'hls_url': '/hazard/media/wall/index.m3u8',
                },
              ],
            }),
          ),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );

    final wall = await api.createWall(site: 'site-a');

    expect(request.url.path, '/hazard/api/db_management/api/playback/walls');
    expect(jsonDecode(request.body), <String, dynamic>{
      'site': 'site-a',
      'profile': 'overlay',
      'language': 'zh-TW',
      'transport': 'hls',
    });
    expect(wall.items.single.streamId, 'stream-1');
    expect(wall.items.single.previewHlsUrl, '/hazard/media/wall/index.m3u8');
  });

  test('createWall excludes disabled streams before allocating wall tiles',
      () async {
    final api = PlaybackApi(
      accessTokenProvider: ({bool force = false}) async => 'app-access',
      client: MockClient((_) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'id': 'wall-1',
            'expires_in': 600,
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'stream_id': 'enabled-stream',
                'camera': 'Enabled camera',
                'recognition_enabled': true,
                'hls_url': '/hazard/media/enabled/index.m3u8',
              },
              <String, dynamic>{
                'stream_id': 'disabled-stream',
                'camera': 'Disabled camera',
                'recognition_enabled': false,
                'hls_url': '/hazard/media/disabled/index.m3u8',
              },
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final wall = await api.createWall(site: 'site-a');

    expect(wall.items, hasLength(1));
    expect(wall.items.single.streamId, 'enabled-stream');
  });

  test('renew posts to fixed endpoint and parses stable renewal response',
      () async {
    var count = 0;
    final paths = <String>[];
    final bodies = <Map<String, dynamic>>[];
    final api = PlaybackApi(
      accessTokenProvider: ({bool force = false}) async => 'app-access',
      client: MockClient((request) async {
        paths.add(request.url.path);
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        count += 1;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'id': count == 1 ? 'wall-1' : 'single-1',
            'mode': count == 1 ? 'multi_stream' : 'single_stream',
            'renew_endpoint':
                '/hazard/api/db_management/api/playback/sessions/renew',
            'expires_in': 600,
            'renewed': true,
            'hls_urls_changed': false,
          }),
          200,
        );
      }),
    );

    final wall = await api.renew(
      const PlaybackWall(
        id: 'wall-1',
        expiresIn: 600,
        renewEndpoint: '/hazard/api/db_management/api/playback/sessions/renew',
        items: <PlaybackWallItem>[],
      ),
    );
    final single = await api.renew(
      PlaybackSession(
        id: 'single-1',
        expiresIn: 600,
        renewEndpoint: null,
        hlsUrl: '/hazard/media/single/index.m3u8',
        hlsUri: Uri.parse('/hazard/media/single/index.m3u8'),
      ),
    );

    expect(wall, isA<PlaybackRenewal>());
    expect(wall.id, 'wall-1');
    expect(wall.renewed, isTrue);
    expect(wall.hlsUrlsChanged, isFalse);
    expect(single, isA<PlaybackRenewal>());
    expect(single.id, 'single-1');
    expect(paths, <String>[
      '/hazard/api/db_management/api/playback/sessions/renew',
      '/hazard/api/db_management/api/playback/sessions/renew',
    ]);
    expect(bodies, <Map<String, dynamic>>[
      <String, dynamic>{'id': 'wall-1'},
      <String, dynamic>{'id': 'single-1'},
    ]);
  });

  test('renew rejects a cross-origin endpoint before sending credentials',
      () async {
    final requests = <http.Request>[];
    var accessTokenCalls = 0;
    final api = PlaybackApi(
      accessTokenProvider: ({bool force = false}) async {
        accessTokenCalls += 1;
        return 'app-access';
      },
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('', 200);
      }),
    );

    await expectLater(
      api.renew(
        const PlaybackWall(
          id: 'wall-1',
          expiresIn: 600,
          renewEndpoint: 'https://attacker.example/playback/sessions/renew',
          items: <PlaybackWallItem>[],
        ),
      ),
      throwsA(isA<FormatException>()),
    );

    expect(requests, isEmpty);
    expect(accessTokenCalls, 0);
  });

  test('close deletes the playback session resource', () async {
    final paths = <String>[];
    final api = PlaybackApi(
      accessTokenProvider: ({bool force = false}) async => 'app-access',
      client: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response('', 204);
      }),
    );

    await api.close('session-1');

    expect(paths, <String>[
      '/hazard/api/db_management/api/playback/sessions/session-1',
    ]);
  });

  test('retries native playback once after a 401 with a refreshed token',
      () async {
    final authorizations = <String?>[];
    final tokenForces = <bool>[];
    var token = 'expired-access';
    var requestCount = 0;
    final api = PlaybackApi(
      accessTokenProvider: ({bool force = false}) async {
        tokenForces.add(force);
        if (force) token = 'refreshed-access';
        return token;
      },
      client: MockClient((request) async {
        authorizations.add(request.headers['Authorization']);
        requestCount += 1;
        if (requestCount == 1) {
          return http.Response('{"detail":"expired_token"}', 401);
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
    expect(authorizations, <String?>[
      'Bearer expired-access',
      'Bearer refreshed-access',
    ]);
  });

  test('playback renewal delay uses 50 percent with safe bounds', () {
    expect(playbackRenewalDelaySeconds(600), 300);
    expect(playbackRenewalDelaySeconds(60), 30);
    expect(playbackRenewalDelaySeconds(20), 30);
    expect(playbackRenewalDelaySeconds(1800), 600);
  });

  test('retries transient playback transport failures with capped backoff', () {
    expect(playbackRetryDelay(0), const Duration(seconds: 3));
    expect(playbackRetryDelay(1), const Duration(seconds: 6));
    expect(playbackRetryDelay(5), const Duration(seconds: 60));
    expect(playbackRetryDelay(20), const Duration(seconds: 60));

    expect(
      isRetryablePlaybackError(TimeoutException('request timed out')),
      isTrue,
    );
    expect(
        isRetryablePlaybackError(http.ClientException('dns failure')), isTrue);
    expect(
      isRetryablePlaybackError(
        const PlaybackApiException(503, 'service unavailable'),
      ),
      isTrue,
    );
    expect(
      isRetryablePlaybackError(const PlaybackApiException(401, 'expired')),
      isFalse,
    );
  });
}
