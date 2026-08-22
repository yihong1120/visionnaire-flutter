import 'hcaptcha_flutter_platform_interface.dart';

class HCaptchaFlutter {
  static Future<String> show({
    required String siteKey,
    required String language,
  }) =>
      HCaptchaFlutterPlatform.instance.show(
        siteKey: siteKey,
        language: language,
      );

  static Future<void> dismiss() => HCaptchaFlutterPlatform.instance.dismiss();
}
