import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decode/jwt_decode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_user_snapshot.dart';
import '../models/native_session_envelope.dart';
import '../services/biometric_auth_service.dart';
import '../services/auth_request_headers.dart';
import '../services/auth_failure_policy.dart';
import '../services/auth_session_manager.dart';
import '../services/management_api_service.dart';
import '../services/deployment_profile_service.dart';
import '../services/push_registration_coordinator.dart';
import '../services/social_auth_service.dart';

class UnifiedAuthProvider extends ChangeNotifier {
  static const String _webBffRequestMarker = 'web-bff-session';
  static const String _nativeSessionStorageKey = 'auth_session_v6';
  /* ────────── 私有靜態 ────────── */
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /* ────────── Token ────────── */
  final AuthSessionManager _authSessionManager;
  late final PushRegistrationCoordinator _pushRegistration;

  String? get _accessToken => _authSessionManager.accessToken;
  String? get _refreshToken => _authSessionManager.refreshToken;
  Future<void>? _refreshFuture;
  int? _refreshGeneration;
  Timer? _sessionMaintenanceTimer;
  Future<void>? _sessionMaintenanceFuture;
  Future<void> _nativeSessionStorageMutation = Future<void>.value();
  int _credentialGeneration = 0;
  static const Duration _accessTokenRefreshLeeway = Duration(minutes: 2);
  static const int _sessionMaintenanceIntervalSeconds = int.fromEnvironment(
    'SESSION_MAINTENANCE_INTERVAL_SECONDS',
    defaultValue: 60,
  );

  /* ────────── 使用者資訊 ────────── */
  String? _username;
  String? _displayName;
  int? _userId;
  String? _role;
  int? _groupId;
  bool _isLoggedIn = false;
  bool _isInitialized = false;
  bool _biometricUnlockAvailable = false;
  bool _biometricUnlockEnabled = false;
  bool _biometricUnlockRequired = false;
  BiometricUnlockType? _biometricUnlockType;

  /* ────────── 功能權限 ────────── */
  /// e.g. ['doc_chat', 'yolo_api', 'file_manage']
  List<String> _features = [];
  final Set<String> _featureSet = <String>{};

  /* ────────── 帳號狀態 ────────── */
  /// 'active' | 'inactive' | 'pending' | 'pending_admin_approval'
  String? _status;

  /* ────────── Getters ────────── */
  bool get isLoggedIn => _isLoggedIn;
  bool get isInitialized => _isInitialized;
  bool get isBiometricUnlockAvailable => _biometricUnlockAvailable;
  bool get isBiometricUnlockEnabled => _biometricUnlockEnabled;
  bool get isBiometricUnlockRequired => _biometricUnlockRequired;
  BiometricUnlockType? get biometricUnlockType => _biometricUnlockType;
  bool get canUnlockWithBiometrics =>
      _biometricUnlockAvailable &&
      _biometricUnlockEnabled &&
      _biometricUnlockRequired &&
      _refreshToken != null &&
      !_isRefreshTokenExpired(_refreshToken!);
  String? get token => _accessToken;

  /// Compatibility credential for existing API call sites.
  ///
  /// Web requests authenticate through the BFF cookie and intentionally use
  /// an empty bearer credential. Native requests use the access token.
  String? get requestToken {
    if (kIsWeb) return _isLoggedIn ? _webBffRequestMarker : null;
    return _accessToken;
  }

  String? get username => _username;
  String? get displayName => _displayName;
  int? get userId => _userId;
  String? get role => _role;
  String get normalizedRole => _role?.trim().toLowerCase() ?? '';
  int? get groupId => _groupId;
  String? get status => _status;
  bool get isPending {
    final normalized = _status?.trim().toLowerCase();
    return normalized == 'pending' || normalized == 'pending_admin_approval';
  }

  bool get isSuperAdmin => normalizedRole == 'super_admin';

  bool get isAdmin => normalizedRole == 'admin' || isSuperAdmin;

  bool get canViewViolationAnalytics => isAdmin || isSuperAdmin;

  /// 直接查詢是否擁有某功能
  bool hasFeature(String name) => _featureSet.contains(name);

  void _setFeatures(Iterable<String> features) {
    _features = List<String>.from(features, growable: false);
    _featureSet
      ..clear()
      ..addAll(_features);
  }

  /// Each local credential transition owns one generation. Any asynchronous
  /// authentication operation that began under an older generation may finish
  /// its network request, but it must not write tokens, a secure-session
  /// record, or signed-in UI state after the local session is cleared.
  int _advanceCredentialGeneration() {
    _credentialGeneration += 1;
    return _credentialGeneration;
  }

  bool _isCredentialGenerationCurrent(int credentialGeneration) =>
      credentialGeneration == _credentialGeneration;

