import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/deployment_invitation.dart';
import '../models/deployment_profile.dart';
import '../utils/authenticated_uri.dart';
import 'api_config_service.dart';
import 'auth_request_headers.dart';
import 'deployment_invitation_http.dart';
import 'management_api_service.dart';

typedef DeploymentInvitationManagementUriProvider = Future<Uri> Function();
typedef DeploymentInvitationWebOriginProvider = Uri Function();

/// A typed client-side protocol failure from the invitation API.
///
/// [invitationCode] is an internal failure category, never an enrollment code.
/// It is deliberately separate from HTTP failures, which use
/// [ManagementApiException] so `AuthUtils.withAuthRetryOnError` can refresh a
/// native token after a 401 response.
final class DeploymentInvitationException extends ManagementApiException {
  const DeploymentInvitationException(
    this.invitationCode, {
    super.statusCode = 0,
  }) : super(message: 'Deployment invitation request could not be completed.');

  final String invitationCode;

  @override
  String? get code => invitationCode;
}

/// Transport for authenticated administrator invitation requests.
///
/// The service supplies a verified management endpoint and platform-correct
/// authentication headers. It is injectable only to make protocol tests
/// deterministic; production uses [CredentialedDeploymentInvitationTransport].
abstract interface class DeploymentInvitationTransport {
  Future<http.Response> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  });
}

/// Sends authenticated requests without allowing a redirect to replay them.
///
/// Native builds send the bearer header built by [AuthRequestHeaders]. Flutter
/// Web uses the same-origin BFF cookie transport and never exposes a bearer
/// credential to browser code. Both implementations set
/// `followRedirects = false` before they send a request.
final class CredentialedDeploymentInvitationTransport
    implements DeploymentInvitationTransport {
  CredentialedDeploymentInvitationTransport({
    Duration requestTimeout = const Duration(seconds: 15),
    http.Client? httpClient,
  })  : _requestTimeout = requestTimeout,
        _httpClient = httpClient {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'The invitation request timeout must be positive.',
      );
    }
  }

  final Duration _requestTimeout;
  final http.Client? _httpClient;

  @override
  Future<http.Response> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) {
    return sendDeploymentInvitationHttpRequest(
      method: method,
      uri: uri,
      headers: headers,
      body: body,
      timeout: _requestTimeout,
      httpClient: _httpClient,
    );
  }
}

/// Creates, lists, and revokes short-lived device invitations.
///
/// This is the authenticated administrator-side API. It is intentionally
/// separate from the public Registry exchange endpoint: a manager creates the
/// code here, then a native device redeems it at the fixed Registry and only
/// receives a deployment ID.
final class DeploymentInvitationService {
  factory DeploymentInvitationService({
    bool? isWeb,
    DeploymentInvitationManagementUriProvider? managementBaseUriProvider,
    DeploymentInvitationWebOriginProvider? webOriginProvider,
    DeploymentInvitationTransport? transport,
  }) {
    return DeploymentInvitationService._(
      isWeb: isWeb ?? kIsWeb,
      managementBaseUriProvider:
          managementBaseUriProvider ?? _defaultManagementBaseUri,
      webOriginProvider: webOriginProvider ?? _defaultWebOrigin,
      transport: transport ?? CredentialedDeploymentInvitationTransport(),
    );
  }

  DeploymentInvitationService._({
    required bool isWeb,
    required DeploymentInvitationManagementUriProvider
        managementBaseUriProvider,
    required DeploymentInvitationWebOriginProvider webOriginProvider,
    required DeploymentInvitationTransport transport,
  })  : _isWeb = isWeb,
        _managementBaseUriProvider = managementBaseUriProvider,
        _webOriginProvider = webOriginProvider,
        _transport = transport;

  static final DeploymentInvitationService shared =
      DeploymentInvitationService();

  final bool _isWeb;
  final DeploymentInvitationManagementUriProvider _managementBaseUriProvider;
  final DeploymentInvitationWebOriginProvider _webOriginProvider;
  final DeploymentInvitationTransport _transport;

