import 'package:flutter/material.dart';

/// A reusable form field widget supporting label, controller, validator, onChanged,
/// clipboard operations, and trailing icons.
class LabeledTextField extends StatelessWidget {
  /// The controller for the text field.
  final TextEditingController controller;

  /// The label text to display above the field.
  final String label;

  /// The validator function for the field value.
  final String? Function(String?)? validator;

  /// Callback when the field value changes.
  final void Function(String)? onChanged;

  /// The maximum number of lines for the text field.
  final int maxLines;

  /// Whether to use a dense layout for the field.
  final bool dense;

  /// Whether to use an outlined border for the field.
  final bool outlined;

  /// Whether the field is enabled for user input.
  final bool enabled;

  /// The keyboard type for the field (e.g., text, number).
  final TextInputType? keyboardType;

  /// Optional trailing icons to display after the field.
  final List<Widget>? trailingIcons;

  /// Creates a [LabeledTextField] widget.
  ///
  /// [controller] and [label] are required. Other parameters are optional.
  const LabeledTextField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.onChanged,
    this.maxLines = 1,
    this.dense = false,
    this.outlined = true,
    this.enabled = true,
    this.keyboardType,
    this.trailingIcons,
  });

  @override
  Widget build(BuildContext context) {
    // InputDecoration for the text field, supporting outlined and dense styles.
    final InputDecoration inputDecoration = InputDecoration(
      labelText: label,
      isDense: dense,
      border: outlined ? const OutlineInputBorder() : null,
    );
    return Row(
      children: <Widget>[
        Expanded(
          child: TextFormField(
            controller: controller,
            decoration: inputDecoration,
            validator: validator,
            onChanged: onChanged,
            maxLines: maxLines,
            enabled: enabled,
            keyboardType: keyboardType,
          ),
        ),
        if (trailingIcons != null) ...trailingIcons!,
      ],
    );
  }
}

/// A reusable dropdown field widget supporting label, items, value, onChanged, and validator.
///
/// [T] is the type of the dropdown value.
class LabeledDropdownField<T> extends StatelessWidget {
  /// The label text to display above the dropdown.
  final String label;

  /// The list of dropdown menu items.
  final List<DropdownMenuItem<T>> items;

  /// The currently selected value.
  final T? value;

  /// Callback when the dropdown value changes.
  final void Function(T?)? onChanged;

  /// The validator function for the dropdown value.
  final String? Function(T?)? validator;

  /// Whether to use an outlined border for the dropdown.
  final bool outlined;

  /// Whether the dropdown is enabled for user interaction.
  final bool enabled;

  /// Creates a [LabeledDropdownField] widget.
  ///
  /// [label], [items], and [value] are required. Other parameters are optional.
  const LabeledDropdownField({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    this.onChanged,
    this.validator,
    this.outlined = true,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // InputDecoration for the dropdown, supporting outlined style.
    return DropdownButtonFormField<T>(
      decoration: InputDecoration(
        labelText: label,
        border: outlined ? const OutlineInputBorder() : null,
      ),
      items: items,
      initialValue: value,
      onChanged: enabled ? onChanged : null,
      validator: validator,
      isExpanded: true,
    );
  }
}
