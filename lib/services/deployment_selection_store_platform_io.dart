import 'dart:io' show Platform;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'deployment_selection_store_contract.dart';

/// Creates the encrypted native selection store for iOS and Android only.
DeploymentSelectionStore createNativeDeploymentSelectionStore() {
  if (!Platform.isIOS && !Platform.isAndroid) {
    throw UnsupportedError(
      'Deployment enrollment is available only on iOS and Android.',
    );
  }
  return SecureDeploymentSelectionStore();
}

/// Native deployment selection backed by Keychain / Android Keystore storage.
final class SecureDeploymentSelectionStore implements DeploymentSelectionStore {
  SecureDeploymentSelectionStore({DeploymentSelectionKeyValueStore? storage})
      : _storage = storage ?? const _FlutterSecureSelectionStorage();

  static const String _storageKey = 'visionnaire.deployment_selection.v1';

  final DeploymentSelectionKeyValueStore _storage;

  @override
  Future<String?> readDeploymentId() async {
    final String? value = await _storage.read(key: _storageKey);
    return value == null ? null : requireCanonicalDeploymentId(value);
  }

  @override
  Future<void> writeDeploymentId(String deploymentId) async {
    await _storage.write(
      key: _storageKey,
      value: requireCanonicalDeploymentId(deploymentId),
    );
  }

  @override
  Future<void> clear() => _storage.delete(key: _storageKey);
}

final class _FlutterSecureSelectionStorage
    implements DeploymentSelectionKeyValueStore {
  const _FlutterSecureSelectionStorage();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'visionnaire.deployment_selection',
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
    aOptions: AndroidOptions(
      resetOnError: false,
      storageNamespace: 'visionnaire.deployment_selection',
    ),
  );

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}
