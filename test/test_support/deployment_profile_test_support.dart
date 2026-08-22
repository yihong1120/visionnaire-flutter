import 'package:visionnaire/models/deployment_profile.dart';
import 'package:visionnaire/services/deployment_profile_service.dart';
import 'package:visionnaire/services/deployment_registry_client.dart';
import 'package:visionnaire/services/deployment_selection_store.dart';

const String _testDeploymentId = '00000000-0000-4000-8000-000000000001';
const String _testTenantId = '00000000-0000-4000-8000-000000000002';

void installEnrollmentDeploymentProfile({required bool debug}) {
  DeploymentProfileService.replaceSharedForTesting(
    DeploymentProfileService(
      selectionStore: _TestSelectionStore(_testDeploymentId),
      registry: _TestRegistry(),
      isWeb: false,
      isDebug: debug,
    ),
  );
}

void resetDeploymentProfile() {
  DeploymentProfileService.resetSharedForTesting();
}

final class _TestSelectionStore implements DeploymentSelectionStore {
  _TestSelectionStore(this.deploymentId);

  String? deploymentId;

  @override
  Future<void> clear() async {
    deploymentId = null;
  }

  @override
  Future<String?> readDeploymentId() async => deploymentId;

  @override
  Future<void> writeDeploymentId(String value) async {
    deploymentId = value;
  }
}

final class _TestRegistry implements DeploymentRegistry {
  @override
  Future<DeploymentProfile> resolve(
    DeploymentSelector selector, {
    required bool allowInsecureLoopback,
  }) {
    return Future<DeploymentProfile>.value(
      DeploymentProfile.fromRegistryConfiguration(
        <String, Object?>{
          'schema_version': 1,
          'deployment_id': selector.deploymentId,
          'tenant_id': _testTenantId,
          'api_base_url': 'https://api.test.example/hazard/api',
          'config_revision': 1,
        },
        selector: selector,
        allowInsecureLoopback: allowInsecureLoopback,
        issuedAt: 4102444800,
        expiresAt: 4102448400,
      ),
    );
  }
}
