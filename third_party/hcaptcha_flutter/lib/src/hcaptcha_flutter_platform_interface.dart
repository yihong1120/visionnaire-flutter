import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'hcaptcha_flutter_method_channel.dart';

abstract class HCaptchaFlutterPlatform extends PlatformInterface {
  /// Constructs a HCaptchaFlutterPlatform.
  HCaptchaFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static HCaptchaFlutterPlatform _instance = MethodChannelHCaptchaFlutter();

  /// The default instance of [HCaptchaFlutterPlatform] to use.
  ///
  /// Defaults to [MethodChannelHcaptchaFlutter].
  static HCaptchaFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [HCaptchaFlutterPlatform] when
  /// they register themselves.
  static set instance(HCaptchaFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String> show({
    required String siteKey,
    required String language,
  });

  Future<void> dismiss();
}
