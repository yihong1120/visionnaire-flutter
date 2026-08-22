import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionnaire/models/deployment_profile.dart';
import 'package:visionnaire/pages/api_config_page.dart';
import 'package:visionnaire/services/api_config_service.dart';
import 'package:visionnaire/services/deployment_profile_service.dart';
import 'package:visionnaire/services/deployment_registry_client.dart';
import 'package:visionnaire/services/deployment_selection_store.dart';

import '../test_helpers.dart';
import '../test_support/deployment_profile_test_support.dart';

void main() {
  setUp(() {
    if (!kIsWeb) installEnrollmentDeploymentProfile(debug: true);
  });

  tearDown(() {
    if (!kIsWeb) resetDeploymentProfile();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required bool editorEnabled,
    DeploymentReactivationIntentHandler? onReactivationRequested,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ApiConfigService.initialize();
    expect(ApiConfigService.allowsRuntimeEndpointOverrides, editorEnabled);
    await tester.pumpWidget(
      createLocalizedTestApp(
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              ApiConfigPage(
                embedded: true,
                onReactivationRequested: onReactivationRequested,
              ),
            ],
          ),
        ),
        wrapInScaffold: false,
      ),
    );
    await tester.pump();
    await TestUtils.pumpUntilFound(
      tester,
      editorEnabled ? find.byType(TextField) : find.text('Enrolled connection'),
    );
  }

  testWidgets('debug native build shows the internal endpoint editor',
      (WidgetTester tester) async {
    await pumpPage(tester, editorEnabled: true);

    expect(find.byType(TextField), findsWidgets);
    expect(find.byIcon(Icons.save_outlined), findsOneWidget);
  }, skip: kIsWeb);

  testWidgets('debug native editor saves a typed endpoint override',
      (WidgetTester tester) async {
    await pumpPage(tester, editorEnabled: true);
    const String replacement = 'https://chat.internal.example/api';

    await tester.enterText(find.byType(TextField).first, replacement);
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();

    expect(await ApiConfigService.getApiUrl('chat'), replacement);
  }, skip: kIsWeb);

  testWidgets(
      'native re-activation requires confirmation before emitting its intent',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var requestCount = 0;
    await pumpPage(
      tester,
      editorEnabled: true,
      onReactivationRequested: () async {
        requestCount += 1;
      },
    );

    expect(
        find.byKey(const Key('deployment_reactivation_card')), findsOneWidget);
    expect(requestCount, 0);

    final Finder requestButton =
        find.byKey(const Key('request_reactivation_button'));
    await tester.tap(requestButton);
    await tester.pumpAndSettle();

    expect(find.text('Re-activate this device?'), findsOneWidget);
    expect(
      find.text(
        'Confirming removes this device\'s local sign-in and connection '
        'selection. You will need a new one-time activation code and must '
        'sign in again. This page never edits a server URL.',
      ),
      findsOneWidget,
    );
    expect(requestCount, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(requestCount, 0);

    await tester.tap(requestButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Request re-activation'),
    );
    await tester.pumpAndSettle();

    expect(requestCount, 1);
    expect(
      find.text(
        'The re-activation request was handed to the controlled workflow.',
      ),
      findsOneWidget,
    );
  }, skip: kIsWeb);

  testWidgets('native build keeps re-activation disabled without a handler',
      (WidgetTester tester) async {
    await pumpPage(tester, editorEnabled: true);

    final OutlinedButton button = tester.widget<OutlinedButton>(
      find.byKey(const Key('request_reactivation_button')),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text(
        'Sign in to enable the controlled re-activation workflow.',
      ),
      findsOneWidget,
    );
  }, skip: kIsWeb);

  testWidgets(
      'native configuration failure still exposes the controlled re-activation intent',
      (WidgetTester tester) async {
    DeploymentProfileService.replaceSharedForTesting(
      DeploymentProfileService(
        selectionStore: _FailingSelectionStore(),
        registry: _FailingRegistry(),
        isWeb: false,
        isDebug: true,
      ),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      createLocalizedTestApp(
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              ApiConfigPage(
                embedded: true,
                onReactivationRequested: () async {},
              ),
            ],
          ),
        ),
        wrapInScaffold: false,
      ),
    );
    await TestUtils.pumpUntilFound(
      tester,
      find.text('Deployment configuration is unavailable.'),
    );

    expect(find.byType(TextField), findsNothing);
    expect(
        find.byKey(const Key('deployment_reactivation_card')), findsOneWidget);
    expect(
        find.byKey(const Key('request_reactivation_button')), findsOneWidget);
  }, skip: kIsWeb);

  testWidgets('web only shows read-only connection status',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      createLocalizedTestApp(
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              ApiConfigPage(
                embedded: true,
                onReactivationRequested: () async {},
              ),
            ],
          ),
        ),
        wrapInScaffold: false,
      ),
    );
    await tester.pump();
    await TestUtils.pumpUntilFound(tester, find.text('Enrolled connection'));

    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byKey(const Key('deployment_reactivation_card')), findsNothing);
    for (final ApiEndpoint endpoint in ApiConfigService.endpoints) {
      expect(find.text(endpoint.name), findsNothing);
    }
  }, skip: !kIsWeb);
}

final class _FailingSelectionStore implements DeploymentSelectionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readDeploymentId() async =>
      '00000000-0000-4000-8000-000000000001';

  @override
  Future<void> writeDeploymentId(String value) async {}
}

final class _FailingRegistry implements DeploymentRegistry {
  @override
  Future<DeploymentProfile> resolve(
    DeploymentSelector selector, {
    required bool allowInsecureLoopback,
  }) {
    throw const DeploymentRegistryException('registry_unavailable');
  }
}
