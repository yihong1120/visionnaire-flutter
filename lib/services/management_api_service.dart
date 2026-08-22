import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/bff_config.dart';
import 'api_config_service.dart';
import 'auth_request_headers.dart';
import 'credentialed_http.dart' as credentialed_http;

class ManagementApiException implements Exception {
  const ManagementApiException({
    required this.statusCode,
    required this.message,
    this.data,
  });

  final int statusCode;
  final String message;
  final Map<String, dynamic>? data;

  Map<String, dynamic>? get payload {
    final raw = data;
    if (raw == null) return null;

    final detail = raw['detail'];
    if (detail is Map) {
      return Map<String, dynamic>.from(detail);
    }
    return raw;
  }

  String? get code {
    final Object? value = payload?['code'];
    if (value is! String) return null;
    final String code = value.trim().toLowerCase();
    return code.isEmpty ? null : code;
  }

  bool get isAccountLocked {
    final normalizedPayload = payload;
    final codeValue = code;
    return statusCode == 423 ||
        codeValue == 'account_locked' ||
        normalizedPayload?['locked'] == true;
  }

  bool get isLoginCooldown {
    final codeValue = code;
    return statusCode == 429 || codeValue == 'login_cooldown';
  }

  bool get isCredentialFailure {
    final codeValue = code;
    return statusCode == 401 || codeValue == 'invalid_credentials';
  }

  bool get isEmailUnverified {
    final codeValue = code;
    return codeValue == 'email_unverified';
  }

  bool get isPendingApproval {
    final codeValue = code;
    return codeValue == 'pending_approval';
  }

  bool get isRejected {
    final codeValue = code;
    return codeValue == 'rejected';
  }

  int? get retryAfterSeconds {
    final normalizedPayload = payload;
    final Object? bodyValue = normalizedPayload?['retry_after_seconds'];
    return _secondsFromValue(bodyValue);
  }

  int? get lockedRemainingSeconds {
    final normalizedPayload = payload;
    final Object? lockedUntil = normalizedPayload?['locked_until'];
    return _secondsFromValue(lockedUntil);
  }

  int? get remainingAttempts {
    final normalizedPayload = payload;
    final Object? value = normalizedPayload?['remaining_attempts'];
    return _intFromValue(value);
  }

  static int? _intFromValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.floor();
    return null;
  }

  static int? _secondsFromValue(Object? value) {
    if (value == null) return null;
    if (value is num) return value.ceil();
    if (value is! String || value.trim().isEmpty) return null;
    final date = DateTime.tryParse(value);
    if (date == null) return null;
    final seconds = date.difference(DateTime.now()).inSeconds;
    return seconds > 0 ? seconds : null;
  }

  static String errorMessageFromData(Object? data, int statusCode) {
    final String genericMessage = 'Server error ($statusCode)';
    if (data is String && data.trim().isNotEmpty) return data.trim();
    if (data is! Map) return genericMessage;

    final Object? detail = data['detail'];
    if (detail is String && detail.trim().isNotEmpty) return detail.trim();
    if (detail is Map) {
      final Object? message = detail['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return genericMessage;
  }

  @override
  String toString() => message;
}

class AuthIdentity {
  const AuthIdentity({
    required this.id,
    required this.provider,
    this.providerUserId,
    this.email,
    this.emailVerified = false,
    this.displayName,
    this.linkedAt,
    this.updatedAt,
    this.canUnlink,
  });

  final String id;
  final String provider;
  final String? providerUserId;
  final String? email;
  final bool emailVerified;
  final String? displayName;
  final DateTime? linkedAt;
  final DateTime? updatedAt;
  final bool? canUnlink;

  bool get isGoogle => provider == 'google';
  bool get isApple => provider == 'apple';

  String get providerLabel {
    if (isGoogle) return 'Google';
    if (isApple) return 'Apple';
    return provider;
  }

  factory AuthIdentity.fromJson(Map<String, dynamic> json) {
    final Object? id = json['identity_id'];
    final Object? provider = json['provider'];
    final Object? emailVerified = json['email_verified'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Identity response is missing identity_id');
    }
    if (provider is! String || provider.trim().isEmpty) {
      throw const FormatException('Identity response is missing provider');
    }
    if (emailVerified is! bool) {
      throw const FormatException(
          'Identity response is missing email_verified');
    }

    return AuthIdentity(
      id: id.trim(),
      provider: provider.trim().toLowerCase(),
      providerUserId: _nullableString(json['provider_user_id']),
      email: _nullableString(json['email']),
      emailVerified: emailVerified,
      displayName: _nullableString(json['display_name']),
      linkedAt: _nullableDateTime(json['linked_at']),
      updatedAt: _nullableDateTime(json['updated_at']),
      canUnlink: _nullableBool(json['can_unlink']),
    );
  }

  static String? _nullableString(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException('Identity response contains a non-string');
    }
    final String text = value.trim();
    return text.isEmpty ? null : text;
  }

  static bool? _nullableBool(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    throw const FormatException('Identity response contains a non-boolean');
  }

  static DateTime? _nullableDateTime(Object? value) {
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Identity response contains an invalid date');
    }
    return DateTime.tryParse(value) ??
        (throw const FormatException(
            'Identity response contains an invalid date'));
  }
}

