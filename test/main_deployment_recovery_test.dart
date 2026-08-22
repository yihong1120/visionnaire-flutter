import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/main.dart' as application;
import 'package:visionnaire/models/deployment_profile.dart';
import 'package:visionnaire/pages/deployment_enrollment_page.dart';
import 'package:visionnaire/services/deployment_profile_service.dart';
import 'package:visionnaire/services/deployment_registry_client.dart';
import 'package:visionnaire/services/deployment_selection_store.dart';

const String _deploymentId = '0000000a-0000-4000-8000-000000000001';

void main() {
  tearDown(DeploymentProfileService.resetSharedForTesting);

  testWidgets(
      'startup recovers an existing deployment without exposing activation input',
      (WidgetTester tester) async {
    DeploymentProfileService.replaceSharedForTesting(
      DeploymentProfileService(
        selectionStore: _StoredSelection(),
        registry: _UnavailableRegistry(),
        isWeb: false,
        isDebug: false,
      ),
    );

    await application.main();
    await tester.pumpAndSettle();

    expect(find.byType(DeploymentRecoveryPage), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Activation code'), findsNothing);
    expect(find.text('Activate'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });
}

final class _StoredSelection implements DeploymentSelectionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readDeploymentId() async => _deploymentId;

  @override
  Future<void> writeDeploymentId(String deploymentId) async {}
}

final class _UnavailableRegistry implements DeploymentRegistry {
  @override
  Future<DeploymentProfile> resolve(
    DeploymentSelector selector, {
    required bool allowInsecureLoopback,
  }) {
    throw const DeploymentRegistryException('registry_unavailable');
  }
}
