/// Test helpers and utilities for the Visionnaire Flutter app tests.
///
/// Provides common test utilities, mock data, and helper functions to support
/// comprehensive unit testing across all app components.
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:visionnaire/l10n/app_localizations.dart';
import 'package:visionnaire/providers/unified_auth_provider.dart';
import 'package:visionnaire/providers/locale_provider.dart';
import 'package:visionnaire/providers/api_config_provider.dart';
import 'package:visionnaire/services/biometric_auth_service.dart';

/// Creates a test-ready widget with all necessary providers and localization
Widget createTestWidget(
  Widget child, {
  UnifiedAuthProvider? authProvider,
  LocaleProvider? localeProvider,
  ApiConfigProvider? apiConfigProvider,
}) {
  final UnifiedAuthProvider effectiveAuthProvider =
      authProvider ?? MockUnifiedAuthProvider();
  final LocaleProvider effectiveLocaleProvider =
      localeProvider ?? LocaleProvider();
  final ApiConfigProvider effectiveApiConfigProvider =
      apiConfigProvider ?? MockApiConfigProvider();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UnifiedAuthProvider>.value(
        value: effectiveAuthProvider,
      ),
      ChangeNotifierProvider<LocaleProvider>.value(
        value: effectiveLocaleProvider,
      ),
      ChangeNotifierProvider<ApiConfigProvider>.value(
        value: effectiveApiConfigProvider,
      ),
    ],
    child: MaterialApp(
      home: child,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

/// Creates a localized [MaterialApp] for widget tests that do not need providers.
Widget createLocalizedTestApp(
  Widget child, {
  bool wrapInScaffold = true,
}) {
  return MaterialApp(
    home: wrapInScaffold ? Scaffold(body: child) : child,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
  );
}

/// Mock implementations for testing
class MockUnifiedAuthProvider extends UnifiedAuthProvider {
  bool _isLoggedIn = false;
  String? _username;
  String? _displayName;
  String? _role;
  int? _userId;
  int? _groupId;
  List<String> _features = [];
  bool _isSuperAdmin = false;
  bool throwOnLogout = false;
  Object? loginError;
  Completer<void>? loginCompleter;
  Duration loginDelay = Duration.zero;
  int loginCallCount = 0;
  String? lastLoginUsername;
  String? lastLoginPassword;
  String? lastLoginHCaptchaToken;
  bool biometricUnlockAvailable = false;
  bool biometricUnlockEnabled = false;
  bool biometricUnlockRequired = false;
  bool biometricUnlockResult = true;
  int biometricUnlockCallCount = 0;
  String? lastBiometricUnlockReason;
  BiometricUnlockType? mockBiometricUnlockType;

  @override
  bool get isLoggedIn => _isLoggedIn;

  @override
  String? get requestToken => _isLoggedIn ? 'test-access-token' : null;

  @override
  String? get username => _username;

  @override
  String? get displayName => _displayName;

  @override
  String? get role => _role;

  @override
  int? get userId => _userId;

  @override
  int? get groupId => _groupId;

  @override
  bool get isSuperAdmin => _isSuperAdmin;

  @override
  bool get isBiometricUnlockAvailable => biometricUnlockAvailable;

  @override
  bool get isBiometricUnlockEnabled => biometricUnlockEnabled;

  @override
  bool get isBiometricUnlockRequired => biometricUnlockRequired;

  @override
  BiometricUnlockType? get biometricUnlockType => mockBiometricUnlockType;

  @override
  bool get canUnlockWithBiometrics =>
      biometricUnlockAvailable &&
      biometricUnlockEnabled &&
      biometricUnlockRequired;

  @override
  bool hasFeature(String name) => _features.contains(name);

  @override
  Future<void> login(
    String username,
    String password, {
    String? hcaptchaToken,
    bool enableBiometricUnlock = false,
  }) async {
    loginCallCount += 1;
    lastLoginUsername = username;
    lastLoginPassword = password;
    lastLoginHCaptchaToken = hcaptchaToken;

    if (loginCompleter != null) {
      await loginCompleter!.future;
    } else if (loginDelay > Duration.zero) {
      await Future<void>.delayed(loginDelay);
    }

    if (loginError != null) {
      throw loginError!;
    }

    setLoginState(
      isLoggedIn: true,
      username: username,
      role: _role ?? 'user',
      userId: _userId ?? 1,
      groupId: _groupId,
      features: _features,
      isSuperAdmin: _isSuperAdmin,
    );
  }

  @override
  Future<void> logout({bool localOnly = false}) async {
    if (throwOnLogout) {
      throw Exception('forced logout failure');
    }

    _isLoggedIn = false;
    _username = null;
    _displayName = null;
    _role = null;
    _userId = null;
    _groupId = null;
    _isSuperAdmin = false;
    _features = [];
    notifyListeners();
  }

  @override
  Future<bool> unlockWithBiometrics({
    required String reason,
  }) async {
    biometricUnlockCallCount += 1;
    lastBiometricUnlockReason = reason;
    if (!biometricUnlockResult) return false;

    biometricUnlockRequired = false;
    setLoginState(
      isLoggedIn: true,
      username: _username ?? 'biometric-user',
      displayName: _displayName,
      role: _role ?? 'user',
      userId: _userId ?? 1,
      groupId: _groupId,
      features: _features,
      isSuperAdmin: _isSuperAdmin,
    );
    return true;
  }

  void setLoginState({
    required bool isLoggedIn,
    String? username,
    String? displayName,
    String? role,
    int? userId,
    int? groupId,
    List<String> features = const [],
    bool isSuperAdmin = false,
  }) {
    _isLoggedIn = isLoggedIn;
    _username = username;
    _displayName = displayName;
    _role = role;
    _userId = userId;
    _groupId = groupId;
    _features = features;
    _isSuperAdmin = isSuperAdmin;
    notifyListeners();
  }

  void setLoggedIn(bool value) {
    _isLoggedIn = value;
    notifyListeners();
  }

  void setUsername(String? value) {
    _username = value;
    notifyListeners();
  }

  void setDisplayName(String? value) {
    _displayName = value;
    notifyListeners();
  }

  void setRole(String? value) {
    _role = value;
    notifyListeners();
  }

  void setUserId(int? value) {
    _userId = value;
    notifyListeners();
  }

  void setGroupId(int? value) {
    _groupId = value;
    notifyListeners();
  }

  void setSuperAdmin(bool value) {
    _isSuperAdmin = value;
    notifyListeners();
  }

  void setFeatures(Set<String> features) {
    _features = features.toList();
    notifyListeners();
  }

  void setBiometricUnlockState({
    required bool available,
    required bool enabled,
    required bool unlockRequired,
    BiometricUnlockType? type,
  }) {
    biometricUnlockAvailable = available;
    biometricUnlockEnabled = enabled;
    biometricUnlockRequired = unlockRequired;
    mockBiometricUnlockType = type;
    notifyListeners();
  }

  void addFeature(String feature) {
    if (!_features.contains(feature)) {
      _features.add(feature);
      notifyListeners();
    }
  }

  void removeFeature(String feature) {
    if (_features.remove(feature)) {
      notifyListeners();
    }
  }
}

class MockLocaleProvider extends LocaleProvider {
  Locale _locale = const Locale('en', 'GB');

  @override
  Locale get locale => _locale;

  @override
  void setLocale(Locale newLocale) {
    _locale = newLocale;
    notifyListeners();
  }
}

class MockApiConfigProvider extends ApiConfigProvider {
  final Map<String, String> _apiUrls = {
    'chat': 'https://test-chat.example.com',
    'detection': 'https://test-detection.example.com',
    'management': 'https://test-management.example.com',
    'fcm': 'https://test-fcm.example.com',
    'streaming_web': 'https://test-streaming.example.com',
    'fileManagement': 'https://test-files.example.com',
    'violationRecords': 'https://test-violations.example.com',
  };

  @override
  String getApiUrl(String key) {
    final String? url = _apiUrls[key];
    if (url == null) {
      throw StateError('No test API route is configured for $key.');
    }
    return url;
  }

  void setApiUrl(String key, String url) {
    _apiUrls[key] = url;
    notifyListeners();
  }
}

/// Mock data generators
class MockDataGenerator {
  static Map<String, dynamic> createMockUser({
    int id = 1,
    String username = 'testuser',
    String role = 'user',
    int groupId = 1,
    bool isActive = true,
  }) {
    return {
      'id': id,
      'username': username,
      'role': role,
      'group_id': groupId,
      'is_active': isActive,
      'profile': {
        'family_name': 'Test',
        'given_name': 'User',
        'email': 'test@example.com',
      }
    };
  }

  static Map<String, dynamic> createMockSite({
    int id = 1,
    String name = 'Test Site',
    int groupId = 1,
  }) {
    return {
      'id': id,
      'name': name,
      'group_id': groupId,
    };
  }

  static Map<String, dynamic> createMockDetectionResult({
    List<dynamic> bbox = const [100, 100, 200, 200],
    double confidence = 0.85,
    String label = 'person',
  }) {
    return {
      'bbox': bbox,
      'confidence': confidence,
      'label': label,
    };
  }

  static Map<String, dynamic> createMockViolationRecord({
    int id = 1,
    String siteId = '1',
    String description = 'Test violation',
    String severity = 'medium',
    DateTime? timestamp,
  }) {
    return {
      'id': id,
      'site_id': siteId,
      'description': description,
      'severity': severity,
      'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
      'images': ['image1.jpg', 'image2.jpg'],
    };
  }

  static Uint8List createMockImageBytes() {
    // A valid 1x1 transparent PNG keeps image-decoding tests stable.
    return Uint8List.fromList([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      13,
      73,
      72,
      68,
      82,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      8,
      6,
      0,
      0,
      0,
      31,
      21,
      196,
      137,
      0,
      0,
      0,
      1,
      115,
      82,
      71,
      66,
      0,
      174,
      206,
      28,
      233,
      0,
      0,
      0,
      10,
      73,
      68,
      65,
      84,
      120,
      156,
      99,
      0,
      1,
      0,
      0,
      5,
      0,
      1,
      13,
      10,
      42,
      186,
      0,
      0,
      0,
      0,
      73,
      69,
      78,
      68,
      174,
      66,
      96,
      130,
    ]);
  }
}

/// Test utilities
class TestUtils {
  /// Pump and settle widget with common delays
  static Future<void> pumpAndSettle(
    WidgetTester tester, [
    Duration step = const Duration(milliseconds: 16),
    int maxPumps = 120,
  ]) async {
    var pumps = 0;

    do {
      await tester.pump(step);
      pumps += 1;

      if (!tester.binding.hasScheduledFrame) {
        return;
      }
    } while (pumps < maxPumps);

    throw TestFailure(
      'pumpAndSettle timed out after $pumps pumps. '
      'A widget may be scheduling frames continuously.',
    );
  }

  /// Pump a fixed number of frames to advance short animations.
  static Future<void> pumpFrames(
    WidgetTester tester, {
    int count = 2,
    Duration step = const Duration(milliseconds: 16),
  }) async {
    for (var index = 0; index < count; index += 1) {
      await tester.pump(step);
    }
  }

  /// Pump until a finder appears or the retry budget is exhausted.
  static Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 120,
    Duration step = const Duration(milliseconds: 16),
  }) async {
    for (var index = 0; index < maxPumps; index += 1) {
      if (finder.evaluate().isNotEmpty) {
        return;
      }

      await tester.pump(step);
    }

    throw TestFailure('Finder did not appear within $maxPumps pumps: $finder');
  }

  /// Pump until a finder disappears or the retry budget is exhausted.
  static Future<void> pumpUntilMissing(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 120,
    Duration step = const Duration(milliseconds: 16),
  }) async {
    for (var index = 0; index < maxPumps; index += 1) {
      if (finder.evaluate().isEmpty) {
        return;
      }

      await tester.pump(step);
    }

    throw TestFailure(
      'Finder was still present after $maxPumps pumps: $finder',
    );
  }

  /// Find widget by type with error handling
  static Finder findWidgetSafely<T extends Widget>() {
    try {
      return find.byType(T);
    } catch (e) {
      throw TestFailure('Widget of type $T not found: $e');
    }
  }

  /// Tap and settle
  static Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await pumpAndSettle(tester);
  }

  /// Enter text and settle
  static Future<void> enterTextAndSettle(
    WidgetTester tester,
    Finder finder,
    String text,
  ) async {
    await tester.enterText(finder, text);
    await pumpAndSettle(tester);
  }
}

/// Custom matchers for testing
class CustomMatchers {
  /// Matcher for checking if a widget contains specific text
  static Matcher containsText(String text) {
    return predicate<Widget>((widget) {
      if (widget is Text) {
        return widget.data?.contains(text) == true;
      }
      return false;
    }, 'contains text "$text"');
  }

  /// Matcher for checking widget visibility
  static Matcher isVisible() {
    return predicate<Widget>((widget) {
      return widget is Opacity ? widget.opacity > 0 : true;
    }, 'is visible');
  }
}
