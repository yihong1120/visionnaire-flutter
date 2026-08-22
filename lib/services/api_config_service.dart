import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/bff_config.dart';
import '../models/deployment_profile.dart';
import 'deployment_profile_service.dart';

/// Resolves API routes from the active deployment profile.
///
/// Production clients never read a user-entered server URL. Web is bound to
/// the current origin's BFF; native apps use a signed profile selected by a
/// completed company enrollment. The endpoint editor exists only in a native
/// Flutter debug build and never changes the enrolled production profile.
abstract final class ApiConfigService {
  static const String _runtimeOverrideKeyPrefix = 'api_url_';

  static const List<ApiEndpoint> endpoints = <ApiEndpoint>[
    ApiEndpoint(
      key: 'chat',
      name: 'Chat API (Orchestrator)',
      description: 'OpenClaw chat and streaming service.',
      relativePath: 'chat',
    ),
    ApiEndpoint(
      key: 'detection',
      name: 'Detection API',
      description: 'Object-detection service.',
      relativePath: 'detect',
    ),
    ApiEndpoint(
      key: 'management',
      name: 'Auth API (Orchestrator)',
      description: 'Account and management service.',
      relativePath: 'db_management',
    ),
    ApiEndpoint(
      key: 'fcm',
      name: 'FCM API',
      description: 'Device notification service.',
      relativePath: 'fcm',
    ),
    ApiEndpoint(
      key: 'streaming_web',
      name: 'Streaming API',
      description: 'Streaming media service.',
      relativePath: '',
    ),
    ApiEndpoint(
      key: 'fileManagement',
      name: 'File Management API',
      description: 'Document-management service.',
      relativePath: 'file_manage',
    ),
    ApiEndpoint(
      key: 'violationRecords',
      name: 'Violation Records API',
      description: 'Violation-record service.',
      relativePath: 'violations',
    ),
  ];

  /// Resolves the deployment profile once before routing any native request.
  static Future<DeploymentProfile> initialize() =>
      DeploymentProfileService.shared.initialize();

  /// Whether this debug build may show the native endpoint editor.
  ///
  static bool get allowsRuntimeEndpointOverrides {
    return !kIsWeb && kDebugMode;
  }

  /// Gets one effective service URI.
  static Future<String> getApiUrl(String serviceKey) async {
    final ApiEndpoint endpoint = _endpointFor(serviceKey);
    if (kIsWeb) return BffConfig.serviceBaseUrl(endpoint.key);

    await initialize();
    if (allowsRuntimeEndpointOverrides) {
      final String? runtimeOverride = await _readRuntimeOverride(endpoint);
      if (runtimeOverride != null) return runtimeOverride;
    }

    return _urlFor(endpoint, _nativeApiBaseUri()).toString();
  }

  /// Gets every effective service URI in one preferences read for debug
  /// builds, or without touching local preferences in production.
  static Future<Map<String, String>> getAllApiUrls() async {
    if (kIsWeb) {
      return Map<String, String>.unmodifiable(<String, String>{
        for (final ApiEndpoint endpoint in endpoints)
          endpoint.key: BffConfig.serviceBaseUrl(endpoint.key),
      });
    }

    await initialize();
    final Uri apiBaseUri = _nativeApiBaseUri();
    final SharedPreferences? preferences = allowsRuntimeEndpointOverrides
        ? await SharedPreferences.getInstance()
        : null;
    final Map<String, String> urls = <String, String>{};

    for (final ApiEndpoint endpoint in endpoints) {
      final String? runtimeOverride = preferences == null
          ? null
          : _parseRuntimeOverride(
              endpoint,
              preferences.getString(_runtimeOverrideStorageKey(endpoint.key)),
            );
      urls[endpoint.key] =
          runtimeOverride ?? _urlFor(endpoint, apiBaseUri).toString();
    }
    return Map<String, String>.unmodifiable(urls);
  }

  /// Stores an endpoint override for a debug build only.
  static Future<void> setRuntimeEndpointOverride(
    String serviceKey,
    String value,
  ) async {
    await initialize();
    _requireRuntimeOverridesEnabled();
    final ApiEndpoint endpoint = _endpointFor(serviceKey);
    final Uri uri = _parseRuntimeOverrideUri(value);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(
        _runtimeOverrideStorageKey(endpoint.key), uri.toString());
  }

