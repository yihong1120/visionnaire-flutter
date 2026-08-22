import 'package:flutter/foundation.dart';

class HCaptchaConfig {
  static const bool enabled = bool.fromEnvironment(
    'HCAPTCHA_ENABLED',
    defaultValue: false,
  );

  static const String siteKey = String.fromEnvironment(
    'HCAPTCHA_SITE_KEY',
    defaultValue: '',
  );

  @visibleForTesting
  static bool? debugIsConfigured;

  @visibleForTesting
  static String? debugSiteKey;

  static String get normalizedSiteKey => (debugSiteKey ?? siteKey).trim();

  static bool get isConfigured =>
      debugIsConfigured ?? (enabled && normalizedSiteKey.isNotEmpty);
}