  /// Creates a one-time code and returns that raw code exactly once.
  ///
  /// [requestToken] is an opaque native bearer credential or the Web BFF
  /// request marker supplied by `UnifiedAuthProvider`. Callers should wrap
  /// this method with `AuthUtils.withAuthRetryOnError`.
  Future<CreatedDeploymentInvitation> create({
    required String requestToken,
    required int expiresInMinutes,
  }) async {
    final CreateDeploymentInvitationRequest request =
        CreateDeploymentInvitationRequest(expiresInMinutes: expiresInMinutes);
    final http.Response response = await _send(
      method: 'POST',
      requestToken: requestToken,
      body: jsonEncode(request.toJson()),
      requiresCsrf: true,
    );
    _requireStatus(response, expected: 200);
    try {
      return CreatedDeploymentInvitation.fromJson(
        _parseJsonObject(response, 'Deployment invitation create response'),
      );
    } on FormatException {
      throw const DeploymentInvitationException('invalid_invitation_response');
    }
  }

  /// Lists non-secret invitation metadata visible to the signed-in manager.
  Future<List<DeploymentInvitation>> list({
    required String requestToken,
  }) async {
    final http.Response response = await _send(
      method: 'GET',
      requestToken: requestToken,
    );
    _requireStatus(response, expected: 200);
    final Map<String, Object?> json =
        _parseJsonObject(response, 'Deployment invitation list response');
    if (json.length != 1 || !json.containsKey('items')) {
      throw const DeploymentInvitationException('invalid_invitation_response');
    }
    final Object? rawItems = json['items'];
    if (rawItems is! List) {
      throw const DeploymentInvitationException('invalid_invitation_response');
    }

    try {
      return List<DeploymentInvitation>.unmodifiable(
        rawItems.map(
          (Object? item) => DeploymentInvitation.fromJson(
            deploymentInvitationJsonObject(
              item,
              responseName: 'Deployment invitation list item',
            ),
          ),
        ),
      );
    } on FormatException {
      throw const DeploymentInvitationException('invalid_invitation_response');
    }
  }

  /// Revokes an invitation. A successful DELETE returns an empty 204 body.
  Future<void> revoke({
    required String requestToken,
    required String invitationId,
  }) async {
    final String id;
    try {
      id = DeploymentProfileContract.requiredUuid(invitationId, 'id');
    } on DeploymentProfileFormatException {
      throw const DeploymentInvitationException('invalid_invitation_id');
    }

    final http.Response response = await _send(
      method: 'DELETE',
      requestToken: requestToken,
      invitationId: id,
      requiresCsrf: true,
    );
    _requireStatus(response, expected: 204);
    if (response.bodyBytes.isNotEmpty) {
      throw const DeploymentInvitationException('invalid_invitation_response');
    }
  }

  Future<http.Response> _send({
    required String method,
    required String requestToken,
    String? body,
    String? invitationId,
    bool requiresCsrf = false,
  }) async {
    final Uri endpoint;
    final Map<String, String> headers;
    try {
      endpoint = _endpointUri(
        await _managementBaseUriProvider(),
        invitationId: invitationId,
      );
      if (_isWeb) _requireSameWebOrigin(endpoint, _webOriginProvider());
      headers = _requestHeaders(
        requestToken: requestToken,
        requiresCsrf: requiresCsrf,
        includesJsonBody: body != null,
      );
      return await _transport.send(
        method: method,
        uri: endpoint,
        headers: headers,
        body: body,
      );
    } on DeploymentInvitationException {
      rethrow;
    } on TimeoutException {
      throw const DeploymentInvitationException('invitation_unavailable');
    } catch (_) {
      throw const DeploymentInvitationException('invitation_unavailable');
    }
  }

  Map<String, String> _requestHeaders({
    required String requestToken,
    required bool requiresCsrf,
    required bool includesJsonBody,
  }) {
    if (requestToken.isEmpty || requestToken.trim() != requestToken) {
      throw const DeploymentInvitationException('invitation_unauthenticated');
    }

    final Map<String, String> baseHeaders = <String, String>{
      'accept': 'application/json',
      'cache-control': 'no-store',
      if (includesJsonBody) 'content-type': 'application/json',
    };
    if (!_isWeb) {
      return AuthRequestHeaders.forRequest(
        requestToken,
        headers: baseHeaders,
      );
    }

    final String? csrfToken = AuthRequestHeaders.csrfToken;
    if (requiresCsrf && csrfToken == null) {
      throw const DeploymentInvitationException('invitation_csrf_missing');
    }

    // Pass no bearer token even in VM tests configured with isWeb: true.
    // In a browser, AuthRequestHeaders also contributes the existing CSRF
    // credential; setting it explicitly keeps the testable web branch strict.
    return <String, String>{
      ...AuthRequestHeaders.forRequest('', headers: baseHeaders),
      if (requiresCsrf) 'X-CSRF-Token': csrfToken!,
    };
  }

