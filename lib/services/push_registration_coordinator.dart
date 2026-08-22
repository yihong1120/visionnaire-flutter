import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/bff_config.dart';
import 'api_config_service.dart';
import 'auth_request_headers.dart';
import 'auth_session_manager.dart';
import 'credentialed_http.dart' as credentialed_http;

typedef FcmTokenProvider = Future<String?> Function();
typedef FcmTokenRefreshStreamProvider = Stream<String> Function();
typedef DeviceLocaleProvider = DeviceLocale Function();
typedef NativeDevicesUriProvider = Future<Uri> Function();
typedef HttpRequest = Future<http.Response> Function(
  Uri uri, {
  required String body,
  required Map<String, String> headers,
});

/// A non-empty Firebase-managed registration token.
class FcmToken {
  FcmToken._(this.value);

  final String value;

  static FcmToken? tryParse(String? value) {
    final String? normalised = value?.trim();
    if (normalised == null || normalised.isEmpty) return null;
    return FcmToken._(normalised);
  }
}

/// Locales accepted by the strict FCM device registration schema.
enum DeviceLocale {
  enGb('en-GB'),
  zhTw('zh-TW'),
  zhCn('zh-CN'),
  frFr('fr-FR'),
  viVn('vi-VN'),
  idId('id-ID'),
  thTh('th-TH'),
  jaJp('ja-JP');

  const DeviceLocale(this.wireValue);

  final String wireValue;

  static DeviceLocale fromLocale(Locale locale) {
    final String languageCode = locale.languageCode.toLowerCase();
    final String? countryCode = locale.countryCode?.toUpperCase();
    final String? candidate = countryCode == null || countryCode.isEmpty
        ? null
        : '$languageCode-$countryCode';

    if (candidate != null) {
      for (final DeviceLocale locale in values) {
        if (locale.wireValue == candidate) return locale;
      }
    }

    return switch (languageCode) {
      'zh' => countryCode == 'CN' ? zhCn : zhTw,
      'en' => enGb,
      'fr' => frFr,
      'vi' => viVn,
      'id' => idId,
      'th' => thTh,
      'ja' => jaJp,
      _ => enGb,
    };
  }
}

/// Platform values accepted by the strict FCM device registration schema.
enum PushPlatform {
  web('web'),
  ios('ios'),
  android('android');

  const PushPlatform(this.wireValue);

  final String wireValue;
}

class DeviceRegistrationRequest {
  const DeviceRegistrationRequest({
    required this.deviceToken,
    required this.deviceLocale,
    required this.platform,
  });

  final FcmToken deviceToken;
  final DeviceLocale deviceLocale;
  final PushPlatform platform;

  Map<String, String> toJson() => <String, String>{
        'device_token': deviceToken.value,
        'device_lang': deviceLocale.wireValue,
        'platform': platform.wireValue,
      };
}

class DeviceRemovalRequest {
  const DeviceRemovalRequest({required this.deviceToken});

  final FcmToken deviceToken;

  Map<String, String> toJson() => <String, String>{
        'device_token': deviceToken.value,
      };
}

abstract interface class PushDeviceTransport {
  Future<void> register(DeviceRegistrationRequest request);

  Future<void> remove(DeviceRemovalRequest request);
}

/// Raised before a Web mutation when the BFF CSRF credential is unavailable.
class MissingWebCsrfTokenException implements Exception {
  const MissingWebCsrfTokenException();

  @override
  String toString() =>
      'MissingWebCsrfTokenException: No BFF CSRF token is available.';
}

/// Native FCM transport. [AuthSessionManager] adds the bearer credential.
class NativePushDeviceTransport implements PushDeviceTransport {
  NativePushDeviceTransport({
    required AuthSessionManager authSessionManager,
    required NativeDevicesUriProvider devicesUriProvider,
  })  : _authSessionManager = authSessionManager,
        _devicesUriProvider = devicesUriProvider;

  final AuthSessionManager _authSessionManager;
  final NativeDevicesUriProvider _devicesUriProvider;

  @override
  Future<void> register(DeviceRegistrationRequest request) async {
    final Uri uri = await _devicesUriProvider();
    final http.Response response = await _authSessionManager.put(
      uri,
      body: jsonEncode(request.toJson()),
      headers: _jsonHeaders,
    );
    _throwIfPushRequestFailed(response, 'register push device');
  }

  @override
  Future<void> remove(DeviceRemovalRequest request) async {
    final Uri uri = await _devicesUriProvider();
    final http.Response response = await _authSessionManager.delete(
      uri,
      body: jsonEncode(request.toJson()),
      headers: _jsonHeaders,
    );
    _throwIfPushRequestFailed(response, 'remove push device');
  }
}

