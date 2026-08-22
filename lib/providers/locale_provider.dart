import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../utils/overlay_language.dart';

/// A provider for managing and updating the application's locale.
///
/// Holds the current [Locale] and provides a method to update it. Notifies listeners when the locale changes.
class LocaleProvider extends ChangeNotifier {
  // Keys for persistence
  static const String _kPrefLocaleKey = 'preferred_locale';
  static const String _kManualKey = 'is_manual_locale';

  // The locales this app explicitly supports in UI routing and resources
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh', 'TW'),
    Locale('en', 'GB'),
    Locale('fr', 'FR'),
    Locale('id', 'ID'),
    Locale('ja', 'JP'),
    Locale('th', 'TH'),
    Locale('vi', 'VN'),
  ];

  /// The current locale of the application. Defaults to zh_TW to keep
  /// backward-compatibility with existing tests and behavior.
  Locale _locale = const Locale('zh', 'TW');
  bool _isManual = false;

  /// The current (raw) locale value stored by the provider.
  Locale get locale => _locale;

  /// The effective locale the UI should use after mapping to the set of
  /// supported locales (falls back to English if unsupported).
  Locale get effectiveLocale => _bestSupportedFor(_locale);

  /// Whether the current locale was manually selected by the user.
  bool get isManual => _isManual;

  /// The language used for labels rendered by backend playback streams.
  ///
  /// This derives from the same persisted user preference as the UI locale,
  /// making it safe to restore after a direct URL visit or page refresh.
  String get selectedOverlayLanguage => OverlayLanguage.forLocale(
        effectiveLocale,
      );

  /// Initialize locale from persisted user choice if present; otherwise,
  /// auto-detect from system and fall back to English when unsupported.
  Future<void> initialize() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool manual = prefs.getBool(_kManualKey) ?? false;
      final String? savedCode = prefs.getString(_kPrefLocaleKey);

      if (manual && savedCode != null && savedCode.isNotEmpty) {
        // Respect user's manual choice long-term
        final Locale saved = _decodeLocale(savedCode);
        // Store the exact saved value to keep object identity expectations
        // in tests; UI will map via [effectiveLocale].
        _locale = saved;
        _isManual = true;
        notifyListeners();
        return;
      }

      // Auto-detect from system
      final Locale device = WidgetsBinding.instance.platformDispatcher.locale;
      _locale = _bestSupportedFor(device);
      _isManual = false;
      notifyListeners();
    } catch (_) {
      // Safe fallback to English if anything goes wrong
      _locale = const Locale('en', 'GB');
      _isManual = false;
      notifyListeners();
    }
  }

  /// Sets a new locale as user's manual preference and persists it.
  void setLocale(Locale newLocale) {
    if (_locale == newLocale) return;
    _locale = newLocale; // Preserve exact instance as tests expect identity
    _isManual = true;
    notifyListeners();

    // Fire-and-forget persistence
    unawaited(() async {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kPrefLocaleKey, _encodeLocale(newLocale));
        await prefs.setBool(_kManualKey, true);
      } catch (_) {
        // Ignore persistence errors silently
      }
    }());
  }

  /// Optionally clear manual preference and re-auto-detect on next init.
  Future<void> clearManualPreference() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrefLocaleKey);
      await prefs.remove(_kManualKey);
      _isManual = false;
    } catch (_) {
      // Ignore errors
    }
  }

  // --- Helpers ---
  static Locale _bestSupportedFor(Locale? candidate) {
    if (candidate == null) {
      return const Locale('en', 'GB');
    }

    // 1) Exact match language+country
    for (final Locale s in supportedLocales) {
      if (s.languageCode == candidate.languageCode &&
          s.countryCode == candidate.countryCode) {
        return s;
      }
    }
    // 2) Match by language only
    for (final Locale s in supportedLocales) {
      if (s.languageCode == candidate.languageCode) {
        return s;
      }
    }
    // 3) Explicit mapping by language families
    switch (candidate.languageCode) {
      case 'zh':
        return const Locale('zh', 'TW');
      case 'fr':
        return const Locale('fr', 'FR');
      case 'en':
        return const Locale('en', 'GB');
      case 'id':
        return const Locale('id', 'ID');
      case 'ja':
        return const Locale('ja', 'JP');
      case 'th':
        return const Locale('th', 'TH');
      case 'vi':
        return const Locale('vi', 'VN');
      default:
        return const Locale('en', 'GB');
    }
  }

  static String _encodeLocale(Locale l) {
    final String lang = l.languageCode;
    final String? country = l.countryCode;
    return (country != null && country.isNotEmpty) ? '${lang}_$country' : lang;
  }

  static Locale _decodeLocale(String code) {
    final List<String> parts = code.split('_');
    if (parts.length >= 2) {
      return Locale(parts[0], parts[1]);
    }
    return Locale(parts[0]);
  }
}
