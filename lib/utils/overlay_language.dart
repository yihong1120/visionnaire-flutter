import 'dart:ui' show Locale;

/// Canonical language values accepted by the playback overlay API.
///
/// Overlay text is rendered into the backend-owned HLS stream, so this is
/// deliberately separate from presentation-only locale formatting.
abstract final class OverlayLanguage {
  static const String fallback = 'zh-TW';

  static const Set<String> supportedValues = <String>{
    'zh-TW',
    'en',
    'zh-CN',
    'ja',
    'vi',
    'id',
    'fr',
    'th',
  };

  /// Maps the persisted application locale to a playback API language.
  static String forLocale(Locale locale) {
    final languageCode = locale.languageCode.toLowerCase();
    final countryCode = locale.countryCode?.toUpperCase();

    if (languageCode == 'zh') {
      return countryCode == 'CN' ? 'zh-CN' : 'zh-TW';
    }
    return supportedValues.contains(languageCode) ? languageCode : fallback;
  }

  /// Returns a canonical API value or throws when [value] is unsupported.
  static String requireSupported(String value) {
    final normalized = _canonicalize(value);
    if (!supportedValues.contains(normalized)) {
      throw ArgumentError.value(
        value,
        'language',
        'Unsupported playback overlay language',
      );
    }
    return normalized;
  }

  /// Safely normalizes a route value, using the application fallback for an
  /// absent or invalid query parameter.
  static String normalizeOrFallback(String? value) {
    if (value == null || value.trim().isEmpty) return fallback;
    try {
      return requireSupported(value);
    } on ArgumentError {
      return fallback;
    }
  }

  static String _canonicalize(String value) {
    final normalized = value.trim().replaceAll('_', '-').toLowerCase();
    return switch (normalized) {
      'zh-tw' => 'zh-TW',
      'zh-cn' => 'zh-CN',
      'en' => 'en',
      'ja' => 'ja',
      'vi' => 'vi',
      'id' => 'id',
      'fr' => 'fr',
      'th' => 'th',
      _ => value.trim(),
    };
  }
}
