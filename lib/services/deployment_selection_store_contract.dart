import '../models/deployment_profile.dart';

/// Persists the one native deployment selected by a completed enrollment.
///
/// Only the canonical deployment identifier is retained. The signed registry
/// remains the sole source for the API endpoint and tenant configuration.
abstract interface class DeploymentSelectionStore {
  Future<String?> readDeploymentId();

  Future<void> writeDeploymentId(String deploymentId);

  Future<void> clear();
}

/// The small subset of secure storage used by [SecureDeploymentSelectionStore].
///
/// Keeping this adapter narrow gives tests an in-memory implementation while
/// the native implementation uses `flutter_secure_storage`.
abstract interface class DeploymentSelectionKeyValueStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

/// A typed failure for a corrupt or invalid persisted deployment selection.
final class DeploymentSelectionStoreException implements Exception {
  const DeploymentSelectionStoreException(this.code);

  final String code;

  @override
  String toString() => 'DeploymentSelectionStoreException: $code';
}

String requireCanonicalDeploymentId(String value) {
  try {
    return DeploymentProfileContract.requiredUuid(value, 'deployment_id');
  } on DeploymentProfileFormatException {
    throw const DeploymentSelectionStoreException('invalid_deployment_id');
  }
}
