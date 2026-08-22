import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as google_web;

Widget buildGoogleSignInButton({
  required String locale,
  double minimumWidth = 320,
}) {
  return google_web.renderButton(
    configuration: google_web.GSIButtonConfiguration(
      type: google_web.GSIButtonType.standard,
      theme: google_web.GSIButtonTheme.outline,
      size: google_web.GSIButtonSize.large,
      text: google_web.GSIButtonText.continueWith,
      shape: google_web.GSIButtonShape.pill,
      logoAlignment: google_web.GSIButtonLogoAlignment.left,
      minimumWidth: minimumWidth.clamp(180, 400).toDouble(),
      locale: locale,
    ),
  );
}
