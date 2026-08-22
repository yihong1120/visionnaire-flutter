import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hcaptcha_flutter/hcaptcha_flutter.dart';

import '../config/hcaptcha_config.dart';

class HCaptchaException implements Exception {
  const HCaptchaException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class HCaptchaService {
  HCaptchaService._();

  static const Duration _challengeTimeout = Duration(minutes: 2);

  @visibleForTesting
  static Future<String?> Function(Locale locale)? debugTokenResolver;

  static Future<String?>? _activeRequest;

  /// Native hCaptcha owns one WebView at a time. Returning the in-flight
  /// request prevents a second tap from presenting another challenge over it.
  static bool get isChallengeActive => _activeRequest != null;

  static bool get isSupportedNativePlatform {
    if (kIsWeb) return false;

    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  static Future<String?> requestToken({required Locale locale}) {
    if (!HCaptchaConfig.isConfigured || !isSupportedNativePlatform) {
      return Future<String?>.value();
    }

    final debugResolver = debugTokenResolver;
    if (debugResolver != null) {
      return debugResolver(locale);
    }

    final activeRequest = _activeRequest;
    if (activeRequest != null) {
      return activeRequest;
    }

    final request = _requestToken(locale);
    _activeRequest = request;
    unawaited(
      request.then<void>(
        (_) => _clearActiveRequest(request),
        onError: (Object _, StackTrace __) => _clearActiveRequest(request),
      ),
    );
    return request;
  }

  static Future<String?> _requestToken(Locale locale) async {
    try {
      final token = await HCaptchaFlutter.show(
        siteKey: HCaptchaConfig.normalizedSiteKey,
        language: _languageTagFor(locale),
      ).timeout(
        _challengeTimeout,
      );
      final normalizedToken = token.trim();
      if (normalizedToken.isEmpty) {
        throw const HCaptchaException('hCaptcha returned an empty token.');
      }
      return normalizedToken;
    } on TimeoutException catch (e) {
      throw HCaptchaException('hCaptcha challenge timed out.', e);
    } on MissingPluginException catch (e) {
      throw HCaptchaException('hCaptcha is not available on this platform.', e);
    } on PlatformException catch (e) {
      throw HCaptchaException(e.message ?? 'hCaptcha challenge failed.', e);
    } finally {
      await _dismissNativeChallenge();
    }
  }

  /// Cancels a visible native challenge and releases its WebView immediately.
  ///
  /// This is safe to call from a page's [State.dispose] and is idempotent.
  static Future<void> cancelActiveChallenge() async {
    if (_activeRequest == null) return;
    await _dismissNativeChallenge();
  }

  static Future<void> _dismissNativeChallenge() async {
    if (!isSupportedNativePlatform) return;

    try {
      await HCaptchaFlutter.dismiss();
    } on MissingPluginException {
      // The app may be shutting down before the plugin is attached.
    } on PlatformException {
      // Cleanup must never replace the challenge's original result.
    }
  }

  static void _clearActiveRequest(Future<String?> request) {
    if (identical(_activeRequest, request)) {
      _activeRequest = null;
    }
  }

  static String _languageTagFor(Locale locale) {
    final countryCode = locale.countryCode;
    if (countryCode == null || countryCode.isEmpty) {
      return locale.languageCode;
    }

    return '${locale.languageCode}-$countryCode';
  }
}