/// Web FCM transport. Authentication is the BFF cookie plus CSRF header only.
class BffPushDeviceTransport implements PushDeviceTransport {
  BffPushDeviceTransport({
    Uri? devicesUri,
    HttpRequest? put,
    HttpRequest? delete,
  })  : _devicesUri = devicesUri ?? BffConfig.fcmDevicesUri,
        _put = put ?? _defaultWebPut,
        _delete = delete ?? _defaultWebDelete;

  final Uri _devicesUri;
  final HttpRequest _put;
  final HttpRequest _delete;

  @override
  Future<void> register(DeviceRegistrationRequest request) async {
    final http.Response response = await _put(
      _devicesUri,
      body: jsonEncode(request.toJson()),
      headers: _webBffHeaders(),
    );
    _throwIfPushRequestFailed(response, 'register push device');
  }

  @override
  Future<void> remove(DeviceRemovalRequest request) async {
    final http.Response response = await _delete(
      _devicesUri,
      body: jsonEncode(request.toJson()),
      headers: _webBffHeaders(),
    );
    _throwIfPushRequestFailed(response, 'remove push device');
  }

  /// Cookie authentication is implicit. This map intentionally cannot acquire
  /// an Authorization header, even when tested outside a web runtime.
  static Map<String, String> _webBffHeaders() {
    final String? csrfToken = AuthRequestHeaders.csrfToken;
    if (csrfToken == null) throw const MissingWebCsrfTokenException();
    return <String, String>{
      ..._jsonHeaders,
      'X-CSRF-Token': csrfToken,
    };
  }
}

const Map<String, String> _jsonHeaders = <String, String>{
  'Content-Type': 'application/json',
};
const Duration _pushRequestTimeout = Duration(seconds: 30);

Future<http.Response> _defaultWebPut(
  Uri uri, {
  required String body,
  required Map<String, String> headers,
}) =>
    credentialed_http.sendJsonRequest(
      'PUT',
      uri,
      body: body,
      headers: headers,
      timeout: _pushRequestTimeout,
    );

Future<http.Response> _defaultWebDelete(
  Uri uri, {
  required String body,
  required Map<String, String> headers,
}) =>
    credentialed_http.sendJsonRequest(
      'DELETE',
      uri,
      body: body,
      headers: headers,
      timeout: _pushRequestTimeout,
    );

void _throwIfPushRequestFailed(http.Response response, String action) {
  if (response.statusCode >= 200 && response.statusCode < 300) return;
  if (response.statusCode == 422 && kDebugMode) {
    debugPrint(
      '[PushRegistration] $action rejected (422): '
      '${utf8.decode(response.bodyBytes)}',
    );
  }
  throw http.ClientException(
    'Failed to $action (status ${response.statusCode})',
    response.request?.url,
  );
}

/// Registers the current Firebase Messaging token for the signed-in session.
///
/// This is deliberately application-global. Authentication owns access and
/// refresh credentials through [AuthSessionManager]; this coordinator owns only
/// the Firebase token lifecycle and device registration endpoints.
class PushRegistrationCoordinator {
  factory PushRegistrationCoordinator({
    AuthSessionManager? authSessionManager,
    FcmTokenProvider? fcmTokenProvider,
    FcmTokenRefreshStreamProvider? fcmTokenRefreshStreamProvider,
    DeviceLocaleProvider? deviceLocaleProvider,
    NativeDevicesUriProvider? nativeDevicesUriProvider,
    HttpRequest? webPut,
    HttpRequest? webDelete,
    PushDeviceTransport? transport,
    bool? isWeb,
    TargetPlatform Function()? platformProvider,
  }) {
    final bool resolvedIsWeb = isWeb ?? kIsWeb;
    final AuthSessionManager resolvedAuthSessionManager =
        authSessionManager ?? AuthSessionManager.shared;
    final PushDeviceTransport resolvedTransport = transport ??
        (resolvedIsWeb
            ? BffPushDeviceTransport(put: webPut, delete: webDelete)
            : NativePushDeviceTransport(
                authSessionManager: resolvedAuthSessionManager,
                devicesUriProvider:
                    nativeDevicesUriProvider ?? _defaultNativeDevicesUri,
              ));

    return PushRegistrationCoordinator._(
      fcmTokenProvider: fcmTokenProvider ?? _getFcmToken,
      fcmTokenRefreshStreamProvider:
          fcmTokenRefreshStreamProvider ?? _getFcmTokenRefreshStream,
      deviceLocaleProvider: deviceLocaleProvider ?? _defaultDeviceLocale,
      transport: resolvedTransport,
      isWeb: resolvedIsWeb,
      platformProvider: platformProvider ?? (() => defaultTargetPlatform),
    );
  }

