import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/services/deployment_selection_store.dart';

const String _deploymentId = '0000000a-0000-4000-8000-000000000001';

void main() {
  test('stores exactly one canonical deployment ID', () async {
    final _MemoryStore persistence = _MemoryStore();
    final SecureDeploymentSelectionStore store =
        SecureDeploymentSelectionStore(storage: persistence);

    await store.writeDeploymentId(_deploymentId);

    expect(await store.readDeploymentId(), _deploymentId);
    expect(
      persistence.values,
      const <String, String>{
        'visionnaire.deployment_selection.v1': _deploymentId,
      },
    );
  });

  test('refuses malformed values before storing or returning them', () async {
    final _MemoryStore persistence = _MemoryStore();
    final SecureDeploymentSelectionStore store =
        SecureDeploymentSelectionStore(storage: persistence);

    await expectLater(
      store.writeDeploymentId(_deploymentId.toUpperCase()),
      throwsA(
        isA<DeploymentSelectionStoreException>().having(
          (DeploymentSelectionStoreException error) => error.code,
          'code',
          'invalid_deployment_id',
        ),
      ),
    );
    expect(persistence.values, isEmpty);

    persistence.values['visionnaire.deployment_selection.v1'] = 'not-a-uuid';
    await expectLater(
      store.readDeploymentId(),
      throwsA(
        isA<DeploymentSelectionStoreException>().having(
          (DeploymentSelectionStoreException error) => error.code,
          'code',
          'invalid_deployment_id',
        ),
      ),
    );
  });

  test('clears the persisted selection', () async {
    final _MemoryStore persistence = _MemoryStore();
    final SecureDeploymentSelectionStore store =
        SecureDeploymentSelectionStore(storage: persistence);
    await store.writeDeploymentId(_deploymentId);

    await store.clear();

    expect(await store.readDeploymentId(), isNull);
    expect(persistence.values, isEmpty);
  });
}

final class _MemoryStore implements DeploymentSelectionKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}
