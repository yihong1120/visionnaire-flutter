/// The source that selected a deployment.
///
/// Native profiles are selected by a completed company enrollment and then
/// resolved through the signed registry. Web is permanently same-origin BFF.
enum DeploymentProfileSource {
  enrollment,
  webBff,
}

/// Raised when a deployment selector or profile does not satisfy its contract.
class DeploymentProfileFormatException implements Exception {
  const DeploymentProfileFormatException(this.message);

  final String message;

  @override
  String toString() => 'DeploymentProfileFormatException: $message';
}

/// Identifies one deployment before its signed profile is loaded.
///
/// A company enrollment provides only [deploymentId]. The remaining profile
/// values are fetched from and authenticated by the deployment registry.
final class DeploymentSelector {
  const DeploymentSelector._({
    required this.deploymentId,
    required this.source,
  });

  final String deploymentId;
  final DeploymentProfileSource source;

  /// Creates the selector stored after a successful company enrollment.
  factory DeploymentSelector.fromEnrollment(String deploymentId) {
    return DeploymentSelector._(
      deploymentId: DeploymentProfileContract.requiredUuid(
        deploymentId,
        'deployment_id',
      ),
      source: DeploymentProfileSource.enrollment,
    );
  }
}

/// A typed, signed deployment profile.
///
/// A profile is configuration data, never authentication state. In
/// particular, it must not contain access tokens, refresh tokens, or client
/// secrets. Web uses a same-origin BFF and therefore has no external
/// [apiBaseUri].
final class DeploymentProfile {
  const DeploymentProfile._({
    required this.schemaVersion,
    required this.deploymentId,
    required this.tenantId,
    required this.apiBaseUri,
    required this.revision,
    required this.issuedAt,
    required this.expiresAt,
    required this.source,
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String deploymentId;
  final String tenantId;
  final Uri? apiBaseUri;
  final int revision;
  final int? issuedAt;
  final int? expiresAt;
  final DeploymentProfileSource source;

  /// Parses the signed registry profile after its signature was verified.
  ///
  /// The signature and key metadata are deliberately not included here: they
  /// are transport metadata verified by the registry client before this typed
  /// profile is constructed.
  factory DeploymentProfile.fromRegistryConfiguration(
    Map<String, Object?> configuration, {
    required DeploymentSelector selector,
    required bool allowInsecureLoopback,
    required int issuedAt,
    required int expiresAt,
  }) {
    const Set<String> requiredKeys = <String>{
      'schema_version',
      'deployment_id',
      'tenant_id',
      'api_base_url',
      'config_revision',
    };
    if (configuration.length != requiredKeys.length ||
        !configuration.keys.toSet().containsAll(requiredKeys)) {
      throw const DeploymentProfileFormatException(
        'Registry profile has an invalid schema.',
      );
    }

    final int schemaVersion = _requiredSchemaVersion(
      configuration['schema_version'],
    );
    final String deploymentId = DeploymentProfileContract.requiredUuid(
      configuration['deployment_id'],
      'deployment_id',
    );
    if (deploymentId != selector.deploymentId) {
      throw const DeploymentProfileFormatException(
        'Registry profile deployment_id does not match the selector.',
      );
    }
    final int verifiedIssuedAt = DeploymentProfileContract.requiredUnixSeconds(
      issuedAt,
      'issued_at',
    );
    final int verifiedExpiresAt = DeploymentProfileContract.requiredUnixSeconds(
      expiresAt,
      'expires_at',
    );
    if (verifiedExpiresAt <= verifiedIssuedAt) {
      throw const DeploymentProfileFormatException(
        'expires_at must be later than issued_at.',
      );
    }

    return DeploymentProfile._(
      schemaVersion: schemaVersion,
      deploymentId: deploymentId,
      tenantId: DeploymentProfileContract.requiredUuid(
        configuration['tenant_id'],
        'tenant_id',
      ),
      apiBaseUri: DeploymentProfileContract.requiredApiBaseUri(
        configuration['api_base_url'],
        allowInsecureLoopback: allowInsecureLoopback,
      ),
      revision: DeploymentProfileContract.requiredRevision(
        configuration['config_revision'],
      ),
      issuedAt: verifiedIssuedAt,
      expiresAt: verifiedExpiresAt,
      source: selector.source,
    );
  }

  /// Creates the same-origin profile used by Flutter Web.
  factory DeploymentProfile.webBff({
    required String deploymentId,
    required String tenantId,
    required int revision,
  }) {
    return DeploymentProfile._(
      schemaVersion: currentSchemaVersion,
      deploymentId: DeploymentProfileContract.requiredString(
        deploymentId,
        'deployment_id',
      ),
      tenantId: DeploymentProfileContract.requiredString(tenantId, 'tenant_id'),
      apiBaseUri: null,
      revision: DeploymentProfileContract.requiredRevision(revision),
      issuedAt: null,
      expiresAt: null,
      source: DeploymentProfileSource.webBff,
    );
  }

  static int _requiredSchemaVersion(Object? value) {
    if (value != currentSchemaVersion) {
      throw const DeploymentProfileFormatException(
        'Registry profile has an unsupported schema_version.',
      );
    }
    return currentSchemaVersion;
  }

  static Uri _parseApiBaseUri(
    String apiBaseUrl, {
    required bool allowInsecureLoopback,
  }) {
    final Uri? uri = Uri.tryParse(apiBaseUrl);
    if (uri == null ||
        !uri.isAbsolute ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const DeploymentProfileFormatException(
        'api_base_url must be an absolute URI without user credentials, '
        'a query, or a fragment.',
      );
    }

    if (!_isCanonicalApiBaseUri(apiBaseUrl, uri)) {
      throw const DeploymentProfileFormatException(
        'api_base_url must use canonical lowercase HTTPS URI form without a '
        'trailing slash or an explicit default port.',
      );
    }

    if (uri.scheme == 'https') return uri;

    if (uri.scheme == 'http' &&
        allowInsecureLoopback &&
        _isLoopbackHost(uri.host)) {
      return uri;
    }

    throw const DeploymentProfileFormatException(
      'api_base_url must use HTTPS. HTTP is allowed only for a loopback host '
      'in a debug build.',
    );
  }

  static bool _isLoopbackHost(String host) {
    final String normalizedHost = host.toLowerCase();
    if (normalizedHost == 'localhost' || normalizedHost == '::1') {
      return true;
    }

    final List<String> octets = normalizedHost.split('.');
    if (octets.length != 4 || octets.first != '127') return false;

    for (final String octet in octets.skip(1)) {
      final int? value = int.tryParse(octet);
      if (value == null || value < 0 || value > 255) return false;
    }
    return true;
  }

  static bool _isCanonicalApiBaseUri(String value, Uri uri) {
    if (value != uri.toString() ||
        !value.startsWith('${uri.scheme}://') ||
        uri.host != uri.host.toLowerCase() ||
        !_asciiHost.hasMatch(uri.host) ||
        uri.path.endsWith('/') ||
        uri.path.contains('//') ||
        uri.pathSegments.any(
          (String segment) => segment == '.' || segment == '..',
        )) {
      return false;
    }

    return !(uri.hasPort &&
        ((uri.scheme == 'https' && uri.port == 443) ||
            (uri.scheme == 'http' && uri.port == 80)));
  }

  /// Whether this profile remains valid at the supplied UTC Unix second.
  ///
  /// Web's same-origin BFF profile has no registry expiry. Native profiles are
  /// always created with verified signing timestamps.
  bool isActiveAt(int nowUnixSeconds) {
    final int? expiry = expiresAt;
    return expiry == null || nowUnixSeconds < expiry;
  }
}

final RegExp _canonicalUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final RegExp _asciiHost = RegExp(r'^[a-z0-9.:-]+$');

/// Shared validators for signed profiles and persisted native sessions.
///
/// Keeping these rules in one place prevents a previously stored malformed
/// session from being treated as a profile that the registry would reject.
abstract final class DeploymentProfileContract {
  static String requiredString(Object? value, String key) =>
      _requiredString(value, key);

  static String requiredUuid(Object? value, String key) =>
      _requiredUuid(value, key);

  static int requiredRevision(Object? value) => _requiredRevision(value);

  static int requiredUnixSeconds(Object? value, String key) =>
      _requiredUnixSeconds(value, key);

  static Uri requiredApiBaseUri(
    Object? value, {
    required bool allowInsecureLoopback,
  }) {
    return DeploymentProfile._parseApiBaseUri(
      _requiredString(value, 'api_base_url'),
      allowInsecureLoopback: allowInsecureLoopback,
    );
  }
}

String _requiredString(Object? value, String key) {
  if (value is! String || value.isEmpty || value.trim() != value) {
    throw DeploymentProfileFormatException(
      '$key must be a non-empty string without surrounding whitespace.',
    );
  }
  return value;
}

String _requiredUuid(Object? value, String key) {
  final String string = _requiredString(value, key);
  if (string != string.toLowerCase() || !_canonicalUuid.hasMatch(string)) {
    throw DeploymentProfileFormatException(
      '$key must be a canonical lowercase RFC4122 UUID.',
    );
  }
  return string;
}

int _requiredRevision(Object? value) {
  if (value is! int || value < 0) {
    throw const DeploymentProfileFormatException(
      'config_revision must be a non-negative integer.',
    );
  }
  return value;
}

int _requiredUnixSeconds(Object? value, String key) {
  if (value is! int || value < 0) {
    throw DeploymentProfileFormatException(
      '$key must be a non-negative UTC Unix second.',
    );
  }
  return value;
}
