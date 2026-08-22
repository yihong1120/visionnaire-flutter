import 'package:flutter_test/flutter_test.dart';

import '../../tool/generate_firebase_messaging_config.dart';

void main() {
  test('writes an explicit disabled configuration', () {
    const String source = '''
      {"FIREBASE_WEB_MESSAGING_ENABLED":"false"}
    ''';

    final FirebaseMessagingWorkerConfig config =
        FirebaseMessagingWorkerConfig.fromJson(source);

    expect(config.enabled, isFalse);
    expect(
      config.toJavaScript(),
      'self.__FIREBASE_MESSAGING_CONFIG__ = null;\n',
    );
  });

  test('writes only the allowlisted Firebase fields', () {
    const String source = '''
      {
        "FIREBASE_WEB_MESSAGING_ENABLED":"true",
        "FIREBASE_WEB_API_KEY":"api-key",
        "FIREBASE_WEB_APP_ID":"app-id",
        "FIREBASE_WEB_MESSAGING_SENDER_ID":"sender-id",
        "FIREBASE_WEB_PROJECT_ID":"project-id",
        "FIREBASE_WEB_AUTH_DOMAIN":"project.example.com",
        "unexpected":"must-not-be-written"
      }
    ''';

    final FirebaseMessagingWorkerConfig config =
        FirebaseMessagingWorkerConfig.fromJson(source);

    expect(config.enabled, isTrue);
    expect(config.firebaseOptions, <String, String>{
      'apiKey': 'api-key',
      'appId': 'app-id',
      'messagingSenderId': 'sender-id',
      'projectId': 'project-id',
      'authDomain': 'project.example.com',
    });
    expect(config.toJavaScript(), isNot(contains('unexpected')));
  });

  test('requires complete string values when messaging is enabled', () {
    expect(
      () => FirebaseMessagingWorkerConfig.fromJson(
        '{"FIREBASE_WEB_MESSAGING_ENABLED":"true"}',
      ),
      throwsFormatException,
    );
    expect(
      () => FirebaseMessagingWorkerConfig.fromJson(
        '{"FIREBASE_WEB_MESSAGING_ENABLED":true}',
      ),
      throwsFormatException,
    );
  });
}