class LegalDocument {
  const LegalDocument({
    required this.type,
    required this.version,
    required this.title,
    required this.content,
  });

  final String type;
  final String version;
  final String title;
  final String content;

  factory LegalDocument.fromJson(
    String type,
    Map<String, dynamic> json,
  ) {
    final Object? version = json['version'];
    final Object? title = json['title'];
    final Object? content = json['content'];
    if (version is! String || title is! String || content is! String) {
      throw FormatException('Invalid $type legal document response');
    }
    if (version.trim().isEmpty ||
        title.trim().isEmpty ||
        content.trim().isEmpty) {
      throw FormatException('Incomplete $type legal document response');
    }
    return LegalDocument(
      type: type,
      version: version,
      title: title,
      content: content,
    );
  }
}

class LegalDocuments {
  const LegalDocuments({
    required this.terms,
    required this.privacy,
    required this.aiTerms,
  });

  final LegalDocument terms;
  final LegalDocument privacy;
  final LegalDocument aiTerms;

  factory LegalDocuments.fromJson(Map<String, dynamic> json) {
    return LegalDocuments(
      terms: _documentFrom(json, 'terms'),
      privacy: _documentFrom(json, 'privacy'),
      aiTerms: _documentFrom(json, 'ai_terms'),
    );
  }

  static LegalDocument _documentFrom(
    Map<String, dynamic> data,
    String key,
  ) {
    final Object? raw = data[key];
    if (raw is Map<String, dynamic>) {
      return LegalDocument.fromJson(key, raw);
    }
    if (raw is Map) {
      return LegalDocument.fromJson(key, Map<String, dynamic>.from(raw));
    }
    throw FormatException('Missing $key legal document response');
  }
}

/// Service class for backend management API (accounts, groups, sites, features, stream configs, etc).
///
/// Provides unified methods for all backend management API endpoints, including authentication, CRUD, and utility helpers.
class ManagementAPIService {
  /// Timeout for HTTP requests, in seconds.
  static const int timeoutSeconds = 600;

  /// Get the base URL from configuration service
  static Future<String> get baseUrl async {
    return await ApiConfigService.getApiUrl('management');
  }

  /// Unified handler for GET/POST/PUT/DELETE requests.
  ///
  /// [method]: 'GET' | 'POST' | 'PUT' | 'DELETE'
  /// [path]: Path starting with '/', not including baseUrl
  /// [body]: Map will be encoded as JSON
  /// [token]: Optional, if null, no Authorization header is sent
  static Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue$path');

