import 'dart:typed_data';
import 'package:flutter/material.dart';

/// A general-purpose image display widget supporting watermark toggling, deletion,
/// checkbox selection, and tag labelling.
///
/// Displays either the original or stamped image, with optional checkbox, tag, and delete button.
class ImageBox extends StatefulWidget {
  /// The raw image bytes to display when [showDate] is false.
  final Uint8List? rawBytes;

  /// The stamped image bytes to display when [showDate] is true.
  final Uint8List? stampedBytes;

  /// The network image URL (used when rawBytes and stampedBytes are null).
  final String? imageUrl;

  /// Whether to show the stamped image (true) or the raw image (false).
  final bool showDate;

  /// Whether to display a checkbox above the image.
  final bool showCheckbox;

  /// The value of the checkbox (checked/unchecked/null).
  final bool? checkboxValue;

  /// Callback when the checkbox value changes.
  final ValueChanged<bool?>? onCheckboxChanged;

  /// Callback when the delete button is pressed.
  final VoidCallback? onDelete;

  /// Optional tag label to display in the top-left corner of the image.
  final String? tag;

  /// The width of the image box.
  final double width;

  /// The height of the image box.
  final double height;

  /// Callback when the image box is tapped.
  final VoidCallback? onTap;

  /// Lazily builds stamped bytes when [showDate] is true and [stampedBytes] is null.
  final Future<Uint8List> Function()? stampedBytesBuilder;

  /// Distinguishes lazy stamped output when the source image or date text changes.
  final Object? stampCacheKey;

  /// Creates an [ImageBox] widget.
  ///
  /// [rawBytes] and [stampedBytes] are required. [showDate] determines which image is shown.
  /// [showCheckbox], [checkboxValue], [onCheckboxChanged], [onDelete], [tag], [width], [height], and [onTap] are optional.
  const ImageBox({
    super.key,
    this.rawBytes,
    this.stampedBytes,
    this.imageUrl,
    required this.showDate,
    this.showCheckbox = false,
    this.checkboxValue,
    this.onCheckboxChanged,
    this.onDelete,
    this.tag,
    this.width = 120,
    this.height = 90,
    this.onTap,
    this.stampedBytesBuilder,
    this.stampCacheKey,
  });

  @override
  State<ImageBox> createState() => _ImageBoxState();
}

class _ImageBoxState extends State<ImageBox> {
  Future<Uint8List>? _lazyStampedBytes;
  Object? _stampCacheKey;

  @override
  void didUpdateWidget(covariant ImageBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool cacheChanged = oldWidget.stampCacheKey != widget.stampCacheKey ||
        oldWidget.rawBytes != widget.rawBytes ||
        oldWidget.stampedBytes != widget.stampedBytes ||
        oldWidget.showDate != widget.showDate;
    if (cacheChanged) {
      _lazyStampedBytes = null;
      _stampCacheKey = null;
    }
  }

  Future<Uint8List> _resolveStampedBytes() {
    if (_lazyStampedBytes != null && _stampCacheKey == widget.stampCacheKey) {
      return _lazyStampedBytes!;
    }
    _stampCacheKey = widget.stampCacheKey;
    _lazyStampedBytes = widget.stampedBytesBuilder!();
    return _lazyStampedBytes!;
  }

  @override
  Widget build(BuildContext context) {
    // GestureDetector allows the entire image box to be tappable.
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (widget.showCheckbox)
              Row(
                children: <Widget>[
                  Checkbox(
                    visualDensity: VisualDensity.compact,
                    value: widget.checkboxValue,
                    onChanged: widget.onCheckboxChanged,
                  ),
                  const Text('顯示', style: TextStyle(fontSize: 10)),
                ],
              ),
            Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // Display either the stamped or raw image based on [showDate].
                  if (widget.imageUrl != null && widget.rawBytes == null)
                    Image.network(
                      widget.imageUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image),
                    )
                  else if (widget.showDate &&
                      widget.stampedBytes == null &&
                      widget.stampedBytesBuilder != null)
                    FutureBuilder<Uint8List>(
                      future: _resolveStampedBytes(),
                      builder: (
                        BuildContext context,
                        AsyncSnapshot<Uint8List> snapshot,
                      ) {
                        return Image.memory(
                          snapshot.data ?? widget.rawBytes!,
                          fit: BoxFit.contain,
                        );
                      },
                    )
                  else
                    Image.memory(
                      (widget.showDate && widget.stampedBytes != null)
                          ? widget.stampedBytes!
                          : widget.rawBytes!,
                      fit: BoxFit.contain,
                    ),
                  // Optional tag label in the top-left corner.
                  if (widget.tag != null)
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(
                            vertical: 2, horizontal: 6),
                        child: Text(widget.tag!,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)),
                      ),
                    ),
                  // Optional delete button in the top-right corner.
                  if (widget.onDelete != null)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: InkWell(
                        onTap: widget.onDelete,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          color: Colors.black45,
                          child: const Icon(Icons.close,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
