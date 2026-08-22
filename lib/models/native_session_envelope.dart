import 'auth_user_snapshot.dart';
import 'deployment_profile.dart';

/// The complete native refresh-session record kept in secure storage.
///
/// The envelope binds a credential to one exact deployment profile. It is
/// deliberately versioned and strict: unsupported or extra fields are not
/// migrated or guessed.
final class NativeSessionEnvelope {
  const NativeSessionEnvelope._({
    required this.user,
    required this.refreshToken,
    required this.deploymentId,
    required this.tenantId,
    required this.apiBaseUrl,
    required this.profileSource,
    required this.profileRevision,
  });

  static const int currentVersion = 8;

  final AuthUserSnapshot user;
  final String refreshToken;
  final String deploymentId;
  final String tenantId;
  final String apiBaseUrl;
  final DeploymentProfileSource profileSource;
  final int profileRevision;

  factory NativeSessionEnvelope.create({
    required AuthUserSnapshot user,
    required String refreshToken,
    required DeploymentProfile deploymentProfile,
  }) {
    final Uri? apiBaseUri = deploymentProfile.apiBaseUri;
    if (apiBaseUri == null) {
      throw StateError(
          'A native session requires a native deployment profile.');
    }
    return NativeSessionEnvelope._(
      user: user,
      refreshToken: _requiredString(refreshToken, 'refresh_token'),
      deploymentId: deploymentProfile.deploymentId,
      tenantId: deploymentProfile.tenantId,
      apiBaseUrl: apiBaseUri.toString(),
      profileSource: deploymentProfile.source,
      profileRevision: deploymentProfile.revision,
    );
  }

  factory NativeSessionEnvelope.fromJson(Map<String, Object?> json) {
    const Set<String> keys = <String>{
      'version',
      'deployment_id',
      'tenant_id',
      'api_base_url',
      'profile_source',
      'config_revision',
      'refresh_token',
      'username',
      'display_name',
      'role',
      'user_id',
      'group_id',
      'status',
      'feature_names',
    };
    if (json.length != keys.length || !json.keys.toSet().containsAll(keys)) {
      throw const FormatException(
          'Stored native session has an invalid schema.');
    }
    if (json['version'] != currentVersion) {
      throw const FormatException('Unsupported native session version.');
    }

    try {
      return NativeSessionEnvelope._(
        user: AuthUserSnapshot.fromStoredSession(json),
        refreshToken: _requiredString(json['refresh_token'], 'refresh_token'),
        deploymentId: DeploymentProfileContract.requiredUuid(
          json['deployment_id'],
          'deployment_id',
        ),
        tenantId: DeploymentProfileContract.requiredUuid(
          json['tenant_id'],
          'tenant_id',
        ),
        apiBaseUrl: DeploymentProfileContract.requiredApiBaseUri(
          json['api_base_url'],
          allowInsecureLoopback: false,
        ).toString(),
        profileSource: _profileSource(json['profile_source']),
        profileRevision: DeploymentProfileContract.requiredRevision(
          json['config_revision'],
        ),
      );
    } on DeploymentProfileFormatException catch (error) {
      throw FormatException('Stored native session has an invalid profile: '
          '${error.message}');
    }
  }

  bool matches(DeploymentProfile deploymentProfile) {
    final Uri? apiBaseUri = deploymentProfile.apiBaseUri;
    return apiBaseUri != null &&
        deploymentId == deploymentProfile.deploymentId &&
        tenantId == deploymentProfile.tenantId &&
        apiBaseUrl == apiBaseUri.toString() &&
        profileSource == deploymentProfile.source &&
        profileRevision == deploymentProfile.revision;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'version': currentVersion,
        'deployment_id': deploymentId,
        'tenant_id': tenantId,
        'api_base_url': apiBaseUrl,
        'profile_source': profileSource.name,
        'config_revision': profileRevision,
        'refresh_token': refreshToken,
        'username': user.username,
        'display_name': user.displayName,
        'role': user.role,
        'user_id': user.userId,
        'group_id': user.groupId,
        'status': user.status,
        'feature_names': user.features,
      };

  static String _requiredString(Object? value, String key) {
    if (value is! String || value.isEmpty || value.trim() != value) {
      throw FormatException('Stored native session $key must be a string.');
    }
    return value;
  }

  static DeploymentProfileSource _profileSource(Object? value) {
    final String source = _requiredString(value, 'profile_source');
    return switch (source) {
      'enrollment' => DeploymentProfileSource.enrollment,
      _ => throw const FormatException(
          'Stored native session has an invalid profile_source.',
        ),
    };
  }
}