  /// Serializes secure-storage writes and deletion. In particular, a delayed
  /// refresh-session write cannot land after re-enrollment has queued its
  /// local-session deletion.
  Future<T> _withNativeSessionStorageMutation<T>(
    Future<T> Function() action,
  ) {
    final Future<T> operation = _nativeSessionStorageMutation.then<T>(
      (_) => action(),
    );
    _nativeSessionStorageMutation = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  /// 調試方法：檢查 token 狀態
  Map<String, dynamic> getTokenStatus() {
    return {
      'platform': kIsWeb ? 'web' : 'mobile',
      'hasAccessToken': _accessToken != null,
      'hasRefreshToken': _refreshToken != null,
      'accessTokenExpired':
          _accessToken != null ? _isTokenExpired(_accessToken!) : null,
      'refreshTokenExpired':
          _refreshToken != null ? _isRefreshTokenExpired(_refreshToken!) : null,
      'isLoggedIn': _isLoggedIn,
      'isInitialized': _isInitialized,
      'biometricUnlockAvailable': _biometricUnlockAvailable,
      'biometricUnlockEnabled': _biometricUnlockEnabled,
      'biometricUnlockRequired': _biometricUnlockRequired,
      'biometricUnlockType': _biometricUnlockType?.name,
      'username': _username,
      'displayName': _displayName,
      'role': _role,
      'features': _features,
      'storageStrategy': kIsWeb
          ? 'HttpOnly opaque BFF session cookie; no browser tokens'
          : 'SecureStorage only',
    };
  }

  UnifiedAuthProvider({
    AuthSessionManager? authSessionManager,
    PushRegistrationCoordinator? pushRegistration,
  }) : _authSessionManager = authSessionManager ?? AuthSessionManager.shared {
    _pushRegistration = pushRegistration ??
        (authSessionManager == null
            ? PushRegistrationCoordinator.shared
            : PushRegistrationCoordinator(
                authSessionManager: _authSessionManager,
              ));
    // 初始化時自動載入並嘗試刷新 token
    _initializeAndLoadTokens();
  }

  /* ────────── 初始化並讀取本地儲存 ────────── */
  Future<void> _initializeAndLoadTokens() async {
    final int credentialGeneration = _credentialGeneration;
    try {
      final BiometricUnlockType? biometricUnlockType =
          await BiometricAuthService.availableUnlockType();
      if (!_isCredentialGenerationCurrent(credentialGeneration)) return;

      _biometricUnlockType = biometricUnlockType;
      _biometricUnlockAvailable = _biometricUnlockType != null;
      _biometricUnlockEnabled = await BiometricAuthService.isEnabled();
      if (!_isCredentialGenerationCurrent(credentialGeneration)) return;

      await _loadTokens(credentialGeneration: credentialGeneration);
    } on MissingPluginException {
      if (!_isCredentialGenerationCurrent(credentialGeneration)) return;
      _resetSessionFields();
      _isLoggedIn = false;
      _isInitialized = true;
      notifyListeners();
    } on Exception catch (error, stackTrace) {
      if (!_isCredentialGenerationCurrent(credentialGeneration)) return;
      _debugAuthInitializationFailure(error, stackTrace);
      _resetSessionFields();
      _isLoggedIn = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  /* ────────── 讀取本地儲存 ────────── */
  Future<void> _loadTokens({required int credentialGeneration}) async {
    try {
      if (kIsWeb) {
        await _clearWebPersistedAuth();
        if (!_isCredentialGenerationCurrent(credentialGeneration)) return;
        try {
          // The BFF HttpOnly cookie is the only web session source of truth.
          await _loadWebSession();
          if (!_isCredentialGenerationCurrent(credentialGeneration)) return;
          _biometricUnlockRequired = false;
        } on Exception catch (error, stackTrace) {
          if (!_isCredentialGenerationCurrent(credentialGeneration)) return;
          _debugAuthInitializationFailure(error, stackTrace);
          await _clearTokens(
            notifyUI: false,
            expectedCredentialGeneration: credentialGeneration,
          );
          if (!_isCredentialGenerationCurrent(credentialGeneration)) return;
          _isLoggedIn = false;
          _biometricUnlockRequired = false;
        }
        if (!_isCredentialGenerationCurrent(credentialGeneration)) return;
        _updateSessionMaintenance();
        _isInitialized = true;
        notifyListeners();
        return;
      }

      await _loadNativeSessionEnvelope(
        expectedCredentialGeneration: credentialGeneration,
      );
      if (!_isCredentialGenerationCurrent(credentialGeneration)) return;

      final bool hasValidRefreshToken =
          _refreshToken != null && !_isRefreshTokenExpired(_refreshToken!);

      if (_biometricUnlockEnabled && hasValidRefreshToken) {
        _biometricUnlockRequired = true;
        _isLoggedIn = false;
      } else if (hasValidRefreshToken) {
        try {
          final bool refreshed = await _performTokenRefresh(
            notifyUI: false,
            expectedCredentialGeneration: credentialGeneration,
          );
          if (!_isCredentialGenerationCurrent(credentialGeneration) ||
              !refreshed) {
            return;
          }
          _isLoggedIn = true;
        } on Exception catch (error, stackTrace) {
          if (!_isCredentialGenerationCurrent(credentialGeneration)) return;
          _debugAuthInitializationFailure(error, stackTrace);
          if (AuthFailurePolicy.isTerminalRefreshFailure(error)) {
            await _clearTokens(
              notifyUI: false,
              expectedCredentialGeneration: credentialGeneration,
            );
            if (!_isCredentialGenerationCurrent(credentialGeneration)) return;
          }
          _isLoggedIn = false;
        }
      } else {
        if (_accessToken != null || _refreshToken != null) {
          await _clearTokens(
            notifyUI: false,
            expectedCredentialGeneration: credentialGeneration,
          );
          if (!_isCredentialGenerationCurrent(credentialGeneration)) return;
        }
        _isLoggedIn = false;
        _biometricUnlockRequired = false;
      }
    } on Exception catch (error, stackTrace) {
      if (!_isCredentialGenerationCurrent(credentialGeneration)) return;
      _debugAuthInitializationFailure(error, stackTrace);
      _resetSessionFields();
      _isLoggedIn = false;
    }
    if (!_isCredentialGenerationCurrent(credentialGeneration)) return;
    _updateSessionMaintenance();
    // 初始化完成後只通知一次 UI
    _isInitialized = true;
    notifyListeners();
  }

  /* ────────── 登入 ────────── */
  Future<void> login(
    String username,
    String password, {
    String? hcaptchaToken,
    bool enableBiometricUnlock = false,
  }) async {
    final int credentialGeneration = _advanceCredentialGeneration();
    final resp = await ManagementAPIService.login(
      username: username,
      password: password,
      hcaptchaToken: hcaptchaToken,
    );
    if (!_isCredentialGenerationCurrent(credentialGeneration)) return;

    await _completeLoginFromResponse(
      resp,
      enableBiometricUnlock: enableBiometricUnlock,
      expectedCredentialGeneration: credentialGeneration,
    );
  }

  Future<void> loginWithSocialCredential(
    SocialAuthCredential credential, {
    String deviceLang = 'en',
    bool enableBiometricUnlock = false,
    bool? acceptedTerms,
    String? termsVersion,
    String? privacyVersion,
    bool? notificationConsent,
    bool? aiTermsAccepted,
    String? aiTermsVersion,
  }) async {
    final int credentialGeneration = _advanceCredentialGeneration();
    final Map<String, dynamic> resp;
    switch (credential) {
      case GoogleSocialAuthCredential credential:
        resp = await ManagementAPIService.loginWithGoogle(
          idToken: credential.idToken,
          email: credential.email,
          displayName: credential.displayName,
          deviceLang: deviceLang,
          acceptedTerms: acceptedTerms,
          termsVersion: termsVersion,
          privacyVersion: privacyVersion,
          notificationConsent: notificationConsent,
          aiTermsAccepted: aiTermsAccepted,
          aiTermsVersion: aiTermsVersion,
        );
      case AppleSocialAuthCredential credential:
        resp = await ManagementAPIService.loginWithApple(
          identityToken: credential.identityToken,
          authorizationCode: credential.authorizationCode,
          email: credential.email,
          givenName: credential.givenName,
          familyName: credential.familyName,
          nonce: credential.nonce,
          deviceLang: deviceLang,
          acceptedTerms: acceptedTerms,
          termsVersion: termsVersion,
          privacyVersion: privacyVersion,
          notificationConsent: notificationConsent,
          aiTermsAccepted: aiTermsAccepted,
          aiTermsVersion: aiTermsVersion,
        );
    }

    if (!_isCredentialGenerationCurrent(credentialGeneration)) return;
    await _completeLoginFromResponse(
      resp,
      enableBiometricUnlock: enableBiometricUnlock,
      expectedCredentialGeneration: credentialGeneration,
    );
  }

  Future<void> _completeLoginFromResponse(
    Map<String, dynamic> resp, {
    required bool enableBiometricUnlock,
    required int expectedCredentialGeneration,
  }) async {
    if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) return;

    if (kIsWeb) {
      await _applyWebSessionResponse(resp);
      if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) return;
      _biometricUnlockRequired = false;
      _isInitialized = true;
      _updateSessionMaintenance();
      notifyListeners();
      await _registerPushDeviceQuietly(
        expectedCredentialGeneration: expectedCredentialGeneration,
      );
      return;
    }

    final NativeTokenPair tokens = _nativeTokenPairFromResponse(
      resp,
      operation: 'login',
    );
    final AuthUserSnapshot user = AuthUserSnapshot.fromNativeTokenResponse(
      Map<String, Object?>.from(resp),
    );

    _authSessionManager.replaceTokens(tokens);
    _applyUserSnapshot(user);
    _biometricUnlockRequired = false;

    /* 寫入本地 secure storage。Web 不保存認證資料，僅保留記憶體狀態。 */
    final bool persisted = await _persistNativeSession(
      expectedCredentialGeneration: expectedCredentialGeneration,
    );
    if (!persisted ||
        !_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
      return;
    }

    if (enableBiometricUnlock && _biometricUnlockAvailable) {
      await BiometricAuthService.setEnabled(true);
      if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
        await BiometricAuthService.setEnabled(false);
        return;
      }
      _biometricUnlockEnabled = true;
    }

    _isLoggedIn = true;
    _isInitialized = true;
    _updateSessionMaintenance();
    notifyListeners();
    await _registerPushDeviceQuietly(
      expectedCredentialGeneration: expectedCredentialGeneration,
    );
  }