    return _requestUri(method, uri, body: body, token: token);
  }

  static Future<dynamic> _requestUri(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    // Build headers
    final Map<String, String> headers = AuthRequestHeaders.forRequest(
      token ?? '',
      headers: const <String, String>{'Content-Type': 'application/json'},
    );

    final Object? encodedBody =
        method == 'GET' ? null : json.encode(body ?? <String, dynamic>{});
    final http.Response resp = await credentialed_http.sendJsonRequest(
      method,
      uri,
      headers: headers,
      body: encodedBody,
      timeout: const Duration(seconds: timeoutSeconds),
    );

    // Parse response; return {} for empty body
    final dynamic data = _decodeResponseBody(resp.bodyBytes);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return data;
    }
    if (kDebugMode) {
      // Never log request bodies, credentials, tokens, or response bodies.
      debugPrint(
        '[ManagementAPI] $method ${uri.path} returned ${resp.statusCode}.',
      );
    }
    final errorData = data is Map<String, dynamic>
        ? data
        : data is Map
            ? Map<String, dynamic>.from(data)
            : null;
    throw ManagementApiException(
      statusCode: resp.statusCode,
      message: ManagementApiException.errorMessageFromData(
        data,
        resp.statusCode,
      ),
      data: errorData,
    );
  }

  static Future<dynamic> _bffAuthRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) {
    return _requestUri(
      method,
      BffConfig.authUri(path),
      body: body,
    );
  }

  static dynamic _decodeResponseBody(List<int> bodyBytes) {
    if (bodyBytes.isEmpty) return <String, dynamic>{};
    final text = utf8.decode(bodyBytes);
    if (text.trim().isEmpty) return <String, dynamic>{};
    try {
      return json.decode(text);
    } catch (_) {
      return text;
    }
  }

  static Map<String, dynamic> _requireJsonObject(
    Object? data, {
    required String responseName,
  }) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw FormatException('$responseName must be a JSON object.');
  }

  /// Requests a password reset email. The backend should always return a
  /// generic success response to avoid revealing whether the email exists.
  static Future<void> requestPasswordReset({required String email}) async {
    await _request(
      'POST',
      '/password/forgot',
      body: <String, dynamic>{'email': email},
    );
  }

  static Future<LegalDocuments> fetchLegalDocuments({
    required String locale,
  }) async {
    final Object? data = await _request(
      'GET',
      '/legal/documents?locale=${Uri.encodeQueryComponent(locale)}',
    );
    return LegalDocuments.fromJson(
      _requireJsonObject(data, responseName: 'Legal documents response'),
    );
  }

  static Future<Map<String, dynamic>> verifyEmail({
    required String token,
  }) async {
    final dynamic data = await _request(
      'POST',
      '/auth/verify-email',
      body: <String, dynamic>{'token': token},
    );
    return data is Map<String, dynamic>
        ? data
        : data is Map
            ? Map<String, dynamic>.from(data)
            : <String, dynamic>{};
  }

  /// Resends an email verification link. The backend should respond with a
  /// generic success even when the account is unknown, preventing email
  /// enumeration.
  static Future<void> resendEmailVerification({
    required String identifier,
  }) async {
    await _request(
      'POST',
      '/auth/resend-verification',
      body: <String, dynamic>{
        'identifier': identifier,
        'email': identifier,
      },
    );
  }

  /// Resets a password using a one-time token received by email.
  static Future<void> resetPasswordWithToken({
    required String token,
    required String newPassword,
  }) async {
    await _request(
      'POST',
      '/password/reset',
      body: <String, dynamic>{
        'token': token,
        'new_password': newPassword,
      },
    );
  }

  // Convenience wrappers for each HTTP method
  static Future<dynamic> _get(String path, String token) =>
      _request('GET', path, token: token);
  static Future<dynamic> _post(
          String path, Map<String, dynamic> body, String token) =>
      _request('POST', path, body: body, token: token);
  static Future<dynamic> _put(
          String path, Map<String, dynamic> body, String token) =>
      _request('PUT', path, body: body, token: token);
  static Future<dynamic> _delete(
          String path, Map<String, dynamic> body, String token) =>
      _request('DELETE', path, body: body, token: token);

  /// Logs in and returns a token map.
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    String? hcaptchaToken,
  }) async {
    final Object? data = await (kIsWeb
        ? _bffAuthRequest
        : _request)('POST', kIsWeb ? 'login' : '/login', body: {
      'identifier': username,
      'password': password,
      if (hcaptchaToken != null && hcaptchaToken.isNotEmpty)
        'hcaptcha_token': hcaptchaToken,
    });
    return _requireJsonObject(data, responseName: 'Login response');
  }

  /// Exchanges a Google ID token for Visionnaire JWTs.
  static Future<Map<String, dynamic>> loginWithGoogle({
    required String idToken,
    String? email,
    String? displayName,
    String? deviceLang,
    bool? acceptedTerms,
    String? termsVersion,
    String? privacyVersion,
    bool? notificationConsent,
    bool? aiTermsAccepted,
    String? aiTermsVersion,
  }) async {
    final Object? data = await (kIsWeb
        ? _bffAuthRequest
        : _request)('POST', kIsWeb ? 'google' : '/auth/google', body: {
      'id_token': idToken,
      if (email != null && email.isNotEmpty) 'email': email,
      if (displayName != null && displayName.isNotEmpty)
        'display_name': displayName,
      if (deviceLang != null && deviceLang.isNotEmpty)
        'device_lang': deviceLang,
      if (acceptedTerms != null) 'accepted_terms': acceptedTerms,
      if (termsVersion != null && termsVersion.isNotEmpty)
        'terms_version': termsVersion,
      if (privacyVersion != null && privacyVersion.isNotEmpty)
        'privacy_version': privacyVersion,
      if (notificationConsent != null)
        'notification_consent': notificationConsent,
      if (aiTermsAccepted != null) 'ai_terms_accepted': aiTermsAccepted,
      if (aiTermsVersion != null && aiTermsVersion.isNotEmpty)
        'ai_terms_version': aiTermsVersion,
    });
    return _requireJsonObject(data, responseName: 'Google login response');
  }

  /// Exchanges an Apple authorization code / identity token for Visionnaire JWTs.
  static Future<Map<String, dynamic>> loginWithApple({
    String? identityToken,
    required String authorizationCode,
    String? email,
    String? givenName,
    String? familyName,
    String? nonce,
    String? deviceLang,
    bool? acceptedTerms,
    String? termsVersion,
    String? privacyVersion,
    bool? notificationConsent,
    bool? aiTermsAccepted,
    String? aiTermsVersion,
  }) async {
    final Object? data = await (kIsWeb
        ? _bffAuthRequest
        : _request)('POST', kIsWeb ? 'apple' : '/auth/apple', body: {
      if (identityToken != null && identityToken.isNotEmpty)
        'identity_token': identityToken,
      'authorization_code': authorizationCode,
      if (email != null && email.isNotEmpty) 'email': email,
      if (givenName != null && givenName.isNotEmpty) 'given_name': givenName,
      if (familyName != null && familyName.isNotEmpty)
        'family_name': familyName,
      if (nonce != null && nonce.isNotEmpty) 'nonce': nonce,
      if (deviceLang != null && deviceLang.isNotEmpty)
        'device_lang': deviceLang,
      if (acceptedTerms != null) 'accepted_terms': acceptedTerms,
      if (termsVersion != null && termsVersion.isNotEmpty)
        'terms_version': termsVersion,
      if (privacyVersion != null && privacyVersion.isNotEmpty)
        'privacy_version': privacyVersion,
      if (notificationConsent != null)
        'notification_consent': notificationConsent,
      if (aiTermsAccepted != null) 'ai_terms_accepted': aiTermsAccepted,
      if (aiTermsVersion != null && aiTermsVersion.isNotEmpty)
        'ai_terms_version': aiTermsVersion,
    });
    return _requireJsonObject(data, responseName: 'Apple login response');
  }

  /// Lists social identities linked to the current authenticated account.
  static Future<List<AuthIdentity>> listAuthIdentities({
    required String token,
  }) async {
    final Map<String, dynamic> data = _requireJsonObject(
      await _get('/auth/identities', token),
      responseName: 'Identity list response',
    );
    final Object? rawItems = data['items'];
    if (rawItems is! List) {
      throw const FormatException('Identity list response is missing items');
    }

    final List<AuthIdentity> identities = <AuthIdentity>[];
    for (final Object? item in rawItems) {
      if (item is! Map) {
        throw const FormatException('Identity list contains a non-object item');
      }
      identities.add(AuthIdentity.fromJson(Map<String, dynamic>.from(item)));
    }
    return identities;
  }

  /// Links a verified Google identity to the current authenticated account.
  static Future<void> linkGoogleIdentity({
    required String idToken,
    String? email,
    String? displayName,
    required String token,
  }) async {
    await _post(
      '/auth/identities/google/link',
      <String, dynamic>{
        'id_token': idToken,
        if (email != null && email.isNotEmpty) 'email': email,
        if (displayName != null && displayName.isNotEmpty)
          'display_name': displayName,
      },
      token,
    );
  }

  /// Links a verified Apple identity to the current authenticated account.
  static Future<void> linkAppleIdentity({
    String? identityToken,
    required String authorizationCode,
    String? email,
    String? givenName,
    String? familyName,
    String? nonce,
    required String token,
  }) async {
    await _post(
      '/auth/identities/apple/link',
      <String, dynamic>{
        if (identityToken != null && identityToken.isNotEmpty)
          'identity_token': identityToken,
        'authorization_code': authorizationCode,
        if (email != null && email.isNotEmpty) 'email': email,
        if (givenName != null && givenName.isNotEmpty) 'given_name': givenName,
        if (familyName != null && familyName.isNotEmpty)
          'family_name': familyName,
        if (nonce != null && nonce.isNotEmpty) 'nonce': nonce,
      },
      token,
    );
  }

  /// Unlinks a social identity from the current authenticated account.
  static Future<void> unlinkAuthIdentity({
    required String identityId,
    required String token,
  }) async {
    await _request(
      'DELETE',
      '/auth/identities/${Uri.encodeComponent(identityId)}',
      token: token,
    );
  }

  /// Refreshes the access token using a refresh token.
  static Future<Map<String, dynamic>> refreshToken({
    String? refreshToken,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('The Web BFF refreshes tokens server-side.');
    }
    final Object? data = await _request('POST', '/refresh', body: {
      if (refreshToken != null && refreshToken.isNotEmpty)
        'refresh_token': refreshToken,
    });
    return _requireJsonObject(data, responseName: 'Token refresh response');
  }

  static Future<Map<String, dynamic>> getWebSession() async {
    final Object? data = await _bffAuthRequest('GET', 'session');
    return _requireJsonObject(data, responseName: 'BFF session response');
  }

  static Future<String> getWebCsrfToken() async {
    final Object? data = await _bffAuthRequest('GET', 'csrf');
    final Map<String, dynamic> response = _requireJsonObject(
      data,
      responseName: 'BFF CSRF response',
    );
    final Object? rawToken = response['csrf_token'];
    if (rawToken is! String || rawToken.trim().isEmpty) {
      throw const FormatException(
        'BFF CSRF response must contain a non-empty csrf_token.',
      );
    }
    return rawToken.trim();
  }

  /// Logs out the user and invalidates tokens.
  static Future<void> logout({
    String? accessToken,
    String? refreshToken,
  }) async {
    if (kIsWeb) {
      await _bffAuthRequest('POST', 'logout');
      return;
    }
    await _request('POST', '/logout', token: accessToken, body: {
      if (refreshToken != null && refreshToken.isNotEmpty)
        'refresh_token': refreshToken,
    });
  }

  /// Self-signup — no token required.
  ///
  /// Returns the created user map (UserRead from backend).
  static Future<Map<String, dynamic>> signupUser({
    required String username,
    required String password,
    required String familyName,
    required String givenName,
    String? middleName,
    required String email,
    String? mobileNumber,
    required String termsVersion,
    required String privacyVersion,
    required String aiTermsVersion,
    required bool acceptedTerms,
    required bool notificationConsent,
    required bool aiTermsAccepted,
  }) async =>
      (await _request('POST', '/signup', body: {
        'username': username,
        'password': password,
        'accepted_terms': acceptedTerms,
        'terms_version': termsVersion,
        'privacy_version': privacyVersion,
        'notification_consent': notificationConsent,
        'ai_terms_accepted': aiTermsAccepted,
        'ai_terms_version': aiTermsVersion,
        'profile': {
          'family_name': familyName,
          'given_name': givenName,
          if (middleName != null && middleName.isNotEmpty)
            'middle_name': middleName,
          'email': email,
          if (mobileNumber != null && mobileNumber.isNotEmpty)
            'mobile_number': mobileNumber,
        },
      })) as Map<String, dynamic>;

  /// Lists pending users waiting for admin approval (admin only).
  static Future<List<dynamic>> listPendingUsers({
    required String token,
  }) async =>
      (await _get('/list_pending_users', token)) as List<dynamic>;

  /// Approves a pending user sign-up (admin only).
  static Future<void> approvePendingUser({
    required int userId,
    required int groupId,
    required String token,
  }) async {
    await _put(
        '/approve_user_signup',
        {
          'user_id': userId,
          'group_id': groupId,
        },
        token);
  }

  /// Lists users visible to the authenticated account.
  ///
  /// The backend must scope this response by role/group. The frontend treats
  /// the returned collection as already authorized and only applies UX-level
  /// sorting or filtering.
  static Future<List<dynamic>> listUsers({required String token}) async =>
      (await _get('/list_users', token)) as List<dynamic>;

  /// Adds a new user.
  static Future<void> addUser({
    required String username,
    required String password,
    String role = 'user',
    int? groupId,
    Map<String, dynamic>? profile, // Optional user profile
    required String token,
  }) async {
    await _post(
        '/add_user',
        {
          'username': username,
          'password': password,
          'role': role,
          'group_id': groupId,
          if (profile != null) 'profile': profile,
        },
        token);
  }

  /// Updates a user's profile fields.
  static Future<void> updateUserProfile({
    required int userId,
    String? familyName,
    String? middleName,
    String? givenName,
    String? email,
    String? mobileNumber,
    required String token,
  }) async {
    await _put(
        '/update_user_profile',
        {
          'user_id': userId,
          if (familyName != null) 'family_name': familyName,
          if (middleName != null) 'middle_name': middleName,
          if (givenName != null) 'given_name': givenName,
          if (email != null) 'email': email,
          if (mobileNumber != null) 'mobile_number': mobileNumber,
        },
        token);
  }

  /// Deletes a user by ID.
  static Future<void> deleteUser({
    required int userId,
    required String token,
  }) async {
    await _delete('/delete_user', {'user_id': userId}, token);
  }

  /// Sets a user's status ('active' | 'inactive').
  static Future<void> setUserStatus({
    required int userId,
    required String status,
    required String token,
  }) async {
    await _put(
        '/set_user_status',
        {
          'user_id': userId,
          'status': status,
        },
        token);
  }

  /// Admin: updates a user's password by ID.
  static Future<void> adminUpdatePassword({
    required int userId,
    required String newPassword,
    required String token,
  }) async {
    await _put('/admin_update_password',
        {'user_id': userId, 'new_password': newPassword}, token);
  }

  /// Updates the current user's password.
  static Future<void> updateMyPassword({
    required String oldPassword,
    required String newPassword,
    required String token,
  }) async {
    await _put('/update_my_password',
        {'old_password': oldPassword, 'new_password': newPassword}, token);
  }

  /// Updates a user's role.
  static Future<void> updateUserRole({
    required int userId,
    required String newRole,
    required String token,
  }) async {
    await _put(
        '/update_user_role', {'user_id': userId, 'new_role': newRole}, token);
  }

  /// Updates a user's group.
  static Future<void> updateUserGroup({
    required int userId,
    required int newGroupId,
    required String token,
  }) async {
    await _put('/update_user_group',
        {'user_id': userId, 'new_group_id': newGroupId}, token);
  }

  /// Updates a user's username by ID.
  static Future<void> updateUsernameById({
    required int userId,
    required String newUsername,
    required String token,
  }) async {
    await _put(
        '/update_username_id',
        {
          'user_id': userId,
          'new_username': newUsername,
        },
        token);
  }

  /// Admin: updates a user's password by user ID.
  static Future<void> adminUpdatePasswordUserId({
    required int userId,
    required String newPassword,
    required String token,
  }) async {
    await _put('/admin_update_password_userid',
        {'user_id': userId, 'new_password': newPassword}, token);
  }

  /// Lists sites visible to the authenticated account.
  ///
  /// The backend must scope this response by role/group. The frontend treats
  /// the returned collection as already authorized.
  static Future<List<dynamic>> listSites({required String token}) async =>
      (await _get('/list_sites', token)) as List<dynamic>;

  /// Creates a new site.
  static Future<void> createSite({
    required String name,
    List<int>? groupIds,
    required String token,
  }) async {
    await _post(
      '/create_site',
      {
        'name': name,
        'group_ids': groupIds ?? <int>[],
      },
      token,
    );
  }

  /// Updates a site's name.
  static Future<void> updateSite({
    required int siteId,
    required String newName,
    required String token,
  }) async {
    await _put('/update_site', {'site_id': siteId, 'new_name': newName}, token);
  }

  /// Deletes a site by ID.
  static Future<void> deleteSite({
    required int siteId,
    required String token,
  }) async {
    await _delete('/delete_site', {'site_id': siteId}, token);
  }

  /// Adds a user to a site.
  static Future<void> addUserToSite({
    required int siteId,
    required int userId,
    required String token,
  }) async {
    await _post(
        '/add_user_to_site', {'site_id': siteId, 'user_id': userId}, token);
  }

  /// Removes a user from a site.
  static Future<void> removeUserFromSite({
    required int siteId,
    required int userId,
    required String token,
  }) async {
    await _post('/remove_user_from_site',
        {'site_id': siteId, 'user_id': userId}, token);
  }

  /// Adds a group to a site.
  static Future<void> addGroupToSite({
    required int siteId,
    required int groupId,
    required String token,
  }) async {
    await _post(
      '/add_group_to_site',
      {'site_id': siteId, 'group_id': groupId},
      token,
    );
  }

  /// Removes a group from a site.
  static Future<void> removeGroupFromSite({
    required int siteId,
    required int groupId,
    required String token,
  }) async {
    await _post(
      '/remove_group_from_site',
      {'site_id': siteId, 'group_id': groupId},
      token,
    );
  }

  /// Lists groups visible to the authenticated account.
  ///
  /// super_admin should receive all groups; scoped admins should receive only
  /// their manageable group data.
  static Future<List<dynamic>> listGroups({required String token}) async =>
      (await _get('/list_groups', token)) as List<dynamic>;

  /// Creates a new group.
  static Future<void> createGroup({
    required String name,
    required String uniformNumber,
    required String token,
  }) async {
    await _post(
        '/create_group',
        {
          'name': name,
          'uniform_number': uniformNumber,
        },
        token);
  }

  /// Updates a group's name or uniform number.
  static Future<void> updateGroup({
    required int groupId,
    String? newName,
    String? newUniformNumber,
    required String token,
  }) async {
    if (newName == null && newUniformNumber == null) {
      throw Exception('Nothing to update');
    }

    await _put(
        '/update_group',
        {
          'group_id': groupId,
          if (newName != null) 'new_name': newName,
          if (newUniformNumber != null) 'new_uniform_number': newUniformNumber,
        },
        token);
  }

  /// Deletes a group by ID.
  static Future<void> deleteGroup({
    required int groupId,
    required String token,
  }) async {
    await _delete('/delete_group', {'group_id': groupId}, token);
  }

  /// Lists all features.
  static Future<List<dynamic>> listFeatures({required String token}) async =>
      (await _get('/list_features', token)) as List<dynamic>;

  /// Lists all group features.
  static Future<List<dynamic>> listGroupFeatures(
          {required String token}) async =>
      (await _get('/list_group_features', token)) as List<dynamic>;

  /// Creates a new feature.
  static Future<void> createFeature({
    required String featureName,
    String? description,
    required String token,
  }) async {
    await _post(
        '/create_feature',
        {
          'feature_name': featureName,
          'description': description,
        },
        token);
  }

  /// Updates a feature's name or description.
  static Future<void> updateFeature({
    required int featureId,
    String? newName,
    String? newDescription,
    required String token,
  }) async {
    await _put(
        '/update_feature',
        {
          'feature_id': featureId,
          if (newName != null) 'new_name': newName,
          if (newDescription != null) 'new_description': newDescription,
        },
        token);
  }

  /// Deletes a feature by ID.
  static Future<void> deleteFeature({
    required int featureId,
    required String token,
  }) async {
    await _delete('/delete_feature', {'feature_id': featureId}, token);
  }

  /// Updates the features assigned to a group.
  static Future<void> updateGroupFeature({
    required int groupId,
    required List<int> featureIds,
    required String token,
  }) async {
    await _post('/update_group_feature',
        {'group_id': groupId, 'feature_ids': featureIds}, token);
  }

  /// Lists all stream configs for a site.
  static Future<List<dynamic>> listStreamConfigsOfSite({
    required int siteId,
    required String token,
  }) async =>
      (await _get('/list_stream_configs?site_id=$siteId', token))
          as List<dynamic>;

  /// Creates a new stream config.
  static Future<void> createStreamConfig({
    required Map<String, dynamic> body,
    required String token,
  }) async {
    await _post('/create_stream_config', body, token);
  }

  /// Updates a stream config by ID.
  static Future<void> updateStreamConfig({
    required int cfgId,
    required Map<String, dynamic> body,
    required String token,
  }) async {
    await _put('/stream_config/update/$cfgId', body, token);
  }

  /// Deletes a stream config by ID.
  static Future<void> deleteStreamConfig({
    required int cfgId,
    required String token,
  }) async {
    await _delete('/delete_stream_config/$cfgId', {}, token);
  }
}
