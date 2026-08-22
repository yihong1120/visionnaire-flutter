import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/models/auth_user_snapshot.dart';
import 'package:visionnaire/models/deployment_profile.dart';
import 'package:visionnaire/models/native_session_envelope.dart';

const String _deploymentId = '00000000-0000-4000-8000-000000000001';
const String _tenantId = '00000000-0000-4000-8000-000000000002';

void main() {
  final DeploymentProfile profile = _profile(
    DeploymentSelector.fromEnrollment(_deploymentId),
  );
  const AuthUserSnapshot user = AuthUserSnapshot(
    username: 'alice',
    role: 'admin',
    features: <String>['file_manage'],
  );

  test('binds a native refresh session to one exact profile', () {
    final NativeSessionEnvelope envelope = NativeSessionEnvelope.create(
      user: user,
      refreshToken: 'refresh-token',
      deploymentProfile: profile,
    );

    final Map<String, Object?> json = envelope.toJson();
    expect(json, containsPair('version', 8));
    expect(json, containsPair('profile_source', 'enrollment'));
    expect(envelope.matches(profile), isTrue);
    expect(NativeSessionEnvelope.fromJson(json).matches(profile), isTrue);
  });

  test('rejects a session when API base or revision changes', () {
    final NativeSessionEnvelope envelope = NativeSessionEnvelope.create(
      user: user,
      refreshToken: 'refresh-token',
      deploymentProfile: profile,
    );
    final DeploymentProfile changedApi = _profile(
      DeploymentSelector.fromEnrollment(_deploymentId),
      apiBaseUrl: 'https://api-two.company-a.example/hazard/api',
    );
    final DeploymentProfile changedRevision = _profile(
      DeploymentSelector.fromEnrollment(_deploymentId),
      revision: 5,
    );

    expect(envelope.matches(changedApi), isFalse);
    expect(envelope.matches(changedRevision), isFalse);
  });

  test('rejects unknown stored-session fields', () {
    final Map<String, Object?> json = NativeSessionEnvelope.create(
      user: user,
      refreshToken: 'refresh-token',
      deploymentProfile: profile,
    ).toJson();

    expect(
      () => NativeSessionEnvelope.fromJson(<String, Object?>{
        ...json,
        'legacy_api_url': 'https://unexpected.example',
      }),
      throwsFormatException,
    );
  });

  test('rejects malformed stored deployment bindings', () {
    final Map<String, Object?> json = NativeSessionEnvelope.create(
      user: user,
      refreshToken: 'refresh-token',
      deploymentProfile: profile,
    ).toJson();

    for (final Map<String, Object?> malformed in <Map<String, Object?>>[
      <String, Object?>{
        ...json,
        'deployment_id': 'not-a-uuid',
      },
      <String, Object?>{
        ...json,
        'tenant_id': '00000000-0000-6000-8000-000000000002',
      },
      <String, Object?>{
        ...json,
        'api_base_url': 'https://api.company-a.example/hazard/api/',
      },
    ]) {
      expect(
        () => NativeSessionEnvelope.fromJson(malformed),
        throwsFormatException,
      );
    }
  });
}

DeploymentProfile _profile(
  DeploymentSelector selector, {
  String apiBaseUrl = 'https://api.company-a.example/hazard/api',
  int revision = 4,
}) {
  return DeploymentProfile.fromRegistryConfiguration(
    <String, Object?>{
      'schema_version': 1,
      'deployment_id': _deploymentId,
      'tenant_id': _tenantId,
      'api_base_url': apiBaseUrl,
      'config_revision': revision,
    },
    selector: selector,
    allowInsecureLoopback: false,
    issuedAt: 1800000000,
    expiresAt: 1800003600,
  );
}
