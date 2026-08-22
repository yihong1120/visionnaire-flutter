import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'hcaptcha_flutter_platform_interface.dart';

/// An implementation of [HCaptchaFlutterPlatform] that uses method channels.
class MethodChannelHCaptchaFlutter extends HCaptchaFlutterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel(
    'plugins.kjxbyz.com/hcaptcha_flutter_plugin',
  );

  @override
  Future<String> show({
    required String siteKey,
    required String language,
  }) async {
    final token = await methodChannel.invokeMethod<String>(
      'show',
      <String, String>{
        'siteKey': siteKey,
        'language': language,
      },
    );
    if (token == null || token.isEmpty) {
      throw PlatformException(
        code: 'invalid_response',
        message: 'hCaptcha returned an empty token.',
      );
    }
    return token;
  }

  @override
  Future<void> dismiss() {
    return methodChannel.invokeMethod<void>('dismiss');
  }
}
