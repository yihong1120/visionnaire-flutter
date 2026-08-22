import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

void showManagementSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: backgroundColor,
    ),
  );
}

void showManagementErrorSnackBar(BuildContext context, Object error) {
  showManagementSnackBar(
    context,
    AppLocalizations.of(context)!.errorMessage(error.toString()),
  );
}