  Future<bool> unlockWithBiometrics({
    required String reason,
  }) async {
    if (!canUnlockWithBiometrics) return false;
    final int credentialGeneration = _credentialGeneration;

    final bool authenticated = await BiometricAuthService.authenticate(
      reason: reason,
    );
    if (!authenticated ||
        !_isCredentialGenerationCurrent(credentialGeneration)) {
      return false;
    }

    try {
      if (_accessToken == null || _shouldRefreshAccessToken(_accessToken!)) {
        final bool refreshed = await _performTokenRefresh(
          notifyUI: false,
          expectedCredentialGeneration: credentialGeneration,
        );
        if (!refreshed ||
            !_isCredentialGenerationCurrent(credentialGeneration)) {
          return false;
        }
      }

      if (!_isCredentialGenerationCurrent(credentialGeneration) ||
          _accessToken == null ||
          _isTokenExpired(_accessToken!)) {
        return false;
      }

      _biometricUnlockRequired = false;
      _isLoggedIn = true;
      _isInitialized = true;
      _updateSessionMaintenance();
      notifyListeners();

      await _registerPushDeviceQuietly(
        expectedCredentialGeneration: credentialGeneration,
      );
      return true;
    } on Exception catch (error, stackTrace) {
      _debugAuthInitializationFailure(error, stackTrace);
      return false;
    }
  }

