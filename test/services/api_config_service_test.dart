import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionnaire/services/api_config_service.dart';

import '../test_support/deployment_profile_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    installEnrollmentDeploymentProfile(debug: true);
  });

  tearDown(() {
    resetDeploymentProfile();
  });

  test('resolves every native route from the active deployment profile',
      () async {
    await ApiConfigService.initialize();

    final Map<String, String> urls = await ApiConfigService.getAllApiUrls();

    expect(urls.keys, <String>[
      for (final ApiEndpoint endpoint in ApiConfigService.endpoints)
        endpoint.key,
    ]);
    expect(urls['management'], endsWith('/db_management'));
    expect(urls['fcm'], endsWith('/fcm'));
  }, skip: kIsWeb);

  test('runtime endpoint overrides follow the native debug-build policy', () {
    expect(
        ApiConfigService.allowsRuntimeEndpointOverrides, !kIsWeb && kDebugMode);
  });

  test('debug native builds permit a runtime endpoint override', () async {
    await ApiConfigService.initialize();

    expect(ApiConfigService.allowsRuntimeEndpointOverrides, isTrue);
    await ApiConfigService.setRuntimeEndpointOverride(
      'chat',
      'https://chat.internal.example/api',
    );

    expect(
      await ApiConfigService.getApiUrl('chat'),
      'https://chat.internal.example/api',
    );
  }, skip: kIsWeb);

  test('deployment re-activation clears every debug endpoint override',
      () async {
    await ApiConfigService.initialize();
    await ApiConfigService.setRuntimeEndpointOverride(
      'chat',
      'https://chat.internal.example/api',
    );
    await ApiConfigService.setRuntimeEndpointOverride(
      'management',
      'https://management.internal.example/api',
    );

    await ApiConfigService.clearRuntimeEndpointOverridesForDeploymentChange();

    expect(
      await ApiConfigService.getApiUrl('chat'),
      endsWith('/chat'),
    );
    expect(
      await ApiConfigService.getApiUrl('management'),
      endsWith('/db_management'),
    );
  }, skip: kIsWeb);

  test('rejects malformed debug overrides instead of guessing a URL', () async {
    await ApiConfigService.initialize();

    await expectLater(
      ApiConfigService.setRuntimeEndpointOverride('chat', 'not-a-url'),
      throwsA(isA<ApiConfigurationException>()),
    );
  }, skip: kIsWeb);

  test('rejects unknown service keys', () async {
    await expectLater(
      ApiConfigService.getApiUrl('unknown-service'),
      throwsA(isA<ApiConfigurationException>()),
    );
  });
}
