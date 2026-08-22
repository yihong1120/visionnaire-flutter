import 'package:flutter/widgets.dart';

class HCaptchaChallenge extends StatelessWidget {
  const HCaptchaChallenge({
    super.key,
    required this.siteKey,
    required this.onTokenChanged,
    this.onError,
    this.resetCounter = 0,
  });

  final String siteKey;
  final ValueChanged<String?> onTokenChanged;
  final ValueChanged<String?>? onError;
  final int resetCounter;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