  Future<bool> setBiometricUnlockEnabled(
    bool enabled, {
    required String reason,
  }) async {
    final int credentialGeneration = _credentialGeneration;
    if (!enabled) {
      await BiometricAuthService.setEnabled(false);
      if (!_isCredentialGenerationCurrent(credentialGeneration)) return false;
      _biometricUnlockEnabled = false;
      _biometricUnlockRequired = false;
      notifyListeners();
      return true;
    }

    _biometricUnlockType = await BiometricAuthService.availableUnlockType();
    if (!_isCredentialGenerationCurrent(credentialGeneration)) return false;
    _biometricUnlockAvailable = _biometricUnlockType != null;
    if (!_biometricUnlockAvailable || _refreshToken == null) return false;

    final bool authenticated = await BiometricAuthService.authenticate(
      reason: reason,
    );
    if (!authenticated ||
        !_isCredentialGenerationCurrent(credentialGeneration)) {
      return false;
    }

    await BiometricAuthService.setEnabled(true);
    if (!_isCredentialGenerationCurrent(credentialGeneration)) {
      await BiometricAuthService.setEnabled(false);
      return false;
    }
    _biometricUnlockEnabled = true;
    _biometricUnlockRequired = false;
    notifyListeners();
    return true;
  }

  /* ────────── 登出 ────────── */
  Future<void> logout({bool localOnly = false}) {
    final int credentialGeneration = _advanceCredentialGeneration();
    return _logout(
      localOnly: localOnly,
      expectedCredentialGeneration: credentialGeneration,
    );
  }

  Future<void> _logout({
    required bool localOnly,
    required int expectedCredentialGeneration,
  }) async {
    if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) return;

