import 'package:flutter/material.dart';

/// DropdownButtonFormField work-alike whose API is stable across SDKs.
///
/// DropdownButtonFormField's selected-value parameter was renamed
/// (`value` → `initialValue`) in newer Flutter while the ohos fork keeps
/// `value` — DropdownButton's parameter has always been `value`, so this
/// wraps it in an InputDecorator for the identical look.
class DropdownField<T> extends StatelessWidget {
  final T? value;
  final String? hint;
  final InputDecoration? decoration;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  const DropdownField({
    super.key,
    this.value,
    this.hint,
    this.decoration,
    required this.items,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final dec = decoration ??
        InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        );
    return InputDecorator(
      decoration: dec,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isDense: true,
          isExpanded: true,
          value: value,
          hint: hint == null ? null : Text(hint!),
          items: items,
          onChanged: onChanged,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
