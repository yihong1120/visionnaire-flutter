import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Enables desktop-web style text selection for information content.
///
/// Flutter Web renders most text through Flutter rather than native HTML text,
/// so wrapping information regions with [SelectionArea] is required if users
/// should be able to highlight and copy text like a regular web app.
class WebSelectableContent extends StatelessWidget {
  const WebSelectableContent({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !enabled) return child;
    return SelectionArea(child: child);
  }
}

/// Prevents text selection inside controls embedded in a selectable region.
class WebNonSelectableContent extends StatelessWidget {
  const WebNonSelectableContent({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;
    return SelectionContainer.disabled(child: child);
  }
}
