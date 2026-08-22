import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../config/social_auth_config.dart';

enum SocialAuthProviderType {
  google,
  apple,
}

sealed class SocialAuthCredential {
  const SocialAuthCredential();

  SocialAuthProviderType get provider;

  String get providerName => switch (provider) {
        SocialAuthProviderType.google => 'google',
        SocialAuthProviderType.apple => 'apple',
      };
}

final class GoogleSocialAuthCredential extends SocialAuthCredential {
  GoogleSocialAuthCredential({
    required String idToken,
    this.email,
    this.displayName,
  }) : idToken = _requiredCredential(idToken, field: 'Google ID token');

  final String idToken;
  final String? email;
  final String? displayName;

  @override
  SocialAuthProviderType get provider => SocialAuthProviderType.google;
}

final class AppleSocialAuthCredential extends SocialAuthCredential {
  AppleSocialAuthCredential({
    required String authorizationCode,
    this.identityToken,
    this.email,
    this.givenName,
    this.familyName,
    this.nonce,
  }) : authorizationCode = _requiredCredential(
          authorizationCode,
          field: 'Apple authorization code',
        );

  final String authorizationCode;
  final String? identityToken;
  final String? email;
  final String? givenName;
  final String? familyName;
  final String? nonce;

  @override
  SocialAuthProviderType get provider => SocialAuthProviderType.apple;
}

String _requiredCredential(String value, {required String field}) {
  final String normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, field, 'Credential must not be empty.');
  }
  return normalized;
}

class SocialAuthUnavailableException implements Exception {
  const SocialAuthUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SocialAuthService {
  SocialAuthService._();

  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static final StreamController<SocialAuthCredential> _googleWebController =
      StreamController<SocialAuthCredential>.broadcast();

  static Future<void>? _googleInitFuture;
  static StreamSubscription<GoogleSignInAuthenticationEvent>?
      _googleWebEventSubscription;

  static Stream<SocialAuthCredential> get googleWebCredentials =>
      _googleWebController.stream;

  static bool get shouldRenderGoogleWebButton =>
      kIsWeb &&
      SocialAuthConfig.googleEnabled &&
      SocialAuthConfig.googleWebClientIdOrNull != null;

  static bool get shouldRenderGoogleNativeButton =>
      !kIsWeb &&
      SocialAuthConfig.googleEnabled &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get shouldOfferAppleSignIn {
    if (!SocialAuthConfig.appleEnabled) return false;
    if (kIsWeb) return _isSecureWebOrigin && _hasAppleWebAuthenticationConfig;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return true;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _hasAppleWebAuthenticationConfig;
    }
    return false;
  }

  static bool get _isSecureWebOrigin {
    if (!kIsWeb) return true;
    final uri = Uri.base;
    return uri.scheme == 'https' ||
        uri.host == 'localhost' ||
        uri.host == '127.0.0.1';
  }

  static bool get _hasAppleWebAuthenticationConfig =>
      SocialAuthConfig.appleServiceId.trim().isNotEmpty &&
      _appleRedirectUriForCurrentPlatform() != null;

