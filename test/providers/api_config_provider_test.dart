import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionnaire/providers/api_config_provider.dart';
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

  test('loads the active deployment routes once', () async {
    await ApiConfigService.initialize();
    final ApiConfigProvider provider = ApiConfigProvider();

    expect(provider.apiUrls, isEmpty);
    await provider.initialize();

    expect(
        provider.apiUrls.keys,
        containsAll(<String>[
          for (final ApiEndpoint endpoint in ApiConfigService.endpoints)
            endpoint.key,
        ]));
    expect(
      provider.getApiUrl('management'),
      await ApiConfigService.getApiUrl('management'),
    );
  });

  test('does not fabricate a route that was not resolved', () {
    final ApiConfigProvider provider = ApiConfigProvider();

    expect(
      () => provider.getApiUrl('unknown'),
      throwsStateError,
    );
  });
}
