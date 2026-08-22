import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/models/deployment_profile.dart';

const String _deploymentId = '00000000-0000-4000-8000-000000000001';
const String _tenantId = '00000000-0000-4000-8000-000000000002';
const int _issuedAt = 1800000000;
const int _expiresAt = 1800003600;

const Map<String, Object?> _registryConfiguration = <String, Object?>{
  'schema_version': 1,
  'deployment_id': _deploymentId,
  'tenant_id': _tenantId,
  'api_base_url': 'https://api.company-a.example/hazard/api',
  'config_revision': 7,
};

void main() {
  group('DeploymentSelector', () {
    test('accepts a canonical deployment identifier from enrollment', () {
      final DeploymentSelector selector =
          DeploymentSelector.fromEnrollment(_deploymentId);

      expect(selector.deploymentId, _deploymentId);
      expect(selector.source, DeploymentProfileSource.enrollment);
    });

    test('rejects a non-canonical enrollment deployment identifier', () {
      expect(
        () => DeploymentSelector.fromEnrollment(
          '0000000A-0000-4000-8000-000000000001',
        ),
        throwsA(isA<DeploymentProfileFormatException>()),
      );
      expect(
        () => DeploymentSelector.fromEnrollment('deployment-a'),
        throwsA(isA<DeploymentProfileFormatException>()),
      );
    });
  });

  group('DeploymentProfile', () {
    final DeploymentSelector selector =
        DeploymentSelector.fromEnrollment(_deploymentId);

    test('parses a registry profile selected by company enrollment', () {
      final DeploymentProfile profile =
          DeploymentProfile.fromRegistryConfiguration(
        _registryConfiguration,
        selector: selector,
        allowInsecureLoopback: false,
        issuedAt: _issuedAt,
        expiresAt: _expiresAt,
      );

      expect(profile.schemaVersion, DeploymentProfile.currentSchemaVersion);
      expect(profile.deploymentId, _deploymentId);
      expect(profile.tenantId, _tenantId);
      expect(
        profile.apiBaseUri,
        Uri.parse('https://api.company-a.example/hazard/api'),
      );
      expect(profile.revision, 7);
      expect(profile.source, DeploymentProfileSource.enrollment);
    });

    test('rejects an unknown or missing registry profile field', () {
      expect(
        () => DeploymentProfile.fromRegistryConfiguration(
          <String, Object?>{
            ..._registryConfiguration,
            'unexpected': true,
          },
          selector: selector,
          allowInsecureLoopback: false,
          issuedAt: _issuedAt,
          expiresAt: _expiresAt,
        ),
        throwsA(isA<DeploymentProfileFormatException>()),
      );
    });

    test('requires an integer config_revision', () {
      expect(
        () => DeploymentProfile.fromRegistryConfiguration(
          <String, Object?>{
            ..._registryConfiguration,
            'config_revision': '7',
          },
          selector: selector,
          allowInsecureLoopback: false,
          issuedAt: _issuedAt,
          expiresAt: _expiresAt,
        ),
        throwsA(isA<DeploymentProfileFormatException>()),
      );
    });

    test('rejects a registry deployment different from the selector', () {
      expect(
        () => DeploymentProfile.fromRegistryConfiguration(
          <String, Object?>{
            ..._registryConfiguration,
            'deployment_id': 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
          },
          selector: selector,
          allowInsecureLoopback: false,
          issuedAt: _issuedAt,
          expiresAt: _expiresAt,
        ),
        throwsA(isA<DeploymentProfileFormatException>()),
      );
    });

    test('requires HTTPS for non-loopback API hosts', () {
      expect(
        () => DeploymentProfile.fromRegistryConfiguration(
          <String, Object?>{
            ..._registryConfiguration,
            'api_base_url': 'http://api.company-a.example/hazard/api',
          },
          selector: selector,
          allowInsecureLoopback: true,
          issuedAt: _issuedAt,
          expiresAt: _expiresAt,
        ),
        throwsA(isA<DeploymentProfileFormatException>()),
      );
    });

    test('allows HTTP loopback only in a debug profile', () {
      const String loopback = 'http://127.0.0.1:8080/hazard/api';
      final DeploymentProfile profile =
          DeploymentProfile.fromRegistryConfiguration(
        <String, Object?>{
          ..._registryConfiguration,
          'api_base_url': loopback,
        },
        selector: selector,
        allowInsecureLoopback: true,
        issuedAt: _issuedAt,
        expiresAt: _expiresAt,
      );

      expect(profile.apiBaseUri, Uri.parse(loopback));
      expect(
        () => DeploymentProfile.fromRegistryConfiguration(
          <String, Object?>{
            ..._registryConfiguration,
            'api_base_url': loopback,
          },
          selector: selector,
          allowInsecureLoopback: false,
          issuedAt: _issuedAt,
          expiresAt: _expiresAt,
        ),
        throwsA(isA<DeploymentProfileFormatException>()),
      );
    });

    test('web BFF profile does not require an external API URI', () {
      final DeploymentProfile profile = DeploymentProfile.webBff(
        deploymentId: 'web-build',
        tenantId: 'default',
        revision: 0,
      );

      expect(profile.source, DeploymentProfileSource.webBff);
      expect(profile.apiBaseUri, isNull);
    });
  });

  test('rejects API roots with credentials, queries, or fragments', () {
    final DeploymentSelector selector =
        DeploymentSelector.fromEnrollment(_deploymentId);
    for (final String apiBaseUrl in <String>[
      'https://user:pass@api.company-a.example/hazard/api',
      'https://api.company-a.example/hazard/api?tenant=company-a',
      'https://api.company-a.example/hazard/api#section',
    ]) {
      expect(
        () => DeploymentProfile.fromRegistryConfiguration(
          <String, Object?>{
            ..._registryConfiguration,
            'api_base_url': apiBaseUrl,
          },
          selector: selector,
          allowInsecureLoopback: false,
          issuedAt: _issuedAt,
          expiresAt: _expiresAt,
        ),
        throwsA(isA<DeploymentProfileFormatException>()),
      );
    }
  });

  test('requires a canonical API root before it becomes signed state', () {
    final DeploymentSelector selector =
        DeploymentSelector.fromEnrollment(_deploymentId);
    for (final String apiBaseUrl in <String>[
      'HTTPS://api.company-a.example/hazard/api',
      'https://API.company-a.example/hazard/api',
      'https://api.company-a.example:443/hazard/api',
      'https://api.company-a.example/hazard/api/',
      'https://api.company-a.example/hazard//api',
      'https://api.company-a.example/hazard/../api',
    ]) {
      expect(
        () => DeploymentProfile.fromRegistryConfiguration(
          <String, Object?>{
            ..._registryConfiguration,
            'api_base_url': apiBaseUrl,
          },
          selector: selector,
          allowInsecureLoopback: false,
          issuedAt: _issuedAt,
          expiresAt: _expiresAt,
        ),
        throwsA(isA<DeploymentProfileFormatException>()),
        reason: apiBaseUrl,
      );
    }
  });
}