  static Future<void> initializeGoogle() {
    final existing = _googleInitFuture;
    if (existing != null) return existing;

    _googleInitFuture = _googleSignIn
        .initialize(
      clientId: _googleClientIdForCurrentPlatform(),
      serverClientId:
          kIsWeb ? null : SocialAuthConfig.googleServerClientIdOrNull,
    )
        .then((_) {
      if (!kIsWeb || _googleWebEventSubscription != null) return;
      _googleWebEventSubscription =
          _googleSignIn.authenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          final credential = _googleCredentialFromAccount(event.user);
          if (credential != null) {
            _googleWebController.add(credential);
          }
        }
      }, onError: _googleWebController.addError);
    });

    return _googleInitFuture!;
  }

  static String? _googleClientIdForCurrentPlatform() {
    if (kIsWeb) return SocialAuthConfig.googleWebClientIdOrNull;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return SocialAuthConfig.googleIosClientIdOrNull;
    }
    return null;
  }

  static Future<SocialAuthCredential> signInWithGoogle() async {
    if (!SocialAuthConfig.googleEnabled) {
      throw const SocialAuthUnavailableException('Google sign-in is disabled.');
    }
    if (kIsWeb && SocialAuthConfig.googleWebClientIdOrNull == null) {
      throw const SocialAuthUnavailableException(
        'Google Web sign-in requires --dart-define=GOOGLE_WEB_CLIENT_ID=your-web-client-id.apps.googleusercontent.com.',
      );
    }
    await initializeGoogle();

    if (!_googleSignIn.supportsAuthenticate()) {
      throw const SocialAuthUnavailableException(
        'Google Web sign-in requires the official Google button. Check GOOGLE_WEB_CLIENT_ID and rebuild the web app.',
      );
    }

    final account = await _googleSignIn.authenticate();
    final credential = _googleCredentialFromAccount(account);
    if (credential == null) {
      throw const SocialAuthUnavailableException(
        'Google did not return an ID token.',
      );
    }
    return credential;
  }

  static SocialAuthCredential? _googleCredentialFromAccount(
    GoogleSignInAccount account,
  ) {
    final String? idToken = account.authentication.idToken;
    if (idToken == null || idToken.trim().isEmpty) return null;
    return GoogleSocialAuthCredential(
      idToken: idToken,
      email: account.email,
      displayName: account.displayName,
    );
  }

  static Future<bool> isAppleAvailable() async {
    if (!SocialAuthConfig.appleEnabled) return false;
    try {
      return await SignInWithApple.isAvailable();
    } catch (_) {
      return false;
    }
  }

  static Future<SocialAuthCredential> signInWithApple() async {
    if (!SocialAuthConfig.appleEnabled) {
      throw const SocialAuthUnavailableException('Apple sign-in is disabled.');
    }
    if (kIsWeb && !_isSecureWebOrigin) {
      throw const SocialAuthUnavailableException(
        'Apple Web sign-in must run on HTTPS or localhost.',
      );
    }
    final bool needsWebAuthenticationOptions =
        kIsWeb || defaultTargetPlatform == TargetPlatform.android;
    if (needsWebAuthenticationOptions && !_hasAppleWebAuthenticationConfig) {
      throw const SocialAuthUnavailableException(
        'Apple Web sign-in requires --dart-define=APPLE_SERVICE_ID=your.service.id and --dart-define=APPLE_WEB_REDIRECT_URI=https://your-domain/auth/apple/callback.',
      );
    }
    if (!kIsWeb &&
        defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      throw const SocialAuthUnavailableException('Apple sign-in is disabled.');
    }

    final String nonce = generateNonce();
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const <AppleIDAuthorizationScopes>[
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      webAuthenticationOptions: _appleWebAuthenticationOptions(),
      nonce: nonce,
    );

    return AppleSocialAuthCredential(
      identityToken: credential.identityToken,
      authorizationCode: credential.authorizationCode,
      email: credential.email,
      givenName: credential.givenName,
      familyName: credential.familyName,
      nonce: nonce,
    );
  }

  static WebAuthenticationOptions? _appleWebAuthenticationOptions() {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return null;
    }

    final Uri? redirectUri = _appleRedirectUriForCurrentPlatform();
    if (SocialAuthConfig.appleServiceId.trim().isEmpty || redirectUri == null) {
      throw const SocialAuthUnavailableException(
        'Apple web authentication is not configured.',
      );
    }

    return WebAuthenticationOptions(
      clientId: SocialAuthConfig.appleServiceId.trim(),
      redirectUri: redirectUri,
    );
  }

  static Uri? _appleRedirectUriForCurrentPlatform() {
    if (kIsWeb) {
      return SocialAuthConfig.appleWebRedirectUriValue ??
          SocialAuthConfig.appleRedirectUriValue;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return SocialAuthConfig.appleAndroidRedirectUriValue ??
          SocialAuthConfig.appleRedirectUriValue;
    }
    return SocialAuthConfig.appleRedirectUriValue;
  }
}
