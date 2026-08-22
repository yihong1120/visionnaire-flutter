import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/models/deployment_profile.dart';
import 'package:visionnaire/pages/deployment_enrollment_page.dart';
import 'package:visionnaire/services/deployment_enrollment_client.dart';
import 'package:visionnaire/services/deployment_profile_service.dart';
import 'package:visionnaire/services/deployment_registry_client.dart';
import 'package:visionnaire/services/deployment_selection_store.dart';

const String _deploymentId = '0000000a-0000-4000-8000-000000000001';
const String _tenantId = '0000000a-0000-4000-8000-000000000002';

void main() {
  tearDown(DeploymentProfileService.resetSharedForTesting);

  testWidgets('accepts only an activation code, never a server URL',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DeploymentEnrollmentPage(onCompleted: _completed),
      ),
    );

    expect(find.text('Activation code'), findsOneWidget);
    expect(find.textContaining('API URL'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('requires a non-empty activation code',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DeploymentEnrollmentPage(onCompleted: _completed),
      ),
    );

    await tester.tap(find.text('Activate'));
    await tester.pump();

    expect(find.text('Enter an activation code.'), findsOneWidget);
  });

  testWidgets('activates only after signed registry verification',
      (WidgetTester tester) async {
    final _MemorySelectionStore selectionStore = _MemorySelectionStore();
    DeploymentProfileService.replaceSharedForTesting(
      DeploymentProfileService(
        enrollment: _FixedEnrollment(_deploymentId),
        selectionStore: selectionStore,
        registry: _FixedRegistry(),
        isWeb: false,
        isDebug: false,
      ),
    );
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: DeploymentEnrollmentPage(
          onCompleted: () async => completed = true,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'company-code');
    await tester.tap(find.text('Activate'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(selectionStore.deploymentId, _deploymentId);
  });

  testWidgets('does not expose a rejected code as a server error',
      (WidgetTester tester) async {
    DeploymentProfileService.replaceSharedForTesting(
      DeploymentProfileService(
        enrollment: _RejectedEnrollment(),
        selectionStore: _MemorySelectionStore(),
        registry: _FixedRegistry(),
        isWeb: false,
        isDebug: false,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: DeploymentEnrollmentPage(onCompleted: _completed),
      ),
    );

    await tester.enterText(find.byType(TextField), 'invalid-code');
    await tester.tap(find.text('Activate'));
    await tester.pumpAndSettle();

    expect(
      find.text('This activation code is invalid or has expired.'),
      findsOneWidget,
    );
    expect(find.text('Code: invalid-code'), findsNothing);
  });

  testWidgets('recovery is retry-only and cannot submit an activation code',
      (WidgetTester tester) async {
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: DeploymentRecoveryPage(
          initialErrorCode: 'registry_unavailable',
          onRetry: () async => retries += 1,
        ),
      ),
    );

    expect(find.text('Connection unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Activation code'), findsNothing);
    expect(find.text('Activate'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(retries, 1);
  });
}

Future<void> _completed() async {}

final class _MemorySelectionStore implements DeploymentSelectionStore {
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

final class _FixedEnrollment implements DeploymentEnrollment {
  const _FixedEnrollment(this.deploymentId);

  final String deploymentId;

  @override
  Future<String> exchange(String enrollmentCode) async => deploymentId;
}

final class _RejectedEnrollment implements DeploymentEnrollment {
  @override
  Future<String> exchange(String enrollmentCode) {
    throw const DeploymentEnrollmentException('enrollment_code_rejected');
  }
}

final class _FixedRegistry implements DeploymentRegistry {
  @override
  Future<DeploymentProfile> resolve(
    DeploymentSelector selector, {
    required bool allowInsecureLoopback,
  }) async {
    return DeploymentProfile.fromRegistryConfiguration(
      <String, Object?>{
        'schema_version': 1,
        'deployment_id': selector.deploymentId,
        'tenant_id': _tenantId,
        'api_base_url': 'https://api.example.test/hazard/api',
        'config_revision': 1,
      },
      selector: selector,
      allowInsecureLoopback: allowInsecureLoopback,
      issuedAt: 1800000000,
      expiresAt: 1800003600,
    );
  }
}
