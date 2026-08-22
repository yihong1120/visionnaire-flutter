import 'package:flutter/material.dart';

/// A widget that overlays a busy indicator on top of its child when [busy] is true.
///
/// This is useful for indicating loading or processing states in the UI, preventing user interaction
/// with the underlying content while the overlay is active.
class BusyOverlay extends StatelessWidget {
  /// Whether the overlay should be shown (true) or not (false).
  final bool busy;

  /// The widget over which the busy overlay will be displayed.
  final Widget child;

  /// The colour of the overlay. Defaults to a semi-transparent black if not specified.
  final Color? overlayColor;

  /// The widget to use as the busy indicator. Defaults to [CircularProgressIndicator] if not specified.
  final Widget? indicator;

  /// Creates a [BusyOverlay] widget.
  ///
  /// [busy] determines if the overlay is shown.
  /// [child] is the content to display beneath the overlay.
  /// [overlayColor] sets the overlay's background colour.
  /// [indicator] sets the widget shown as the busy indicator.
  const BusyOverlay({
    super.key,
    required this.busy,
    required this.child,
    this.overlayColor,
    this.indicator,
  });

  @override
  Widget build(BuildContext context) {
    // Use a Stack to layer the busy overlay above the child widget.
    return Stack(
      children: <Widget>[
        child,
        if (busy)
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true, // Prevents interaction with underlying widgets.
              child: Container(
                color:
                    overlayColor ?? Colors.black26, // Default overlay colour.
                alignment: Alignment.center,
                child: indicator ??
                    const CircularProgressIndicator(), // Default indicator.
              ),
            ),
          ),
      ],
    );
  }
}
