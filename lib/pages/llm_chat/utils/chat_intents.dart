import 'package:flutter/widgets.dart';

// Intent used to trigger sending the message via keyboard shortcuts.
class SendMessageIntent extends Intent {
  const SendMessageIntent();
}

// Intent used to insert a newline explicitly (e.g., Shift+Enter)
class NewlineIntent extends Intent {
  const NewlineIntent();
}
