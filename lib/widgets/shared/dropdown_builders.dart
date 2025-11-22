import 'package:flutter/material.dart';

class DropdownBuilders {
  static List<DropdownMenuEntry<T>> createEntries<T>(
    List<T> values,
    String Function(T) labelBuilder,
  ) {
    return values
        .map((value) => DropdownMenuEntry<T>(
              value: value,
              label: labelBuilder(value),
            ))
        .toList();
  }

  static DropdownMenu<T> buildNumericDropdown<T extends num>({
    required T? initialSelection,
    required List<DropdownMenuEntry<T>> entries,
    required String label,
    required ValueChanged<T?>? onSelected,
    EdgeInsetsGeometry expandedInsets = EdgeInsets.zero,
  }) {
    return DropdownMenu<T>(
      expandedInsets: expandedInsets,
      initialSelection: initialSelection,
      dropdownMenuEntries: entries,
      onSelected: onSelected,
      label: Text(label),
    );
  }
}
