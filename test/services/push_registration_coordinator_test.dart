import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:visionnaire/config/bff_config.dart';
import 'package:visionnaire/services/auth_request_headers.dart';
import 'package:visionnaire/services/auth_session_manager.dart';
import 'package:visionnaire/services/push_registration_coordinator.dart';

class _RecordingClient extends http.BaseClient {
  final List<http.Request> requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final http.Request copied = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) copied.bodyBytes = request.bodyBytes;
    requests.add(copied);
    return http.StreamedResponse(
      Stream<List<int>>.value(const <int>[]),
      204,
      request: request,
    );
  }
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  tearDown(AuthRequestHeaders.clearWebSession);

  test('native registration uses the FCM API and session bearer token',
      () async {
    final client = _RecordingClient();
    final authSession = AuthSessionManager(client: client)
      ..replaceTokens(
        NativeTokenPair(
          accessToken: 'native-access-token',
          refreshToken: 'native-refresh-token',
        ),
      );
    final coordinator = PushRegistrationCoordinator(
      authSessionManager: authSession,
      fcmTokenProvider: () async => 'native-fcm-token',
      fcmTokenRefreshStreamProvider: Stream<String>.empty,
      deviceLocaleProvider: () => DeviceLocale.zhTw,
      nativeDevicesUriProvider: () async =>
          Uri.parse('https://fcm.example.test/api/devices'),
      isWeb: false,
      platformProvider: () => TargetPlatform.iOS,
    );

    await coordinator.onSignedIn();
    await coordinator.onSigningOut();

    expect(client.requests, hasLength(2));
    final putRequest = client.requests.first;
    final deleteRequest = client.requests.last;
    expect(putRequest.method, 'PUT');
    expect(putRequest.url.toString(), 'https://fcm.example.test/api/devices');
    expect(putRequest.headers['authorization'], 'Bearer native-access-token');
    expect(putRequest.headers['x-csrf-token'], isNull);
    expect(jsonDecode(putRequest.body), <String, dynamic>{
      'device_token': 'native-fcm-token',
      'device_lang': 'zh-TW',
      'platform': 'ios',
    });
    expect(deleteRequest.method, 'DELETE');
    expect(
        deleteRequest.headers['authorization'], 'Bearer native-access-token');
    expect(jsonDecode(deleteRequest.body), <String, dynamic>{
      'device_token': 'native-fcm-token',
    });
  });

  test(
      'suspending for a deployment change sends no request and blocks old refresh registration',
      () async {
    final client = _RecordingClient();
    final authSession = AuthSessionManager(client: client)
      ..replaceTokens(
        NativeTokenPair(
          accessToken: 'native-access-token',
          refreshToken: 'native-refresh-token',
        ),
      );
    final StreamController<String> refreshes =
        StreamController<String>.broadcast();
    final coordinator = PushRegistrationCoordinator(
      authSessionManager: authSession,
      fcmTokenProvider: () async => 'native-fcm-token',
      fcmTokenRefreshStreamProvider: () => refreshes.stream,
      deviceLocaleProvider: () => DeviceLocale.zhTw,
      nativeDevicesUriProvider: () async =>
          Uri.parse('https://fcm.example.test/api/devices'),
      isWeb: false,
      platformProvider: () => TargetPlatform.iOS,
    );
    addTearDown(() async {
      await coordinator.suspendForDeploymentChange();
      await refreshes.close();
    });

    await coordinator.onSignedIn();
    expect(client.requests, hasLength(1));

    await coordinator.suspendForDeploymentChange();
    expect(client.requests, hasLength(1));

    refreshes.add('refreshed-fcm-token');
    await Future<void>.delayed(Duration.zero);

    // Re-enrollment must not DELETE from, or PUT to, the old deployment.
    expect(client.requests, hasLength(1));
    expect(client.requests.single.method, 'PUT');

    // A later sign-in installs a new subscription for the newly selected
    // deployment rather than reviving the cancelled old one.
    await coordinator.onSignedIn();
    refreshes.add('new-deployment-fcm-token');
    await Future<void>.delayed(Duration.zero);

    expect(client.requests, hasLength(3));
    expect(client.requests[1].method, 'PUT');
    expect(client.requests[2].method, 'PUT');
  });

  test('web registration and removal use the BFF cookie/CSRF transport',
      () async {
    AuthRequestHeaders.setCsrfToken('csrf-token');
    Uri? putUri;
    Uri? deleteUri;
    Map<String, String>? putHeaders;
    Map<String, String>? deleteHeaders;
    Object? putBody;
    Object? deleteBody;

    final coordinator = PushRegistrationCoordinator(
      fcmTokenProvider: () async => 'web-fcm-token',
      fcmTokenRefreshStreamProvider: Stream<String>.empty,
      deviceLocaleProvider: () => DeviceLocale.zhTw,
      isWeb: true,
      webPut: (uri, {required body, required headers}) async {
        putUri = uri;
        putHeaders = headers;
        putBody = body;
        return http.Response('', 204);
      },
      webDelete: (uri, {required body, required headers}) async {
        deleteUri = uri;
        deleteHeaders = headers;
        deleteBody = body;
        return http.Response('', 204);
      },
    );

    await coordinator.onSignedIn();
    await coordinator.onSigningOut();

    expect(putUri, BffConfig.fcmDevicesUri);
    expect(deleteUri, BffConfig.fcmDevicesUri);
    expect(putUri!.path, '/bff/fcm/devices');
    expect(putHeaders!['X-CSRF-Token'], 'csrf-token');
    expect(deleteHeaders!['X-CSRF-Token'], 'csrf-token');
    expect(putHeaders!.containsKey('Authorization'), isFalse);
    expect(deleteHeaders!.containsKey('Authorization'), isFalse);
    final expectedPayload = <String, dynamic>{
      'device_token': 'web-fcm-token',
      'device_lang': 'zh-TW',
      'platform': 'web',
    };
    expect(jsonDecode(putBody! as String), expectedPayload);
    expect(jsonDecode(deleteBody! as String), <String, dynamic>{
      'device_token': 'web-fcm-token',
    });
  });

  test('normalizes device locales to the API allowlist', () {
    expect(
      PushRegistrationCoordinator.normaliseDeviceLocale(const Locale('zh')),
      'zh-TW',
    );
    expect(
      PushRegistrationCoordinator.normaliseDeviceLocale(
        const Locale('zh', 'CN'),
      ),
      'zh-CN',
    );
    expect(
      PushRegistrationCoordinator.normaliseDeviceLocale(
        const Locale('en', 'US'),
      ),
      'en-GB',
    );
    expect(
      PushRegistrationCoordinator.normaliseDeviceLocale(const Locale('ja')),
      'ja-JP',
    );
  });

  test('typed requests keep PUT and DELETE schemas separate', () {
    final FcmToken token = FcmToken.tryParse('  firebase-token  ')!;

    expect(
      DeviceRegistrationRequest(
        deviceToken: token,
        deviceLocale: DeviceLocale.zhTw,
        platform: PushPlatform.android,
      ).toJson(),
      <String, String>{
        'device_token': 'firebase-token',
        'device_lang': 'zh-TW',
        'platform': 'android',
      },
    );
    expect(
      DeviceRemovalRequest(deviceToken: token).toJson(),
      <String, String>{'device_token': 'firebase-token'},
    );
    expect(FcmToken.tryParse('  '), isNull);
    expect(FcmToken.tryParse(null), isNull);
  });

  test('web transport fails before mutation when CSRF token is missing',
      () async {
    AuthRequestHeaders.clearWebSession();
    bool requestSent = false;
    final BffPushDeviceTransport transport = BffPushDeviceTransport(
      put: (uri, {required body, required headers}) async {
        requestSent = true;
        return http.Response('', 204);
      },
    );
    final FcmToken token = FcmToken.tryParse('firebase-token')!;

    await expectLater(
      transport.register(
        DeviceRegistrationRequest(
          deviceToken: token,
          deviceLocale: DeviceLocale.enGb,
          platform: PushPlatform.web,
        ),
      ),
      throwsA(isA<MissingWebCsrfTokenException>()),
    );
    expect(requestSent, isFalse);
  });

  test('coordinator surfaces sign-in registration failures to auth', () async {
    AuthRequestHeaders.clearWebSession();
    final PushRegistrationCoordinator coordinator = PushRegistrationCoordinator(
      fcmTokenProvider: () async => 'web-fcm-token',
      fcmTokenRefreshStreamProvider: Stream<String>.empty,
      deviceLocaleProvider: () => DeviceLocale.enGb,
      isWeb: true,
    );

    await expectLater(
      coordinator.onSignedIn(),
      throwsA(isA<MissingWebCsrfTokenException>()),
    );
  });
}
