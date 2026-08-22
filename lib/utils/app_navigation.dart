import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

bool get _isMobileApp {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
}

void appPushOrGo(
  BuildContext context,
  String location, {
  Object? extra,
}) {
  if (_isMobileApp) {
    context.push(location, extra: extra);
    return;
  }
  context.go(location, extra: extra);
}

void appBackOrGo(BuildContext context, String fallbackLocation) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
    return;
  }

  if (context.canPop()) {
    context.pop();
    return;
  }

  context.go(fallbackLocation);
}
