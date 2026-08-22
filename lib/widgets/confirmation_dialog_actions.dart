import 'package:flutter/material.dart';

/// Builds a standard cancel/confirm button pair for [AlertDialog.actions].
List<Widget> buildConfirmationDialogActions({
  required BuildContext context,
  required String cancelLabel,
  required String confirmLabel,
  IconData? confirmIcon,
  bool isDestructive = false,
  Object? cancelResult = false,
  Object? confirmResult = true,
}) {
  final ButtonStyle? confirmStyle = isDestructive
      ? ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        )
      : null;

  void onCancel() => Navigator.pop(context, cancelResult);
  void onConfirm() => Navigator.pop(context, confirmResult);

  return <Widget>[
    TextButton(
      onPressed: onCancel,
      child: Text(cancelLabel),
    ),
    if (confirmIcon == null)
      ElevatedButton(
        onPressed: onConfirm,
        style: confirmStyle,
        child: Text(confirmLabel),
      )
    else
      ElevatedButton.icon(
        onPressed: onConfirm,
        style: confirmStyle,
        icon: Icon(confirmIcon),
        label: Text(confirmLabel),
      ),
  ];
}
