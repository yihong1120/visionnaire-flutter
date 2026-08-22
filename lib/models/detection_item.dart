import 'package:flutter/material.dart';

/// Represents a single detected item with its bounding box and label.
class DetectionItem {
  /// The bounding box of the detected item.
  final Rect rect;

  /// The label of the detected item (e.g., 'person', 'car').
  final String label;

  /// Creates a [DetectionItem].
  const DetectionItem({
    required this.rect,
    required this.label,
  });
}
