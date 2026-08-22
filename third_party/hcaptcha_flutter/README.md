# HCaptcha for Flutter

[![Pub Version](https://img.shields.io/pub/v/hcaptcha_flutter)](https://pub.dev/packages/hcaptcha_flutter)

## Getting Started

```dart
final token = await HCaptchaFlutter.show(
  siteKey: 'your site key',
  language: 'en',
);
```

`show` completes with the response token. It throws a `PlatformException` if
the challenge fails or is dismissed. Call `HCaptchaFlutter.dismiss()` to cancel
an in-flight challenge.