  static Future<Uri> _defaultManagementBaseUri() async {
    final String value = await ApiConfigService.getApiUrl('management');
    final Uri? uri = Uri.tryParse(value);
    if (uri == null) {
      throw const DeploymentInvitationException('invalid_management_api_url');
    }
    return uri;
  }

  static Uri _defaultWebOrigin() => Uri.base;

  static Uri _endpointUri(Uri baseUri, {String? invitationId}) {
    if (!baseUri.isAbsolute ||
        !baseUri.hasAuthority ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment) {
      throw const DeploymentInvitationException('invalid_management_api_url');
    }

    final String basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final String suffix = invitationId == null
        ? '/deployment-enrollment-codes'
        : '/deployment-enrollment-codes/${Uri.encodeComponent(invitationId)}';
    return baseUri.replace(path: '$basePath$suffix');
  }

  static void _requireSameWebOrigin(Uri endpoint, Uri webOrigin) {
    if (!webOrigin.isAbsolute ||
        !webOrigin.hasAuthority ||
        webOrigin.host.isEmpty ||
        webOrigin.userInfo.isNotEmpty ||
        !AuthenticatedUri.isSameOrigin(endpoint, webOrigin)) {
      throw const DeploymentInvitationException(
        'invitation_cross_origin_rejected',
      );
    }
  }

  static Map<String, Object?> _parseJsonObject(
    http.Response response,
    String responseName,
  ) {
    final String contentType = response.headers['content-type']
            ?.split(';')
            .first
            .trim()
            .toLowerCase() ??
        '';
    if (contentType != 'application/json') {
      throw const DeploymentInvitationException('invalid_invitation_response');
    }
    final Set<String> cacheDirectives =
        (response.headers['cache-control'] ?? '')
            .split(',')
            .map((String value) => value.trim().toLowerCase())
            .toSet();
    if (!cacheDirectives.contains('no-store')) {
      throw const DeploymentInvitationException('invalid_invitation_response');
    }
    try {
      return deploymentInvitationJsonObject(
        jsonDecode(utf8.decode(response.bodyBytes)),
        responseName: responseName,
      );
    } on FormatException {
      throw const DeploymentInvitationException('invalid_invitation_response');
    } on ArgumentError {
      throw const DeploymentInvitationException('invalid_invitation_response');
    }
  }

  static void _requireStatus(
    http.Response response, {
    required int expected,
  }) {
    if (response.statusCode == expected) return;
    if (_isRedirect(response.statusCode)) {
      throw DeploymentInvitationException(
        'invitation_redirect_rejected',
        statusCode: response.statusCode,
      );
    }
    throw _httpFailure(response);
  }

  static ManagementApiException _httpFailure(http.Response response) {
    final Map<String, dynamic>? data = _safeErrorData(
      _tryDecodeJson(response.bodyBytes),
    );
    return ManagementApiException(
      statusCode: response.statusCode,
      // Error text is untrusted and could echo a one-time enrollment code.
      // Keep a generic display value; [data] only preserves safe structured
      // fields such as detail.code needed by AuthFailurePolicy.
      message: 'Invitation request failed (${response.statusCode}).',
      data: data,
    );
  }

  static Map<String, dynamic>? _safeErrorData(Object? decoded) {
    if (decoded is! Map) return null;
    // The only server data this client needs from an error is an auth code for
    // [AuthFailurePolicy]. Copying arbitrary error JSON could retain a raw
    // one-time code, including when a proxy has nested it in an error object.
    final Object? detail = decoded['detail'];
    if (detail is Map && detail['code'] is String) {
      return <String, dynamic>{
        'detail': <String, String>{'code': detail['code'] as String},
      };
    }
    if (decoded['code'] is String) {
      return <String, dynamic>{'code': decoded['code'] as String};
    }
    return null;
  }

  static Object? _tryDecodeJson(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
  }

  static bool _isRedirect(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }
}
