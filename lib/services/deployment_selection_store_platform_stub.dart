import 'deployment_selection_store_contract.dart';

/// Web deployment selection is deliberately handled by the same-origin BFF.
/// There is no browser persistence for a native deployment identifier.
DeploymentSelectionStore createNativeDeploymentSelectionStore() {
  throw UnsupportedError(
    'Deployment enrollment is available only on iOS and Android.',
  );
}

/// Exists only so shared code can type-check on Flutter Web. It never reads or
/// writes browser storage.
final class SecureDeploymentSelectionStore implements DeploymentSelectionStore {
  SecureDeploymentSelectionStore({DeploymentSelectionKeyValueStore? storage});

  Never _unsupported() => throw UnsupportedError(
        'Deployment enrollment is available only on iOS and Android.',
      );

  @override
  Future<String?> readDeploymentId() => Future<String?>.error(_unsupported());

  @override
  Future<void> writeDeploymentId(String deploymentId) =>
      Future<void>.error(_unsupported());

  @override
  Future<void> clear() => Future<void>.error(_unsupported());
}