    if (kIsWeb) {
      if (!localOnly) {
        await _unregisterPushDeviceQuietly();
        if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
          return;
        }
        try {
          await ManagementAPIService.logout();
        } on Exception catch (error, stackTrace) {
          _debugAuthLogoutFailure(error, stackTrace);
        }
        if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
          return;
        }
      }
      await _clearTokens(
        notifyUI: true,
        expectedCredentialGeneration: expectedCredentialGeneration,
      );
      return;
    }

    if (!localOnly && _canPreserveBiometricSession) {
      await _unregisterPushDeviceQuietly();
      if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
        return;
      }
      await _lockForBiometricUnlock(
        expectedCredentialGeneration: expectedCredentialGeneration,
      );
      return;
    }

    final String? accessToken = _accessToken;
    final String? refreshToken = _refreshToken;
    if (!localOnly && accessToken != null && refreshToken != null) {
      // Unregister first because logout may immediately invalidate the access
      // token needed by the FCM endpoint.
      await _unregisterPushDeviceQuietly();
      if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
        return;
      }
      try {
        await ManagementAPIService.logout(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );
      } on Exception catch (error, stackTrace) {
        _debugAuthLogoutFailure(error, stackTrace);
      }
      if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
        return;
      }
    }

    // 使用統一的清理方法，登出時需要通知 UI
    await BiometricAuthService.setEnabled(false);
    if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
      return;
    }
    _biometricUnlockEnabled = false;
    _biometricUnlockRequired = false;
    await _clearTokens(
      notifyUI: true,
      expectedCredentialGeneration: expectedCredentialGeneration,
    );
  }

  /// Clears this native installation's local authentication before its
  /// enrolled deployment is deliberately replaced.
  ///
  /// This differs from normal sign-out in two important ways: biometric
  /// unlock is never preserved, and no request is sent to the previous API
  /// origin. The caller must subsequently clear the deployment selection and
  /// require a new activation code before allowing another sign-in.
  Future<void> clearLocalSessionForDeploymentChange() async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Web deployments are fixed to their same-origin BFF.',
      );
    }

    // Invalidate before awaiting push teardown. A refresh/login response from
    // the previous deployment must never be committed while reactivation is
    // being prepared.
    final int credentialGeneration = _advanceCredentialGeneration();
    await _pushRegistration.suspendForDeploymentChange();
    if (!_isCredentialGenerationCurrent(credentialGeneration)) return;
    await _logout(
      localOnly: true,
      expectedCredentialGeneration: credentialGeneration,
    );
  }

  Future<void> _unregisterPushDeviceQuietly() async {
    try {
      await _pushRegistration.onSigningOut();
    } on Exception catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[PushRegistration] sign-out removal failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  Future<void> _registerPushDeviceQuietly({
    int? expectedCredentialGeneration,
  }) async {
    if (expectedCredentialGeneration != null &&
        !_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
      return;
    }
    try {
      await _pushRegistration.onSignedIn();
    } on Exception catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[PushRegistration] sign-in registration failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  bool get _canPreserveBiometricSession =>
      _biometricUnlockAvailable &&
      _biometricUnlockEnabled &&
      _refreshToken != null &&
      !_isRefreshTokenExpired(_refreshToken!);

  Future<void> _lockForBiometricUnlock({
    bool notifyUI = true,
    int? expectedCredentialGeneration,
  }) async {
    if (expectedCredentialGeneration != null &&
        !_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
      return;
    }
    _stopSessionMaintenance();
    _authSessionManager.lockAccessToken();
    _isLoggedIn = false;
    _isInitialized = true;
    _biometricUnlockRequired = true;
    final bool persisted = await _persistNativeSession(
      expectedCredentialGeneration: expectedCredentialGeneration,
    );
    if (!persisted ||
        (expectedCredentialGeneration != null &&
            !_isCredentialGenerationCurrent(expectedCredentialGeneration))) {
      return;
    }

    if (notifyUI) {
      notifyListeners();
    }
  }

  /* ────────── 刷新 access-token ────────── */
  Future<void> refreshIfNeeded({bool force = false}) async {
    if (kIsWeb) {
      if (!force) return;
      await _revalidateWebSession();
      return;
    }

    final int credentialGeneration = _credentialGeneration;
    final activeRefresh = _refreshFuture;
    if (activeRefresh != null && _refreshGeneration == credentialGeneration) {
      await activeRefresh;
      return;
    }

    // 1) 還沒登入、或 access token 尚未接近過期 → 不做事
    if (!force &&
        (_accessToken == null || !_shouldRefreshAccessToken(_accessToken!))) {
      return;
    }

    final refreshFuture = _refreshIfNeeded(
      force: force,
      expectedCredentialGeneration: credentialGeneration,
    );
    _refreshFuture = refreshFuture;
    _refreshGeneration = credentialGeneration;
    try {
      await refreshFuture;
    } finally {
      if (identical(_refreshFuture, refreshFuture)) {
        _refreshFuture = null;
        _refreshGeneration = null;
      }
    }
  }

  Future<bool> ensureWebSessionActive() async {
    if (!kIsWeb) return _isLoggedIn;

    try {
      await _loadWebSession();
      _isInitialized = true;
      _updateSessionMaintenance();
      notifyListeners();
      return true;
    } on ManagementApiException catch (error) {
      if (error.statusCode == 401) {
        await _clearTokens(notifyUI: true);
        return false;
      }
      rethrow;
    }
  }

  Future<void> _refreshIfNeeded({
    required bool force,
    required int expectedCredentialGeneration,
  }) async {
    if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) return;
    if (!force &&
        (_accessToken == null || !_shouldRefreshAccessToken(_accessToken!))) {
      return;
    }

    // 2) Access token 過期或伺服器回 401，嘗試用 refresh session 刷新。
    // Web 使用 HttpOnly cookie；mobile 使用 secure storage refresh token。
    if (_canRefreshSession) {
      try {
        // 靜默刷新 token，不通知 UI（避免不必要的跳轉）
        final bool refreshed = await _performTokenRefresh(
          notifyUI: false,
          expectedCredentialGeneration: expectedCredentialGeneration,
        );
        if (!refreshed ||
            !_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
          return;
        }
        _isLoggedIn = true;
      } catch (error) {
        if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
          return;
        }
        if (AuthFailurePolicy.isTerminalRefreshFailure(error)) {
          await logout(localOnly: true);
          return;
        }
        rethrow;
      }
    } else {
      // Refresh token 也過期了，強制登出
      // 登出時需要通知 UI，因為這會改變登入狀態
      await logout(localOnly: true);
    }
  }

  /* ────────── 內部方法：執行 token 刷新 ────────── */
  Future<bool> _performTokenRefresh({
    bool notifyUI = true,
    int? expectedCredentialGeneration,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('The Web BFF refreshes tokens server-side.');
    }
    final int credentialGeneration =
        expectedCredentialGeneration ?? _credentialGeneration;
    if (!_isCredentialGenerationCurrent(credentialGeneration)) return false;

    final String? refreshToken = _refreshToken;
    final resp = await ManagementAPIService.refreshToken(
      refreshToken: refreshToken,
    );
    if (!_isCredentialGenerationCurrent(credentialGeneration)) return false;

    final NativeTokenPair tokens = _nativeTokenPairFromResponse(
      resp,
      operation: 'refresh',
    );
    _authSessionManager.replaceTokens(tokens);

    // 更新本地存檔
    final bool persisted = await _persistNativeSession(
      expectedCredentialGeneration: credentialGeneration,
    );
    if (!persisted || !_isCredentialGenerationCurrent(credentialGeneration)) {
      return false;
    }
    // 只有在需要時才通知 UI
    if (notifyUI) {
      notifyListeners();
    }
    return true;
  }

  /* ────────── utils ────────── */
  bool _isTokenExpired(String tk) {
    try {
      return Jwt.isExpired(tk);
    } on Exception {
      return true;
    }
  }

  bool _shouldRefreshAccessToken(String tk) {
    try {
      final expiryDate = Jwt.getExpiryDate(tk);
      if (expiryDate == null) return true;
      return DateTime.now().add(_accessTokenRefreshLeeway).isAfter(expiryDate);
    } on Exception {
      return true;
    }
  }

  bool get _canRefreshSession {
    if (kIsWeb) return true;
    return _refreshToken != null && !_isRefreshTokenExpired(_refreshToken!);
  }

  /// 檢查 refresh token 是否過期
  /// Refresh token 可能是 JWT，也可能是後端發的不透明字串。
  /// 若能解 JWT 就在前端先擋掉明確過期的 token；若不能解，就交給
  /// refresh endpoint 判斷，避免有效的不透明 refresh token 被誤清除。
  bool _isRefreshTokenExpired(String refreshToken) {
    try {
      return Jwt.isExpired(refreshToken);
    } on Exception {
      return false;
    }
  }

  NativeTokenPair _nativeTokenPairFromResponse(
    Map<String, dynamic> response, {
    required String operation,
  }) {
    final Object? accessToken = response['access_token'];
    final Object? refreshToken = response['refresh_token'];
    if (accessToken is! String ||
        accessToken.trim().isEmpty ||
        refreshToken is! String ||
        refreshToken.trim().isEmpty) {
      throw FormatException(
        'Native $operation must return access and rotated refresh tokens.',
      );
    }
    return NativeTokenPair(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  void _applyUserSnapshot(AuthUserSnapshot user) {
    _username = user.username;
    _displayName = user.displayName;
    _role = user.role;
    _groupId = user.groupId;
    _userId = user.userId;
    _status = user.status;
    _setFeatures(user.features);
  }

  /// 清除所有 token 和使用者資訊
  Future<void> _clearTokens({
    bool notifyUI = true,
    int? expectedCredentialGeneration,
  }) async {
    if (expectedCredentialGeneration != null &&
        !_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
      return;
    }
    _stopSessionMaintenance();
    _resetSessionFields();
    _isLoggedIn = false;
    _isInitialized = true;

    // 清除本地存儲（多重清除策略）
    await _clearAllStorages(
      expectedCredentialGeneration: expectedCredentialGeneration,
    );
    if (expectedCredentialGeneration != null &&
        !_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
      return;
    }
    if (kIsWeb) {
      AuthRequestHeaders.clearWebSession();
    }

    // 只有在需要時才通知 UI
    if (notifyUI) {
      notifyListeners();
    }
  }

  /* ────────── Web 特定的存儲方法 ────────── */

  void _resetSessionFields() {
    _authSessionManager.clearTokens();
    _username = null;
    _displayName = null;
    _role = null;
    _userId = null;
    _groupId = null;
    _setFeatures(const <String>[]);
    _status = null;
  }

  Future<void> _loadNativeSessionEnvelope({
    required int expectedCredentialGeneration,
  }) async {
    if (kIsWeb ||
        !_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
      return;
    }
    final deploymentProfile =
        await DeploymentProfileService.shared.initialize();
    if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) return;
    final String? raw = await _storage.read(key: _nativeSessionStorageKey);
    if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) return;
    await _withNativeSessionStorageMutation<void>(() async {
      if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
        return;
      }
      await Future.wait(
        _retiredNativeSessionKeys.map((key) => _storage.delete(key: key)),
      );
    });
    if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) return;
    if (raw == null) return;

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('Stored native session must be an object.');
      }
      final NativeSessionEnvelope session = NativeSessionEnvelope.fromJson(
        Map<String, Object?>.from(decoded),
      );
      if (!session.matches(deploymentProfile)) {
        throw const FormatException(
          'Stored native session belongs to a different deployment.',
        );
      }
      _authSessionManager.restoreRefreshToken(session.refreshToken);
      _applyUserSnapshot(session.user);
    } on FormatException {
      if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) return;
      await _withNativeSessionStorageMutation<void>(() async {
        if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
          return;
        }
        await _storage.delete(key: _nativeSessionStorageKey);
      });
      if (!_isCredentialGenerationCurrent(expectedCredentialGeneration)) return;
      _resetSessionFields();
    }
  }

  Future<bool> _persistNativeSession({
    int? expectedCredentialGeneration,
  }) async {
    final int credentialGeneration =
        expectedCredentialGeneration ?? _credentialGeneration;
    if (kIsWeb) return true;
    if (!_isCredentialGenerationCurrent(credentialGeneration)) return false;

    final deploymentProfile =
        await DeploymentProfileService.shared.initialize();
    if (!_isCredentialGenerationCurrent(credentialGeneration)) return false;
    final String? refreshToken = _refreshToken;
    final String? username = _username;
    final String? role = _role;
    if (refreshToken == null || username == null || role == null) {
      throw StateError('Cannot persist an incomplete native session.');
    }
    final AuthUserSnapshot user = AuthUserSnapshot(
      username: username,
      role: role,
      features: List<String>.unmodifiable(_features),
      displayName: _displayName,
      userId: _userId,
      groupId: _groupId,
      status: _status,
    );
    final NativeSessionEnvelope session = NativeSessionEnvelope.create(
      user: user,
      refreshToken: refreshToken,
      deploymentProfile: deploymentProfile,
    );
    final String serializedSession = jsonEncode(session.toJson());
    return _withNativeSessionStorageMutation<bool>(() async {
      if (!_isCredentialGenerationCurrent(credentialGeneration)) return false;
      await _storage.write(
        key: _nativeSessionStorageKey,
        value: serializedSession,
      );
      if (!_isCredentialGenerationCurrent(credentialGeneration)) return false;
      await Future.wait(
        <Future<void>>[
          ..._retiredNativeSessionKeys.map((key) => _storage.delete(key: key)),
          ..._legacyNativeAuthKeys.map((key) => _storage.delete(key: key)),
        ],
      );
      return _isCredentialGenerationCurrent(credentialGeneration);
    });
  }

  Future<void> _loadWebSession() async {
    final Map<String, dynamic> payload =
        await ManagementAPIService.getWebSession();
    await _applyWebSessionResponse(payload);
  }

  Future<void> _applyWebSessionResponse(
    Map<String, dynamic> payload,
  ) async {
    final Object? authenticated = payload['authenticated'];
    if (authenticated != null && authenticated is! bool) {
      throw const FormatException(
        'BFF session response authenticated must be a boolean.',
      );
    }
    if (authenticated == false) {
      throw const ManagementApiException(
        statusCode: 401,
        message: 'No active BFF session',
      );
    }
    final AuthUserSnapshot user = AuthUserSnapshot.fromBffSessionResponse(
      Map<String, Object?>.from(payload),
      responseName: 'BFF session response',
    );
    final String csrfToken = await ManagementAPIService.getWebCsrfToken();

    _authSessionManager.clearTokens();
    _applyUserSnapshot(user);
    _isLoggedIn = true;
    AuthRequestHeaders.setCsrfToken(csrfToken);
  }

  Future<void> _revalidateWebSession() async {
    try {
      await _loadWebSession();
      _isInitialized = true;
      _updateSessionMaintenance();
      notifyListeners();
    } on ManagementApiException catch (error) {
      if (error.statusCode == 401) {
        await _clearTokens(notifyUI: true);
      }
      rethrow;
    }
  }

  void _updateSessionMaintenance() {
    if (!_isLoggedIn || _biometricUnlockRequired) {
      _stopSessionMaintenance();
      return;
    }
    if (_sessionMaintenanceTimer != null) return;

    _sessionMaintenanceTimer = Timer.periodic(
      Duration(seconds: _sessionMaintenanceIntervalSeconds),
      (_) => unawaited(_maintainSession()),
    );
  }

  void _stopSessionMaintenance() {
    _sessionMaintenanceTimer?.cancel();
    _sessionMaintenanceTimer = null;
    _sessionMaintenanceFuture = null;
  }

  Future<void> _maintainSession() async {
    if (!_isLoggedIn || _biometricUnlockRequired) return;
    if (_sessionMaintenanceFuture != null) return;

    final maintenance = _maintainSessionOnce();
    _sessionMaintenanceFuture = maintenance;
    try {
      await maintenance;
    } finally {
      if (identical(_sessionMaintenanceFuture, maintenance)) {
        _sessionMaintenanceFuture = null;
      }
    }
  }

  Future<void> _maintainSessionOnce() async {
    try {
      if (kIsWeb) {
        // The BFF owns the refresh token and can extend its HttpOnly session.
        await _revalidateWebSession();
      } else {
        // This only rotates when the access token is within the refresh leeway.
        await refreshIfNeeded();
      }
    } catch (error) {
      // A 401 has already cleared local state. Network failures should not
      // log the user out while a later retry can still recover the session.
      debugPrint('Session maintenance failed: $error');
    }
  }

  @override
  void dispose() {
    _advanceCredentialGeneration();
    _stopSessionMaintenance();
    super.dispose();
  }

  /// 清除所有存儲
  Future<void> _clearAllStorages({
    int? expectedCredentialGeneration,
  }) async {
    if (kIsWeb) {
      await _clearWebPersistedAuth();
    } else {
      await _withNativeSessionStorageMutation<void>(() async {
        if (expectedCredentialGeneration != null &&
            !_isCredentialGenerationCurrent(expectedCredentialGeneration)) {
          return;
        }
        await Future.wait(<Future<void>>[
          _storage.delete(key: _nativeSessionStorageKey),
          ..._retiredNativeSessionKeys.map((key) => _storage.delete(key: key)),
          ..._legacyNativeAuthKeys.map((key) => _storage.delete(key: key)),
        ]);
      });
    }
  }

  /// Removes credentials written by older web versions. This is cleanup only;
  /// the current app never saves JWTs to SharedPreferences.
  Future<void> _clearWebPreferences() async {
    if (!kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();

    final keys = [
      'secure_access_token',
      'secure_refresh_token',
      'secure_username',
      'secure_display_name',
      'secure_role',
      'secure_group_id',
      'secure_user_id',
      'secure_features',
      'secure_status',
    ];

    await Future.wait(keys.map(prefs.remove));
  }

  Future<void> _clearWebSecureStorage() => Future.wait(
        _webAuthStorageKeys.map((String key) => _storage.delete(key: key)),
      );

  Future<void> _clearWebPersistedAuth() async {
    await _clearWebPreferences();
    await _clearWebSecureStorage();
  }

  static const List<String> _webAuthStorageKeys = <String>[
    _nativeSessionStorageKey,
    ..._retiredNativeSessionKeys,
    'access_token',
    'refresh_token',
    'username',
    'display_name',
    'role',
    'group_id',
    'user_id',
    'features',
    'status',
  ];

  static const List<String> _legacyNativeAuthKeys = <String>[
    'access_token',
    'refresh_token',
    'username',
    'display_name',
    'role',
    'group_id',
    'user_id',
    'features',
    'status',
  ];

  static const List<String> _retiredNativeSessionKeys = <String>[
    'auth_session_v5',
    'auth_session_v4',
    'auth_session_v3',
    'auth_session_v2',
  ];

  void _debugAuthInitializationFailure(
    Object error,
    StackTrace stackTrace,
  ) {
    if (!kDebugMode) return;
    debugPrint(
        '[UnifiedAuthProvider] authentication initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  void _debugAuthLogoutFailure(Object error, StackTrace stackTrace) {
    if (!kDebugMode) return;
    debugPrint('[UnifiedAuthProvider] remote logout failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
