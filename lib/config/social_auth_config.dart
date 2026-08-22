class SocialAuthConfig {
  SocialAuthConfig._();

  static const bool googleEnabled = bool.fromEnvironment(
    'GOOGLE_SIGN_IN_ENABLED',
    defaultValue: false,
  );

  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  static const bool appleEnabled = bool.fromEnvironment(
    'APPLE_SIGN_IN_ENABLED',
    defaultValue: false,
  );

  static const String appleServiceId = String.fromEnvironment(
    'APPLE_SERVICE_ID',
    defaultValue: '',
  );

  static const String appleRedirectUri = String.fromEnvironment(
    'APPLE_REDIRECT_URI',
    defaultValue: '',
  );

  static const String appleWebRedirectUri = String.fromEnvironment(
    'APPLE_WEB_REDIRECT_URI',
    defaultValue: '',
  );

  static const String appleAndroidRedirectUri = String.fromEnvironment(
    'APPLE_ANDROID_REDIRECT_URI',
    defaultValue: '',
  );

  static String? get googleWebClientIdOrNull {
    final value = googleWebClientId.trim();
    return value.isEmpty ? null : value;
  }

  static String? get googleIosClientIdOrNull {
    final value = googleIosClientId.trim();
    return value.isEmpty ? null : value;
  }

  static String? get googleServerClientIdOrNull {
    final value = googleServerClientId.trim();
    return value.isEmpty ? null : value;
  }

  static Uri? get appleRedirectUriValue {
    return _parseUri(appleRedirectUri);
  }

  static Uri? get appleWebRedirectUriValue {
    return _parseUri(appleWebRedirectUri);
  }

  static Uri? get appleAndroidRedirectUriValue {
    return _parseUri(appleAndroidRedirectUri);
  }

  static bool get hasAppleWebAuthenticationConfig =>
      appleServiceId.trim().isNotEmpty && appleRedirectUriValue != null;

  static Uri? _parseUri(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return Uri.tryParse(trimmed);
  }
}