  /// Removes one debug endpoint override.
  static Future<void> resetRuntimeEndpointOverride(String serviceKey) async {
    await initialize();
    _requireRuntimeOverridesEnabled();
    final ApiEndpoint endpoint = _endpointFor(serviceKey);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.remove(_runtimeOverrideStorageKey(endpoint.key));
  }

  /// Removes all debug endpoint overrides.
  static Future<void> resetAllRuntimeEndpointOverrides() async {
    await initialize();
    _requireRuntimeOverridesEnabled();
    await clearRuntimeEndpointOverridesForDeploymentChange();
  }

  /// Clears debug-only endpoint overrides without resolving a deployment.
  ///
  /// A controlled device re-activation must remove these local development
  /// values before it clears the enrolled profile. This operation is a no-op
  /// for release builds and Web, where endpoint editing is unavailable.
  static Future<void> clearRuntimeEndpointOverridesForDeploymentChange() async {
    if (!allowsRuntimeEndpointOverrides) return;
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await Future.wait<void>(
      endpoints.map(
        (ApiEndpoint endpoint) =>
            preferences.remove(_runtimeOverrideStorageKey(endpoint.key)),
      ),
    );
  }

  /// Validates a full HTTP(S) endpoint URI for the internal editor.
  static bool isValidRuntimeEndpointUrl(String value) {
    try {
      _parseRuntimeOverrideUri(value);
      return true;
    } on ApiConfigurationException {
      return false;
    }
  }

  static ApiEndpoint getEndpoint(String key) => _endpointFor(key);

  static ApiEndpoint _endpointFor(String serviceKey) {
    for (final ApiEndpoint endpoint in endpoints) {
      if (endpoint.key == serviceKey) return endpoint;
    }
    throw ApiConfigurationException('Unknown API service: $serviceKey.');
  }

  static Future<String?> _readRuntimeOverride(ApiEndpoint endpoint) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return _parseRuntimeOverride(
      endpoint,
      preferences.getString(_runtimeOverrideStorageKey(endpoint.key)),
    );
  }

  static String? _parseRuntimeOverride(ApiEndpoint endpoint, String? value) {
    if (value == null) return null;
    if (value.isEmpty) {
      throw ApiConfigurationException(
        'Stored internal URL for ${endpoint.key} is empty.',
      );
    }
    return _parseRuntimeOverrideUri(value).toString();
  }

  static Uri _parseRuntimeOverrideUri(String value) {
    if (value.isEmpty || value.trim() != value) {
      throw const ApiConfigurationException(
        'An endpoint URL must be a non-empty string without surrounding whitespace.',
      );
    }
    final Uri? uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.isAbsolute ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const ApiConfigurationException(
        'An endpoint URL must be an absolute HTTP(S) URI without user '
        'credentials, a query, or a fragment.',
      );
    }
    return uri;
  }

  static Uri _nativeApiBaseUri() {
    final Uri? apiBaseUri =
        DeploymentProfileService.shared.activeProfile.apiBaseUri;
    if (apiBaseUri == null) {
      throw const ApiConfigurationException(
        'A native deployment profile requires an API base URI.',
      );
    }
    return apiBaseUri;
  }

  static Uri _urlFor(ApiEndpoint endpoint, Uri apiBaseUri) {
    final String base = apiBaseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse(
      endpoint.relativePath.isEmpty ? base : '$base/${endpoint.relativePath}',
    );
  }

  static String _runtimeOverrideStorageKey(String serviceKey) =>
      '$_runtimeOverrideKeyPrefix$serviceKey';

  static void _requireRuntimeOverridesEnabled() {
    if (!allowsRuntimeEndpointOverrides) {
      throw const ApiConfigurationException(
        'Runtime endpoint overrides are disabled for this deployment.',
      );
    }
  }
}

/// One known service route beneath a deployment profile API root.
final class ApiEndpoint {
  const ApiEndpoint({
    required this.key,
    required this.name,
    required this.description,
    required this.relativePath,
  });

  final String key;
  final String name;
  final String description;
  final String relativePath;
}

/// Raised when an API route cannot be resolved from the deployment profile.
class ApiConfigurationException implements Exception {
  const ApiConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'ApiConfigurationException: $message';
}