  PushRegistrationCoordinator._({
    required FcmTokenProvider fcmTokenProvider,
    required FcmTokenRefreshStreamProvider fcmTokenRefreshStreamProvider,
    required DeviceLocaleProvider deviceLocaleProvider,
    required PushDeviceTransport transport,
    required bool isWeb,
    required TargetPlatform Function() platformProvider,
  })  : _fcmTokenProvider = fcmTokenProvider,
        _fcmTokenRefreshStreamProvider = fcmTokenRefreshStreamProvider,
        _deviceLocaleProvider = deviceLocaleProvider,
        _transport = transport,
        _isWeb = isWeb,
        _platformProvider = platformProvider;

  static final PushRegistrationCoordinator shared =
      PushRegistrationCoordinator();

  final FcmTokenProvider _fcmTokenProvider;
  final FcmTokenRefreshStreamProvider _fcmTokenRefreshStreamProvider;
  final DeviceLocaleProvider _deviceLocaleProvider;
  final PushDeviceTransport _transport;
  final bool _isWeb;
  final TargetPlatform Function() _platformProvider;

  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _isSignedIn = false;

  /// Obtains the Firebase-managed FCM token, registers it, and starts one
  /// process-wide refresh subscription.
  Future<void> onSignedIn() async {
    _isSignedIn = true;
    _ensureTokenRefreshListener();

    final FcmToken? fcmToken = FcmToken.tryParse(await _fcmTokenProvider());
    if (fcmToken != null) await _registerDevice(fcmToken);
  }

  /// Removes this device before the auth session and its bearer token are
  /// invalidated. Firebase remains the sole owner of the FCM token itself.
  Future<void> onSigningOut() async {
    // Flip this first so a concurrent refresh cannot re-register the device
    // while the DELETE request is in flight.
    _isSignedIn = false;

    final FcmToken? fcmToken = FcmToken.tryParse(await _fcmTokenProvider());
    if (fcmToken != null) {
      await _transport.remove(DeviceRemovalRequest(deviceToken: fcmToken));
    }
  }

  /// Stops native push registration before a deployment is replaced.
  ///
  /// This intentionally performs no network operation. Once the current
  /// deployment selection is cleared, its previous API origin must not receive
  /// a device-removal request or a later FCM token refresh. A later sign-in
  /// starts a fresh subscription for the newly verified deployment.
  Future<void> suspendForDeploymentChange() async {
    _isSignedIn = false;

    final StreamSubscription<String>? subscription = _tokenRefreshSubscription;
    _tokenRefreshSubscription = null;
    await subscription?.cancel();
  }

  Future<void> _registerDevice(FcmToken fcmToken) {
    if (!_isSignedIn) return Future<void>.value();
    return _transport.register(
      DeviceRegistrationRequest(
        deviceToken: fcmToken,
        deviceLocale: _deviceLocaleProvider(),
        platform: _platform,
      ),
    );
  }

  void _ensureTokenRefreshListener() {
    _tokenRefreshSubscription ??=
        _fcmTokenRefreshStreamProvider().listen((String fcmToken) {
      unawaited(_registerRefreshedToken(fcmToken));
    });
  }

  Future<void> _registerRefreshedToken(String value) async {
    final FcmToken? token = FcmToken.tryParse(value);
    if (!_isSignedIn || token == null) return;

    try {
      await _registerDevice(token);
    } on Exception catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[PushRegistration] token refresh failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  PushPlatform get _platform {
    if (_isWeb) return PushPlatform.web;
    return switch (_platformProvider()) {
      TargetPlatform.iOS => PushPlatform.ios,
      TargetPlatform.android => PushPlatform.android,
      _ => throw UnsupportedError('Unsupported FCM platform'),
    };
  }

  static Future<String?> _getFcmToken() =>
      FirebaseMessaging.instance.getToken();

  static Stream<String> _getFcmTokenRefreshStream() =>
      FirebaseMessaging.instance.onTokenRefresh;

  static DeviceLocale _defaultDeviceLocale() {
    return DeviceLocale.fromLocale(PlatformDispatcher.instance.locale);
  }

  /// The FCM API accepts this fixed language set. A device can report a
  /// language-only or unsupported locale (for example `en-US`), so normalize
  /// it before the strict PUT schema is built.
  static String normaliseDeviceLocale(Locale locale) =>
      DeviceLocale.fromLocale(locale).wireValue;

  static Future<Uri> _defaultNativeDevicesUri() async {
    final String baseUrl = await ApiConfigService.getApiUrl('fcm');
    return Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/devices');
  }
}
